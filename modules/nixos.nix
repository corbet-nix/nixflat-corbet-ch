#
# NixOS backend. Nothing here diverges from modules/arch.nix — Flatpak install is identical on
# every distro, unlike nixmsg/nixoffice's repo/AUR channels, which genuinely need a per-platform
# package name. Kept as its own file anyway, matching the family's per-plane output convention
# (nixosModules.default / systemManagerModules.default each independently importable), so a
# future NixOS-specific need — e.g. wiring `services.flatpak` for desktop-portal integration, a
# decision this repo deliberately does not make, see ./install.nix's own header — has an obvious,
# non-breaking place to land instead of forcing a flake-output rename.
#
{ ... }:
{
  imports = [ ./install.nix ];
}
