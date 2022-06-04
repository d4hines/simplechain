{
  # Setup trusted binary caches
  nixConfig = {
    trusted-substituters =
      [ "https://cache.nixos.org/" "https://anmonteiro.cachix.org" ];
    trusted-public-keys = [ "anmonteiro.cachix.org-1:KF3QRoMrdmPVIol+I2FGDcv7M7yUajp4F2lt0567VA4=" ];
  };
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:anmonteiro/nix-overlays";
  };
  outputs = { self, nixpkgs, flake-utils }:
    let
      out = system:
        let
          my-overlay = import ./nix/overlay.nix;
          pkgs = nixpkgs.legacyPackages."${system}".extend my-overlay;
          inherit (pkgs) lib;
          myPkgs = pkgs.recurseIntoAttrs (import ./nix {
            inherit pkgs;
            doCheck = true;
          }).native;
          myDrvs = lib.filterAttrs (_: value: lib.isDerivation value) myPkgs;
        in
        {
          devShell = (pkgs.mkShell {
            inputsFrom = lib.attrValues myDrvs;
            buildInputs = with pkgs;
              with ocamlPackages; [
                utop
                ocaml-lsp
                ocamlformat
                ocamlformat-rpc
                odoc
                ocaml
                dune_3
                nixfmt
              ];
          });

          defaultPackage = myPkgs.simplechain;

          defaultApp =
            flake-utils.lib.mkApp { drv = self.defaultPackage."${system}"; };

        };
    in
    with flake-utils.lib;
    eachSystem defaultSystems out;

}
