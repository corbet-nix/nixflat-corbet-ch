# SPDX-License-Identifier: MIT OR Apache-2.0
{
  description = "nixflat — Flatpak as a declarative delivery channel: one place installing apps by Flatpak ID and remote, instead of a copy per catalogue";

  # NO INPUTS FOR CONSUMERS. Same reasoning as nixmsg/nixoffice/nixmedia: this flake is options
  # plus an installer, taking `pkgs` from the consumer's own evaluation rather than pinning a
  # nixpkgs, so composing it never adds a second nixpkgs — or a sibling flake's whole input
  # closure — to a real host's closure.
  inputs = {
    # checks-only, same convention the rest of this family uses: the modules themselves take
    # `pkgs` from whatever evaluation composes them (never from this input directly), so a
    # consumer who doesn't `follow` this flake's `checks` output pays no second nixpkgs fetch for
    # it.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      # ONLY THE SYSTEM THESE CHECKS CAN GENUINELY BE BUILT ON, which is the narrower claim and the
      # honest one. The eval checks are real derivations, and an aarch64-linux derivation cannot be
      # built by an x86_64 runner, so declaring aarch64 bought no coverage whatsoever: a bare
      # `nix flake check` answered with "The check omitted these incompatible systems:
      # aarch64-linux" and exited 0 — CI reported green having evaluated half of what this flake
      # claimed, which for this repo included the non-Flathub regression guard below.
      #
      # Keeping aarch64 and dropping `--all-systems` is the worse trade and the one this family
      # refuses. Narrow the claim, keep the check strict — see .github/workflows/ci.yml.
      #
      # Nothing else narrows: the modules take `pkgs` from whatever evaluation composes them, so a
      # consumer still gets this on any platform. Only `checks` and `formatter` were ever
      # system-scoped here.
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      # Platform-neutral policy: the apps option, dedup, and conflict guards, plus (since the
      # `flatpak` runtime package became this repo's job too) `archPackages`, the pacman-name
      # half of that decision. Import this directly if you want the shape without the installer.
      nixosModules.nixflat = ./modules/nixflat.nix;
      systemManagerModules.nixflat = ./modules/nixflat.nix;

      # The installer — one file, both planes for the APP install (see modules/install.nix's own
      # header for why a single implementation is correct here, unlike siblings with genuinely
      # per-platform package names). The `flatpak` RUNTIME package now diverges per plane instead:
      # modules/nixos.nix wires the upstream `services.flatpak.enable` option, modules/arch.nix
      # has nothing to wire (the pacman name published as `archPackages` above is enough) — see
      # each file's own header.
      nixosModules.default = ./modules/nixos.nix;
      nixosModules.install = ./modules/nixos.nix;
      systemManagerModules.default = ./modules/arch.nix;

      # EVAL-TIME checks only — see checks/default.nix's own header for what's under test and why
      # it exists (modules/nixflat.nix's dedup/conflict logic, and modules/install.nix's
      # remote-aware rendering of it).
      checks = forAllSystems (system: import ./checks { pkgs = pkgsFor system; });

      formatter = forAllSystems (system: (pkgsFor system).nixpkgs-fmt);
    };
}
