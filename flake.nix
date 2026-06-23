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
      self,
      ...
    }:
    let
      inherit (flake-parts.lib)
        mkFlake
        ;

      projectRoot = ./.;
    in
    mkFlake
      {
        inherit
          inputs
          ;

        specialArgs = {
          inherit
            projectRoot
            ;
        };
      }
      {
        imports = [
          flake-parts.flakeModules.partitions
        ];

        flake = {
          overlays = {
            default =
              final: prev:
              let
                inherit (prev)
                  emacsPackagesFor
                  ;

                crane-lib = (crane.mkLib prev.pkgs);

                buildCargoPackage =
                  (crane-lib.overrideToolchain prev.pkgs.rust-bin.stable.latest.default)
                  .buildPackage;

                package =
                  {
                    buildCargoPackage,
                    cleanCargoSource,
                    lib,
                    pkgs,
                    stdenv,
                    melpaBuild,
                    projectRoot,
                    writeText,
                    ...
                  }:
                  let
                    inherit (lib)
                      importTOML
                      licenses
                      maintainers
                      ;

                    ext =
                      stdenv.hostPlatform.extensions.sharedLibrary;

                    meta = {
                      description = "jieba-rs for GNU Emacs";
                      homepage = "https://codeberg.org/bingshan/emacs-jieba-rs";
                      license = licenses.gpl3Plus;
                      maintainers = with maintainers; [ brsvh ];
                    };

                    cargoFile = projectRoot + /Cargo.toml;

                    version = (importTOML cargoFile).package.version;

                    module = buildCargoPackage {
                      inherit
                        version
                        ;

                      cargoExtraArgs = "--lib";
                      doCheck = true;
                      pname = "emacs-jieba-rs-module";
                      src = cleanCargoSource projectRoot;
                    };

                    src = projectRoot + /lisp;
                  in
                  melpaBuild {
                    inherit
                      meta
                      src
                      version
                      ;

                    pname = "jieba-rs";

                    preBuild = ''
                      install -m 755 ${module}/lib/libjieba_rs_module${ext} jieba-rs-module${ext}
                    '';

                    files = ''(:defaults "jieba-rs-module${ext}")'';

                    passthru = {
                      inherit
                        module
                        ;
                    };
                  };

                scope = finalAttrs: prevAttrs: {
                  jieba-rs = finalAttrs.callPackage package {
                    inherit (crane-lib)
                      cleanCargoSource
                      ;

                    inherit
                      buildCargoPackage
                      projectRoot
                      ;
                  };
                };
              in
              (rust-overlay.overlays.default final prev)
              // {
                emacsPackagesFor =
                  emacs:
                  (emacsPackagesFor emacs).overrideScope scope;
              };
          };
        };

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
            system,
            ...
          }:
          let
            inherit (lib)
              foldl'
              versions
              ;
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
                    self.overlays.default
                  ];
                };
              };
            };

            packages =
              foldl'
                (
                  acc: base:
                  let
                    inherit (pkgs)
                      emacsPackagesFor
                      writeShellApplication
                      ;

                    version = "${versions.major base.version}";

                    emacs =
                      (emacsPackagesFor base).emacsWithPackages
                        (
                          epkgs: with epkgs; [
                            jieba-rs
                          ]
                        );
                  in
                  acc
                  // {
                    "emacs${version}-with-jieba-rs" =
                      writeShellApplication
                        {
                          name = "emacs${version}-with-jieba-rs";

                          runtimeInputs = [
                            emacs
                          ];

                          text = ''
                            exec emacs --init-directory "$(mktemp -d)" "$@"
                          '';
                        };

                    "emacs${version}-run-jieba-rs-tests" =
                      writeShellApplication
                        {
                          name = "emacs${version}-run-jieba-rs-tests";

                          runtimeInputs = [
                            emacs
                          ];

                          text = ''
                            initdir="$(mktemp --tmpdir -d emacs-jieba-rs-test-XXXXXX)"
                            trap 'rm -rf "$initdir"' EXIT

                            emacs --batch \
                              --init-directory "$initdir" \
                              -l "${projectRoot + /tests/jieba-rs-tests.el}" \
                              -f ert-run-tests-batch-and-exit
                          '';
                        };
                  }
                )
                { }
                (
                  with pkgs;
                  [
                    emacs30
                    emacs31
                  ]
                );
          };

        systems = [
          "x86_64-linux"
        ];
      };
}
