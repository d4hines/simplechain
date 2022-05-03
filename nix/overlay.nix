{ tenderbake-simulator }: final: prev:
{
  ocamlPackages = prev.ocamlPackages.overrideScope'
    (oself: osuper:
      with oself;
      {
        preface = buildDunePackage {
          pname = "preface";
          version = "0.1.0";
          useDune2 = true;
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
          useDune2 = true;
          src = prev.fetchFromGitHub {
            owner = "c-cube";
            repo = "qcheck";
            rev = "824dafb111961ec16bc3526173ad004d45820632";
            sha256 = "sha256-HNV0yVWJlCpjQd4NtSSdTMhYZ9E1Kzg44zlpnHYzwCY=";
          };
        });
        ppx_deriving_qcheck = buildDunePackage {
          pname = "ppx_deriving_qcheck";
          inherit (qcheck-core) version src;
          useDune2 = true;
          propagatedBuildInputs = [ qcheck-core ppxlib ppx_deriving ];
        };
        ppx_deriving_encoding = buildDunePackage {
          pname = "ppx_deriving_encoding";
          version = "dev";
          useDune2 = true;
          src = prev.fetchFromGitLab {
            owner = "o-labs";
            repo = "ppx_deriving_encoding";
            rev = "a8f7c425baa3cfad53756de91e962fdfc755d675";
            sha256 = "sha256-rKOum9leE+7JHW/3wEvFznMRgsY0xdS+v/AL+gIv1EY=";
          };
          propagatedBuildInputs = [ ppxlib json-data-encoding ];
        };
        tenderbatter = tenderbake-simulator;
      });
}
