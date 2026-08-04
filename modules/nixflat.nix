#
# nixflat — the policy layer: which Flatpak apps a host wants, and which remote each one comes
# from. Owns nothing about HOW they get installed (see ./install.nix for the systemd oneshot) —
# this file is importable on its own by a consumer who wants the shape (`nixflat.apps`, the
# deduplication, the conflict guards) without the installer, the same "policy separate from
# backend" split nixmsg/nixoffice/nixmedia already draw for their own catalogues.
#
# THE CONTRACT THIS ACCEPTS. Two catalogues in this project family already emit exactly this
# shape, read-only: `nixmsg.flatpakApps` and `nixoffice.flatpakApps`, both `listOf { id;
# remoteName; remoteUrl; }`. Id and remote travel TOGETHER rather than as two lists a consumer
# must keep indexed in step, because "which remote" is not always Flathub — nixmsg's own
# `ch.threema.threema-desktop` does not exist on Flathub at all, only on Threema GmbH's own
# `releases.threema.ch`. A consumer wires both catalogues in with a plain `++`:
#
#   nixflat.apps = config.nixmsg.flatpakApps ++ config.nixoffice.flatpakApps;
#
# DEDUPLICATION, TWO SHAPES. An app declared by more than one catalogue (or twice by the same
# one) collapses to one install, and a remote named by more than one catalogue collapses to one
# `remote-add` — both handled here so ./install.nix never has to think about it, and so every
# consumer gets the same dedup for free instead of reimplementing it per catalogue. Reimplementing
# it per catalogue is exactly the duplication this repo exists to end.
#
# CONFLICTS ARE REFUSED, NOT ARBITRARILY RESOLVED. Two entries naming the same `id` with a
# DIFFERENT remote, or two remotes sharing a `name` with a DIFFERENT `url`, are not "the same
# thing declared twice" (dedup above collapses that safely) — they are two catalogues disagreeing
# about where an app or a remote actually lives, and `remote-add --if-not-exists` would silently
# let whichever happened to render first win while the other's app never gets its remote added at
# all. An eval-time assertion catches this instead of shipping a host where one catalogue's app
# quietly fails to install.
#
{ config, lib, ... }:
let
  cfg = config.nixflat;

  appType = lib.types.submodule {
    options = {
      id = lib.mkOption {
        type = lib.types.str;
        description = ''Flatpak application ID, e.g. "com.discordapp.Discord".'';
      };
      remoteName = lib.mkOption {
        type = lib.types.str;
        description = ''Name to register the remote under, e.g. "flathub".'';
      };
      remoteUrl = lib.mkOption {
        type = lib.types.str;
        description = ''The remote's .flatpakrepo URL, e.g. "https://flathub.org/repo/flathub.flatpakrepo".'';
      };
      flatpakref = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          URL of this app's `.flatpakref`, for a remote whose `remoteUrl` is a bare ostree repo
          rather than a `.flatpakrepo`. Null (the default) when `remoteUrl` alone is enough.

          THIS IS ABOUT THE SIGNING KEY, not about having a second way to install. A
          `.flatpakrepo` carries the remote's public key inline as `GPGKey=`, so
          `flatpak remote-add <name> <that url>` produces a remote whose summary can actually be
          verified. A bare repo URL carries no key, `remote-add` accepts it anyway, and the
          failure surfaces later and misleadingly as

              error: Unable to load summary from remote <name>:
              Signature made ... using EdDSA key ID ...
              Can't check signature: public key not found

          A `.flatpakref` carries `GPGKey=` the same way a `.flatpakrepo` does, plus the app id
          and `SuggestRemoteName`, so `flatpak install --from <ref>` registers the remote WITH its
          key and installs in one step. For a vendor who publishes only a bare repo and a
          per-app ref -- which is what Threema does -- that is the only mechanism that works at
          all, so it belongs in the catalogue next to the id rather than as host-side setup.
        '';
      };
    };
  };

  remoteType = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.str; };
      url = lib.mkOption { type = lib.types.str; };
    };
  };

  # Exact-duplicate entries (same id, remoteName, AND remoteUrl) collapse to one — two catalogues
  # that happen to agree about an app are not a conflict, just redundant.
  resolvedApps = lib.unique cfg.apps;

  # Group resolved apps by id, then reduce each group to its DISTINCT (remoteName, remoteUrl)
  # pairs. More than one distinct pair for the same id is the ambiguous-app-identity conflict
  # described above.
  distinctRemotesFor = entries: lib.unique (map (a: { inherit (a) remoteName remoteUrl; }) entries);
  byId = lib.groupBy (a: a.id) resolvedApps;
  idConflicts = lib.filterAttrs (_id: entries: lib.length (distinctRemotesFor entries) > 1) byId;

  # Group resolved apps by remoteName, then reduce each group to its DISTINCT urls. More than one
  # distinct url for the same remote name is the ambiguous-remote-identity conflict described
  # above.
  distinctUrlsFor = entries: lib.unique (map (a: a.remoteUrl) entries);
  byRemoteName = lib.groupBy (a: a.remoteName) resolvedApps;
  nameConflicts = lib.filterAttrs (_name: entries: lib.length (distinctUrlsFor entries) > 1) byRemoteName;

  # Every DISTINCT remote the resolved apps actually need, deduplicated by name — built from
  # byRemoteName's own grouping rather than filtering a list, so two apps naming the same remote
  # never produce two `remote-add` lines for it. In the conflict case above, the first url seen
  # wins here — irrelevant to correctness, since the assertion already refuses the build; this
  # value only has to be deterministic, not "right", for a config the build rejects anyway.
  remotes = lib.mapAttrsToList (name: entries: { inherit name; url = lib.head (distinctUrlsFor entries); }) byRemoteName;

  # The remotes ./install.nix must `remote-add` ITSELF, which is not all of them. A remote whose
  # every app carries a `flatpakref` is registered by `flatpak install --from` -- with the signing
  # key that ref carries, which is the whole point -- so pre-adding it here would create the same
  # remote WITHOUT a key first, and `--if-not-exists` would then leave that keyless one in place.
  # Filtering on "every app", not "any app": one app still installing by remote name genuinely
  # needs the remote to exist beforehand.
  refCoveredRemotes = lib.attrNames
    (lib.filterAttrs (_n: entries: lib.all (a: a.flatpakref != null) entries) byRemoteName);
  remotesNeedingAdd = lib.filter (r: !(lib.elem r.name refCoveredRemotes)) remotes;
