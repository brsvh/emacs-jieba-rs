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

            jiebaRsSource = projectRoot + /lisp/jieba-rs.el;

            jiebaRsTestSource =
              projectRoot + /tests/jieba-rs-tests.el;

            release = with pkgs; emacsPackagesFor emacs31;
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

            packages = {
              inherit (release)
                jieba-rs
                ;

              jieba-rs-module = release.jieba-rs.module;
            }
            //
              foldl'
                (
                  acc: base:
                  let
                    inherit (pkgs)
                      coreutils
                      emacsPackagesFor
                      gnugrep
                      writeShellApplication
                      ;

                    version = "${versions.major base.version}";

                    emacsWithJiebaRs =
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
                            emacsWithJiebaRs
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
                            coreutils
                            emacsWithJiebaRs
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

                    "emacs${version}-byte-compile-jieba-rs" =
                      writeShellApplication
                        {
                          name = "emacs${version}-byte-compile-jieba-rs";

                          runtimeInputs = [
                            coreutils
                            gnugrep
                          ];

                          text = ''
                            initdir="$(mktemp --tmpdir -d emacs-jieba-rs-byte-compile-XXXXXX)"
                            workdir="$(mktemp --tmpdir -d emacs-jieba-rs-byte-compile-src-XXXXXX)"
                            trap 'rm -rf "$initdir" "$workdir"' EXIT

                            mkdir -p "$workdir/lisp" "$workdir/tests"
                            cp "${jiebaRsSource}" "$workdir/lisp/jieba-rs.el"
                            cp "${jiebaRsTestSource}" \
                              "$workdir/tests/jieba-rs-tests.el"

                            compileLog="$workdir/byte-compile.log"

                            {
                              "${emacsWithJiebaRs}/bin/emacs" --batch \
                                --init-directory "$initdir" \
                                -L "$workdir/lisp" \
                                --eval '(setq byte-compile-error-on-warn t)' \
                                -f batch-byte-compile \
                                "$workdir/lisp/jieba-rs.el"

                              "${emacsWithJiebaRs}/bin/emacs" --batch \
                                --init-directory "$initdir" \
                                -L "$workdir/lisp" \
                                -L "$workdir/tests" \
                                --eval '(setq byte-compile-error-on-warn t)' \
                                -f batch-byte-compile \
                                "$workdir/tests/jieba-rs-tests.el"
                            } 2>&1 | tee "$compileLog"

                            if grep -Fq 'Note:' "$compileLog"; then
                              printf '%s\n' \
                                'Byte compilation emitted Note diagnostics:' >&2
                              grep -F 'Note:' "$compileLog" >&2
                              exit 1
                            fi

                            "${emacsWithJiebaRs}/bin/emacs" --batch \
                              --init-directory "$initdir" \
                              -L "$workdir/lisp" \
                              --eval '(progn
                                (require (quote jieba-rs))
                                (require (quote jieba-rs-module))
                                (unless
                                    (equal
                                     (jieba-rs-module-segment
                                      "我们中出了一个叛徒" nil)
                                     ["我们" "中" "出" "了" "一个" "叛徒"])
                                  (error
                                   "Rust module segmentation smoke test failed")))'
                          '';
                        };

                    "emacs${version}-checkdoc-jieba-rs" =
                      writeShellApplication
                        {
                          name = "emacs${version}-checkdoc-jieba-rs";

                          runtimeInputs = [
                            coreutils
                          ];

                          text = ''
                            initdir="$(mktemp --tmpdir -d emacs-jieba-rs-checkdoc-XXXXXX)"
                            trap 'rm -rf "$initdir"' EXIT

                            CHECKDOC_SOURCES="$(
                              printf '%s\n' \
                                "${projectRoot}/lisp/jieba-rs.el" \
                                "${projectRoot}/tests/jieba-rs-tests.el"
                            )" \
                            "${base}/bin/emacs" --batch \
                              --init-directory "$initdir" \
                              --eval '(progn
                                (require (quote checkdoc))
                                (dolist
                                    (file
                                     (split-string
                                      (getenv "CHECKDOC_SOURCES")
                                      "\n" t))
                                  (let ((buffer
                                         (find-file-noselect file)))
                                    (unwind-protect
                                        (with-current-buffer buffer
                                          (let
                                              ((checkdoc-autofix-flag
                                                (quote never)))
                                            (condition-case error-data
                                                (checkdoc-current-buffer)
                                              (error
                                               (error
                                                "Checkdoc failed for %s: %s"
                                                file
                                                (error-message-string
                                                 error-data))))))
                                      (kill-buffer buffer)))))'
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
