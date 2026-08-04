#
# Arch / system-manager backend. Identical body to modules/nixos.nix — see that file's own header
# for why this stays a separate file rather than collapsing both flake outputs onto one path.
#
{ ... }:
{
  imports = [ ./install.nix ];
}
