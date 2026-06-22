{
  description = "jieba-rs for GNU Emacs";

  inputs = {
    crane = {
      url = "git+https://github.com/ipetkov/crane.git?ref=refs/tags/v0.23.4";
    };

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

    rust-overlay = {
      inputs = {
        nixpkgs = {
          follows = "nixpkgs";
        };
      };

      url = "git+https://github.com/oxalica/rust-overlay.git?ref=master";
    };
  };

  outputs =
    inputs@{
      crane,
      flake-parts,
      nixpkgs,
      rust-overlay,
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
            lib,
            pkgs,
            projectRoot,
            system,
            ...
          }:
          {
            _module = {
              args = {
                pkgs = import nixpkgs {
                  inherit
                    system
                    ;

                  overlays = [
                    rust-overlay.overlays.default
                  ];
                };

                projectRoot = ./.;
              };
            };

            packages =
              let
                crane-lib = (crane.mkLib pkgs);

                inherit
                  (crane-lib.overrideToolchain pkgs.rust-bin.stable.latest.default)
                  buildPackage
                  ;

                inherit (lib)
                  importTOML
                  ;
              in
              {
                emacs-jieba-rs =
                  let
                    src = projectRoot;
                    cargoFile = projectRoot + /Cargo.toml;
                    version = (importTOML cargoFile).package.version;
                  in
                  buildPackage {
                    inherit
                      src
                      version
                      ;

                    pname = "emacs-jieba-rs";
                    cargoExtraArgs = "--lib";
                    doCheck = true;
                  };
              };
          };

        systems = [
          "x86_64-linux"
        ];
      };
}
