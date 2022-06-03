{ pkgs ? (import ./nix/nixpkgs {})
}:

pkgs.ocamlPackages.buildDunePackage {
  pname = "tenderbatter";
  version = "0.0.1.0";
  useDune2 = true;
  src = pkgs.lib.sourceByRegex ./. [
    "^.ocamlformat$"
    "^dune-project$"
    "^src.*$"
    "^tenderbatter.opam$"
    "^test.*$"
  ];
  propagatedBuildInputs = with pkgs.ocamlPackages; [
    (import ./nix/data-encoding { inherit pkgs; })
    alcotest
    base64
    bheap
    crowbar
    cryptokit
    ezjsonm
    owl-base
  ];
  doCheck = false;
}