in
{
  options.nixflat = {
    apps = lib.mkOption {
      type = lib.types.listOf appType;
      default = [ ];
      description = ''
        Flatpak apps to converge onto this host, each carrying its own remote. Feed it every
        catalogue that emits this shape:

          nixflat.apps = config.nixmsg.flatpakApps ++ config.nixoffice.flatpakApps;

        A bare id list is deliberately not accepted here — a consumer that only carried ids could
        only ever assume Flathub, exactly the assumption nixmsg's own Threema entry proved wrong
        (`ch.threema.threema-desktop` does not exist on Flathub at all).

        Deduplicated by exact (id, remoteName, remoteUrl) match. Two entries that share an `id`
        or a `remoteName` but disagree on the rest are a build-time error, not silently resolved
        — see this file's own header.
      '';
    };

    resolvedApps = lib.mkOption {
      type = lib.types.listOf appType;
      readOnly = true;
      internal = true;
      description = "`apps`, deduplicated. What ./install.nix actually installs.";
    };

    remotes = lib.mkOption {
      type = lib.types.listOf remoteType;
      readOnly = true;
      internal = true;
      description = "Every distinct remote `resolvedApps` needs, deduplicated by name.";
    };

    remotesNeedingAdd = lib.mkOption {
      type = lib.types.listOf remoteType;
      readOnly = true;
      internal = true;
      description = ''
        The subset of `remotes` that ./install.nix must `remote-add` itself — those with at least
        one app NOT installed via a `.flatpakref`. A remote every one of whose apps carries a ref
        is registered, with its signing key, by `flatpak install --from`; pre-adding it keyless
        first is what breaks it.
      '';
    };
  };

  config = {
    assertions =
      lib.mapAttrsToList
        (id: entries:
          let distinct = distinctRemotesFor entries; in
          {
            assertion = false;
            message = ''
              nixflat.apps: "${id}" is declared with ${toString (lib.length distinct)} different remotes (${
                lib.concatMapStringsSep ", " (r: "${r.remoteName} -> ${r.remoteUrl}") distinct
              }) — two catalogues disagree about where this app lives. Fix one of them rather than
              letting `remote-add --if-not-exists` silently pick whichever renders first.
            '';
          })
        idConflicts
      ++ lib.mapAttrsToList
        (name: entries:
          let distinct = distinctUrlsFor entries; in
          {
            assertion = false;
            message = ''
              nixflat.apps: remote "${name}" is declared with ${toString (lib.length distinct)} different URLs (${
                lib.concatStringsSep ", " distinct
              }) — two catalogues disagree about what this remote points to.
            '';
          })
        nameConflicts;

    nixflat.resolvedApps = resolvedApps;
    nixflat.remotes = remotes;
    nixflat.remotesNeedingAdd = remotesNeedingAdd;
  };
}
