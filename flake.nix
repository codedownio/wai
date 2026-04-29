{
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.gitignore = {
    url = "github:hercules-ci/gitignore.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/master";

  outputs = { self, flake-utils, gitignore, nixpkgs }:
    flake-utils.lib.eachSystem ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"] (system:
      let
	      pkgs = import nixpkgs { inherit system; };

      in
        {
          devShells = {
            default = pkgs.mkShell {
              NIX_PATH = "nixpkgs=${pkgs.path}";
              buildInputs = with pkgs; [
                haskell.compiler.ghc9124

                pcre
                zlib
              ];
            };
          };

          packages = ({

          });
        }
    );
}
