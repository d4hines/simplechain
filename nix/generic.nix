{ pkgs, stdenv, lib, ocamlPackages, static ? false, doCheck }:
with ocamlPackages;
rec {
  simplechain = buildDunePackage {
    pname = "simplechain";
    version = "0.1.0";

    src = lib.filterGitSource {
      src = ./..;
      dirs = [ "src" ];
      files = [ "dune-project" "simplechain.opam" ];
    };

    # Static builds support, note that you need a static profile in your dune file
    buildPhase = ''
      echo "running ${if static then "static" else "release"} build"
      dune build ./src/bin/simplechain.exe --display=short --profile=${if static then "static" else "release"}
    '';
    installPhase = ''
      mkdir -p $out/bin
      mv _build/default/src/bin/simplechain.exe $out/bin/service
    '';

    checkInputs = [
    ];

    propagatedBuildInputs = [
      bin_prot
      ppx_bin_prot
      qcheck
      qcheck-alcotest
      ppx_deriving_qcheck
      alcotest
      preface
    ];

    inherit doCheck;

    meta = {
      description = "Your service";
    };
  };
}
