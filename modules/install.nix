#
# nixflat's installer — the systemd oneshot that converges installed Flatpak app IDs toward
# `nixflat.resolvedApps`. Extracted from nixmsg's `modules/flatpak-install.nix` (that file's own
# header carries the full history of the remote-aware fix this preserves); the behavior below is
# identical, generalized to read `config.nixflat.*` — already deduplicated and conflict-checked
# by ./nixflat.nix — instead of a catalogue this repo has no opinion about.
#
# ONE FILE, BOTH PLANES. Imported unmodified by both modules/nixos.nix and modules/arch.nix —
# Flatpak is cross-distro, so nothing about "which app IDs are installed" differs between them,
# the same conclusion nixmsg's own header reaches for its identical file.
#
# --system SCOPE, DELIBERATELY, NOT --user. A system-level module (NixOS or system-manager, never
# home-manager) has no user session to run a --user install as without extra per-host wiring (a
# target username, that user's XDG_RUNTIME_DIR/D-Bus session). --system needs none of that — it
# runs as the oneshot's own root user and the app becomes available to every user on the host,
# correct for a single-operator workstation (every host this targets has exactly one real user).
#
# IDEMPOTENT AND IMPERATIVE, ON PURPOSE. `flatpak install` is not a Nix-store artifact — the app
# lives in Flatpak's own runtime-managed tree (/var/lib/flatpak), outside Nix's reach entirely,
# same as pacman/AUR packages are outside it. This oneshot's job is only to converge "which app
# IDs are installed" toward the declared set on every activation; it does not manage updates
# (Flatpak's own auto-update handles that) and does not remove an app later dropped from the
# declared list — same "declaring is not pruning" posture nixarch's own `pruneUndeclared` takes,
# deliberately not solved here either.
#
# THE flatpak PACKAGE ITSELF, FOR THIS UNIT: provided to THIS unit's own PATH only (below),
# independent of whatever the host declares at large — this oneshot needs `flatpak` on its PATH
# regardless of whether an interactive CLI or `services.flatpak` also happen to put it there, so
# it names its own copy rather than assuming one of those already ran first.
#
# THE flatpak PACKAGE ITSELF, FOR THE HOST: no longer this file's call, and no longer absent
# either — it is now owned by the two plane-specific backends, gated on the same
# `resolvedApps != [ ]` this unit itself renders on: ./nixflat.nix's `archPackages` (a pacman name
# published for whatever reconciler a system-manager consumer runs) and ./nixos.nix's
# `services.flatpak.enable` (the upstream option that both installs the package and registers it
# with D-Bus/systemd, not a bare package name). What this module still does NOT decide is
# desktop-integration policy one layer up — an interactive `flatpak` CLI on a user's own
# non-system $PATH, portal-BACKEND selection, autostart, workspace-pin, or compositor wiring are
# all still a consumer's own call, the same boundary nixmsg's own header draws around its
# identical installer for that layer. See README.md for the full reasoning and what a consumer
# who wants deeper desktop integration adds themselves.
#
{ config, lib, pkgs, ... }:
let
  cfg = config.nixflat;
in
{
  imports = [ ./nixflat.nix ];

  config = lib.mkIf (cfg.resolvedApps != [ ]) {
    systemd.services.nixflat-install = {
      description = "nixflat: converge declared Flatpak apps";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.flatpak ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      # An app carrying a `flatpakref` is installed with `--from`, which registers its remote
      # (name, url AND signing key, all three read out of the ref) and installs in one step. Its
      # remote is therefore NOT pre-added by the remote-add pass below: `remote-add` against a
      # bare ostree repo url succeeds while importing no key, and a keyless remote already
      # present is exactly what makes the later `--from` unable to verify the summary it just
      # fetched. Add it once, correctly, or not at all -- see ./nixflat.nix's `flatpakref` option
      # for the error this produces when both happen.
      script = ''
        set -eu
        ${lib.concatMapStringsSep "\n" (r: ''
          flatpak remote-add --system --if-not-exists ${r.name} ${lib.escapeShellArg r.url}
        '') cfg.remotesNeedingAdd}
        ${lib.concatMapStringsSep "\n" (a: ''
          if ! flatpak info --system ${lib.escapeShellArg a.id} >/dev/null 2>&1; then
            ${if a.flatpakref != null
              then "flatpak install --system --noninteractive --from ${lib.escapeShellArg a.flatpakref}"
              else "flatpak install --system --noninteractive ${lib.escapeShellArg a.remoteName} ${lib.escapeShellArg a.id}"}
          fi
        '') cfg.resolvedApps}
      '';
    };
  };
}
