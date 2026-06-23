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
          devShells = "tools";
          formatter = "tools";
        };

        partitions = {
          tools = {
            extraInputsFlake = ./tools;

            module =
              {
                ...
              }:
              {
                imports = [
                  ./tools/flake-module.nix
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
          let
            inherit (lib)
              foldl'
              importTOML
              versions
              ;

            inherit (pkgs)
              writeShellApplication
              ;

            crane-lib = (crane.mkLib pkgs);
          in
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
                inherit
                  (crane-lib.overrideToolchain pkgs.rust-bin.stable.latest.default)
                  buildPackage
                  ;

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

                buildTests =
                  emacs:
                  writeShellApplication {
                    name = "emacs${versions.major emacs.version}-jieba-rs-tests";

                    runtimeInputs = [
                      emacs
                    ];

                    text = ''
                      emacs --batch \
                        --eval "(module-load \"${emacs-jieba-rs}/lib/libemacs_jieba_rs.so\")" \
                        -l "${projectRoot + /tests/jieba-rs-tests.el}" \
                        -f ert-run-tests-batch-and-exit
                    '';
                  };
              in
              (foldl'
                (
                  acc: pkg:
                  acc
                  // {
                    "emacs${versions.major pkg.version}-jieba-rs-tests" =
                      buildTests pkg;
                  }
                )
                { }
                (
                  with pkgs;
                  [
                    emacs30
                    emacs31
                  ]
                )
              )
              // {
                inherit
                  emacs-jieba-rs
                  ;
              };
          };

        systems = [
          "x86_64-linux"
        ];
      };
}
