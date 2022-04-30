{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    ocaml-overlay.url = "github:anmonteiro/nix-overlays";
    ocaml-overlay.inputs.nixpkgs.follows = "nixpkgs";
    ocaml-overlay.inputs.flake-utils.follows = "flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ocaml-overlay }:
    let
      out = system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ ocaml-overlay.overlay (import ./nix/overlay.nix) ];
          };
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
    with flake-utils.lib; eachSystem defaultSystems out;

}
