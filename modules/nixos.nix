#
# NixOS backend. The APP install itself is byte-identical to modules/arch.nix — Flatpak install
# has no platform divergence, unlike nixmsg/nixoffice's repo/AUR channels, which genuinely need a
# per-platform package name — but the RUNTIME package now does diverge, which is exactly the
# future need this file was kept separate from arch.nix to leave room for (see this file's own
# history: it used to be a bare `imports`, identical to arch.nix, with this comment naming
# `services.flatpak` as the not-yet-made decision).
#
# `services.flatpak.enable`, NOT `environment.systemPackages = [ pkgs.flatpak ]`. This is an
# upstream nixpkgs module (nixos/modules/services/desktops/flatpak.nix), and it is the package
# AND the D-Bus/systemd registration in one step — `cfg.package` lands in
# `environment.systemPackages` as a side effect of enabling it, so there is no second line to add
# for the package itself. The asymmetry with modules/arch.nix's plain pacman name is the same one
# nixdesktop's `portals` role draws between its own two planes: on Arch, installing the package IS
# enabling it; on NixOS, a package alone can be present and still not registered with anything.
#
# GATED ON THE SAME SIGNAL AS EVERYTHING ELSE HERE: `resolvedApps != [ ]`, computed once in
# ./nixflat.nix and re-read here rather than re-derived, so a consumer who imports this flake but
# declares no apps gains nothing extra — this plane's exact counterpart to ./nixflat.nix's own
# `archPackages` for the Arch/system-manager plane.
{ config, lib, ... }:
let
  cfg = config.nixflat;
in
{
  imports = [ ./install.nix ];

  config = lib.mkIf (cfg.resolvedApps != [ ]) {
    services.flatpak.enable = true;
  };
}
