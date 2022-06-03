{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = { self, nixpkgs, flake-utils }: flake-utils.lib.eachDefaultSystem (system:
    let pkgs = nixpkgs.legacyPackages."${system}";
    in
    {
      packages = rec {
        tenderbatter = import ./. { inherit pkgs; };
        default = tenderbatter;
      };
      devShell = import ./shell.nix { inherit pkgs; };
    });
}
