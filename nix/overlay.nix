final: prev:
{
  ocamlPackages = prev.ocamlPackages.overrideScope'
    (oself: osuper:
      with osuper;
      rec {
        preface = buildDunePackage {
          pname = "preface";
          version = "0.1.0";
          src = prev.fetchFromGitHub {
            owner = "xvw";
            repo = "preface";
            rev = "v0.1.0";
            sha256 = "yYzMhAhUAxy9BwZinVq4Zi1WzH0E8T9jHif9QQKcVLk=";
          };
          propagatedBuildInputs = [
            either
          ];
          doCheck = false;
        };
        qcheck-core = osuper.qcheck-core.overrideAttrs (_: rec {
          version = "0.19-dev";
          src = prev.fetchFromGitHub {
            owner = "c-cube";
            repo = "qcheck";
            rev = "824dafb111961ec16bc3526173ad004d45820632";
            sha256 = "sha256-HNV0yVWJlCpjQd4NtSSdTMhYZ9E1Kzg44zlpnHYzwCY=";
          };
        });
        ppx_deriving_qcheck = buildDunePackage {
          pname = "ppx_deriving_qcheck";
          inherit (qcheck-core) version useDune2 src;
          propagatedBuildInputs = [ qcheck-core ppxlib ppx_deriving ];
        };
      });
}
