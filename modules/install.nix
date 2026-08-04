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
# THE flatpak PACKAGE ITSELF: provided to THIS UNIT's own PATH only (below), never declared onto
# the host at large. This module's job stops at "the declared app IDs exist on the host" — an
# interactive `flatpak` CLI on a user's own $PATH, `services.flatpak` (NixOS's D-Bus/portal
# integration), or an Arch `flatpak` reconciler entry are desktop-integration policy decisions,
# and none of them are this module's to make on a consumer's behalf, the same boundary nixmsg's
# own header draws around its identical installer (autostart, workspace-pin, and compositor
# wiring all live OUTSIDE that repo's installer for the same reason). See README.md for the full
# reasoning and what a consumer who wants portal integration adds themselves.
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
      script = ''
        set -eu
        ${lib.concatMapStringsSep "\n" (r: ''
          flatpak remote-add --system --if-not-exists ${r.name} ${r.url}
        '') cfg.remotes}
        ${lib.concatMapStringsSep "\n" (a: ''
          if ! flatpak info --system ${a.id} >/dev/null 2>&1; then
            flatpak install --system --noninteractive ${a.remoteName} ${a.id}
          fi
        '') cfg.resolvedApps}
      '';
    };
  };
}
