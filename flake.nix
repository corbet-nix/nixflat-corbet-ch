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
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      # Platform-neutral policy: the apps option, dedup, and conflict guards. Import this
      # directly if you want the shape without the installer.
      nixosModules.nixflat = ./modules/nixflat.nix;
      systemManagerModules.nixflat = ./modules/nixflat.nix;

      # The installer — one file, both planes (see modules/install.nix's own header for why a
      # single implementation is correct here, unlike siblings with genuinely per-platform
      # package names).
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
