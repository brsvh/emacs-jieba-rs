{
  description = "jieba-rs for GNU Emacs";

  inputs = {
    flake-parts = {
      inputs = {
        nixpkgs-lib = {
          follows = "nixpkgs";
        };
      };

      url = "git+https://github.com/hercules-ci/flake-parts.git?ref=main";
    };

    nixpkgs = {
      url = "git+https://github.com/NixOS/nixpkgs.git?ref=nixos-unstable";
    };
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      ...
    }:
    let
      inherit (flake-parts.lib)
        mkFlake
        ;
    in
    mkFlake
      {
        inherit
          inputs
          ;
      }
      {
        imports = [
          flake-parts.flakeModules.partitions
        ];

        partitionedAttrs = {
          devShells = "build-aux";
          formatter = "build-aux";
        };

        partitions = {
          build-aux = {
            extraInputsFlake = ./build-aux;

            module =
              {
                ...
              }:
              {
                imports = [
                  ./build-aux/flake-module.nix
                ];
              };
          };
        };

        perSystem =
          {
            system,
            ...
          }:
          {
            _module = {
              args = {
                projectRoot = ./.;
              };
            };
          };

        systems = [
          "x86_64-linux"
        ];
      };
}
