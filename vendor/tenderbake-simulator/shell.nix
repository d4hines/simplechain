{ pkgs ? (import ./nix/nixpkgs {})
}:

pkgs.mkShell {
  inputsFrom = [(import ./default.nix { inherit pkgs; })];
  buildInputs = with pkgs.ocamlPackages; [
    ocamlformat
    ocaml-lsp
    odoc
    utop
  ];
  shellHook = ''
    
  '';
}
