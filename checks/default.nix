# checks/default.nix
#
# EVAL-TIME checks for modules/nixflat.nix's dedup/conflict logic and modules/install.nix's
# rendering of it — the same `lib.evalModules` + stubbed option-surface technique nixmsg's own
# checks/default.nix uses (see that file's own header): no real NixOS/system-manager evaluation,
# because what is under test is only what these two files RENDER (an option value, a systemd unit
# script, an assertions list), never whether `flatpak` on a real host actually converges.
#
# THE BUG THIS SUITE EXISTS TO CATCH, PERMANENTLY. nixmsg's own flatpak-install.nix once
# hardcoded Flathub as the only remote it would ever `remote-add` or install from — silently
# unable to install its own `threema` entry (`ch.threema.threema-desktop`, which does not exist
# on Flathub at all; the real client is only ever distributed from Threema GmbH's own
# `releases.threema.ch`). Every non-Flathub fixture below proves BOTH directions: the right
# remote gets `remote-add`'d and installed from, AND Flathub does NOT get added when nothing
# declared here needs it — a suite that only checked the first half would pass just as happily on
# a version that added every known remote unconditionally, which is not the property this exists
# to guard. See ../README.md's "Proof the checks are non-vacuous" section for the reintroduce-
# the-bug-and-watch-it-fail run this suite's existence is checked against.
{ pkgs }:
let
  lib = pkgs.lib;

  # Stub of the surface only NixOS/system-manager itself provides — `systemd.services` opaque the
  # same way nixmsg's own checks/default.nix stubs it (a single definition per key is all
  # modules/install.nix ever contributes), plus `assertions`, which modules/nixflat.nix writes to
  # unconditionally (the id/remote-conflict guards) even though most fixtures below never trip it.
  systemSurfaceStub = { lib, ... }: {
    options = {
      systemd.services = lib.mkOption { type = lib.types.attrsOf lib.types.attrs; default = { }; };
      assertions = lib.mkOption { type = lib.types.listOf lib.types.attrs; default = [ ]; };
    };
  };

  evalMod = extraConfig: (lib.evalModules {
    modules = [
      systemSurfaceStub
      { _module.args.pkgs = pkgs; }
      ../modules/nixflat.nix
      ../modules/install.nix
      extraConfig
    ];
  }).config;

  check = name: ok: detail: { inherit name ok detail; };

  scriptOf = cfg: cfg.systemd.services.nixflat-install.script or "";
  linesOf = script: lib.splitString "\n" script;

  flathub = { remoteName = "flathub"; remoteUrl = "https://flathub.org/repo/flathub.flatpakrepo"; };
  threema = { remoteName = "threema-desktop"; remoteUrl = "https://releases.threema.ch/flatpak/threema-desktop/"; };

  # ── Fixture 1: ONLY a non-Flathub app declared ──
  cfgNonFlathubOnly = evalMod {
    nixflat.apps = [{ id = "ch.threema.threema-desktop"; inherit (threema) remoteName remoteUrl; }];
  };

  # ── Fixture 2: ONLY a genuine Flathub app declared — the unaffected case the fix must not
  # regress ──
  cfgFlathubOnly = evalMod {
    nixflat.apps = [{ id = "com.discordapp.Discord"; inherit (flathub) remoteName remoteUrl; }];
  };

  # ── Fixture 3: BOTH together — proves no cross-wiring between the two remotes ──
  cfgMixed = evalMod {
    nixflat.apps = [
      { id = "ch.threema.threema-desktop"; inherit (threema) remoteName remoteUrl; }
      { id = "com.discordapp.Discord"; inherit (flathub) remoteName remoteUrl; }
    ];
  };

  # ── Fixture 4: nothing declared at all — the oneshot must stay a clean no-op ──
  cfgEmpty = evalMod { };

  # ── Fixture 5: two DIFFERENT apps from two (hypothetical) catalogues naming the SAME remote —
  # one `remote-add`, not two ──
  cfgSharedRemote = evalMod {
    nixflat.apps = [
      { id = "com.discordapp.Discord"; inherit (flathub) remoteName remoteUrl; }
      { id = "org.libreoffice.LibreOffice"; inherit (flathub) remoteName remoteUrl; }
    ];
  };

  # ── Fixture 6: the exact same app declared twice (e.g. by two catalogues that both want it) —
  # one install line, not two ──
  cfgExactDuplicate = evalMod {
    nixflat.apps = [
      { id = "com.discordapp.Discord"; inherit (flathub) remoteName remoteUrl; }
      { id = "com.discordapp.Discord"; inherit (flathub) remoteName remoteUrl; }
    ];
  };

  # ── Fixture 7: same id, two DIFFERENT remotes — a real conflict, must be refused rather than
  # silently letting one win ──
  cfgIdConflict = evalMod {
    nixflat.apps = [
      { id = "com.discordapp.Discord"; inherit (flathub) remoteName remoteUrl; }
      { id = "com.discordapp.Discord"; remoteName = "some-other-remote"; remoteUrl = "https://example.com/repo"; }
    ];
  };

  # ── Fixture 8: same remote name, two DIFFERENT urls — a real conflict, must be refused ──
  cfgRemoteConflict = evalMod {
    nixflat.apps = [
      { id = "com.discordapp.Discord"; remoteName = "flathub"; remoteUrl = "https://flathub.org/repo/flathub.flatpakrepo"; }
      { id = "org.libreoffice.LibreOffice"; remoteName = "flathub"; remoteUrl = "https://example.com/not-flathub"; }
    ];
  };

  results = [
    # ── the bug this suite exists to catch, permanently ──
    (check "non-flathub/adds-its-own-remote"
      (lib.hasInfix "flatpak remote-add --system --if-not-exists threema-desktop https://releases.threema.ch/flatpak/threema-desktop/" (scriptOf cfgNonFlathubOnly))
      "script: ${scriptOf cfgNonFlathubOnly}")

    (check "non-flathub/does-not-add-flathub"
      (!(lib.hasInfix "remote-add --system --if-not-exists flathub" (scriptOf cfgNonFlathubOnly)))
      "script: ${scriptOf cfgNonFlathubOnly}")

    (check "non-flathub/installs-from-its-own-remote-not-flathub"
      (lib.hasInfix "flatpak install --system --noninteractive threema-desktop ch.threema.threema-desktop" (scriptOf cfgNonFlathubOnly)
        && !(lib.hasInfix "flatpak install --system --noninteractive flathub ch.threema.threema-desktop" (scriptOf cfgNonFlathubOnly)))
      "script: ${scriptOf cfgNonFlathubOnly}")

    # ── the flip side: a genuine Flathub app is unaffected ──
    (check "flathub-only/adds-flathub-remote"
      (lib.hasInfix "flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo" (scriptOf cfgFlathubOnly))
      "script: ${scriptOf cfgFlathubOnly}")

    (check "flathub-only/does-not-add-threema-remote"
      (!(lib.hasInfix "threema-desktop" (scriptOf cfgFlathubOnly)))
      "script: ${scriptOf cfgFlathubOnly}")

    (check "flathub-only/installs-discord-from-flathub"
      (lib.hasInfix "flatpak install --system --noninteractive flathub com.discordapp.Discord" (scriptOf cfgFlathubOnly))
      "script: ${scriptOf cfgFlathubOnly}")

    # ── mixed: BOTH remotes present, each app installs from ITS OWN remote, never crossed ──
    (check "mixed/adds-both-remotes"
      (lib.hasInfix "remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo" (scriptOf cfgMixed)
        && lib.hasInfix "remote-add --system --if-not-exists threema-desktop https://releases.threema.ch/flatpak/threema-desktop/" (scriptOf cfgMixed))
      "script: ${scriptOf cfgMixed}")

    (check "mixed/threema-installs-from-threema-remote"
      (lib.hasInfix "flatpak install --system --noninteractive threema-desktop ch.threema.threema-desktop" (scriptOf cfgMixed))
      "script: ${scriptOf cfgMixed}")

    (check "mixed/discord-installs-from-flathub-not-threema-remote"
      (lib.hasInfix "flatpak install --system --noninteractive flathub com.discordapp.Discord" (scriptOf cfgMixed)
        && !(lib.hasInfix "flatpak install --system --noninteractive threema-desktop com.discordapp.Discord" (scriptOf cfgMixed)))
      "script: ${scriptOf cfgMixed}")

    # ── nothing declared: the oneshot renders no unit at all ──
    (check "empty/unit-absent"
      (!(cfgEmpty.systemd.services ? "nixflat-install"))
      "systemd.services keys: ${builtins.toJSON (builtins.attrNames cfgEmpty.systemd.services)}")

    # ── dedup: same remote named by two different apps produces ONE remote-add ──
    (check "dedup/shared-remote-adds-once"
      (lib.length (lib.filter (l: lib.hasInfix "remote-add --system --if-not-exists flathub " l) (linesOf (scriptOf cfgSharedRemote))) == 1)
      "script: ${scriptOf cfgSharedRemote}")

    (check "dedup/shared-remote-still-installs-both-apps"
      (lib.hasInfix "flatpak install --system --noninteractive flathub com.discordapp.Discord" (scriptOf cfgSharedRemote)
        && lib.hasInfix "flatpak install --system --noninteractive flathub org.libreoffice.LibreOffice" (scriptOf cfgSharedRemote))
      "script: ${scriptOf cfgSharedRemote}")

    # ── dedup: the exact same app declared twice installs ONCE ──
    (check "dedup/exact-duplicate-app-installs-once"
      (lib.length (lib.filter (l: lib.hasInfix "flatpak install --system --noninteractive flathub com.discordapp.Discord" l) (linesOf (scriptOf cfgExactDuplicate))) == 1)
      "script: ${scriptOf cfgExactDuplicate}")

    # ── conflicts are refused, not arbitrarily resolved ──
    (check "conflict/same-id-different-remote-is-refused"
      (lib.any (a: a.assertion == false) cfgIdConflict.assertions)
      "assertions: ${builtins.toJSON cfgIdConflict.assertions}")

    (check "conflict/same-remote-name-different-url-is-refused"
      (lib.any (a: a.assertion == false) cfgRemoteConflict.assertions)
      "assertions: ${builtins.toJSON cfgRemoteConflict.assertions}")

    # ── the happy-path fixtures above must NOT trip any conflict assertion ──
    (check "no-false-positive/mixed-has-no-assertions"
      (cfgMixed.assertions == [ ])
      "assertions: ${builtins.toJSON cfgMixed.assertions}")
  ];

  failed = builtins.filter (r: !r.ok) results;

  report = lib.concatMapStringsSep "\n" (r: "  - ${r.name}: ${r.detail}") failed;

  eval-checks =
    if failed != [ ]
    then
      throw ''
        nixflat eval-checks FAILED (${toString (builtins.length failed)}/${toString (builtins.length results)}):
        ${report}
      ''
    else
    # Depending on `passedCount` forces `results` (and every `check` assertion above), so the
    # checks genuinely run under `nix flake check` rather than merely being defined.
      pkgs.runCommand "nixflat-eval-checks"
        { passedCount = toString (builtins.length results); }
        ''
          echo "all $passedCount nixflat eval checks passed"
          touch $out
        '';
in
{
  inherit eval-checks;
}
