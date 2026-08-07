#
# Arch / system-manager backend. The APP install is identical to modules/nixos.nix's — Flatpak
# install has no platform divergence to backend around — see that file's own header for why this
# stays a separate file rather than collapsing both flake outputs onto one path, and for the one
# thing that now DOES diverge: the `flatpak` runtime package.
#
# Unlike the NixOS plane, there is nothing to wire here: on Arch, the package name IS the whole
# story (installing `flatpak` is enabling it, no separate D-Bus/systemd registration step exists
# to ask for), and this backend has no reconciler of its own to hand it to — see
# ./nixflat.nix's `archPackages` option, published read-only for whatever consumer's
# `nixarch.packages.pacman` (or equivalent) wants to pick it up, the same "publish a package list,
# let the consumer wire it in" boundary nixbmc's own `archPackages` draws for itself.
#
{ ... }:
{
  imports = [ ./install.nix ];
}
