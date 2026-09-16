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

                crane-lib = crane.mkLib prev.pkgs;

                rustVersion = "${
                  (prev.lib.importTOML (projectRoot + /Cargo.toml))
                  .package.rust-version
                }.0";

                buildCargoPackage =
                  (crane-lib.overrideToolchain
                    prev.pkgs.rust-bin.stable.${rustVersion}.default
                  ).buildPackage;

                package =
                  {
                    buildCargoPackage,
                    cleanCargoSource,
                    lib,
                    stdenv,
                    melpaBuild,
                    projectRoot,
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

                scope = finalAttrs: _: {
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
            extraInputsFlake = projectRoot + /tools;

            module =
              {
                ...
              }:
              {
                imports = [
                  (projectRoot + /tools/flake-module.nix)
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
              concatMapStringsSep
              foldl'
              removeSuffix
              versions
              ;

            lispSources = [
              "lisp/jieba-rs.el"
              "tools/elfmt/elfmt.el"
              "tests/jieba-rs-tests.el"
              "tests/elfmt-tests.el"
            ];

            releasePackages = pkgs.emacsPackagesFor pkgs.emacs31;
          in
          {
            _module = {
              args = {
                pkgs = import nixpkgs {
                  inherit
                    system
                    ;

                  overlays = [
                    self.overlays.default
                  ];
                };
              };
            };

            packages = {
              inherit (releasePackages)
                jieba-rs
                ;

              jieba-rs-module = releasePackages.jieba-rs.module;
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
                              -L "${projectRoot}/tools/elfmt" \
                              -l "${projectRoot + /tests/jieba-rs-tests.el}" \
                              -l "${projectRoot + /tests/elfmt-tests.el}" \
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

                            ${concatMapStringsSep "\n" (source: ''
                              install -Dm644 "${projectRoot}/${source}" "$workdir/${source}"
                            '') lispSources}

                            compileLog="$workdir/byte-compile.log"

                            "${emacsWithJiebaRs}/bin/emacs" --batch \
                              --init-directory "$initdir" \
                              -L "$workdir/lisp" \
                              -L "$workdir/tools/elfmt" \
                              -L "$workdir/tests" \
                              --eval '(setq byte-compile-error-on-warn t)' \
                              -f batch-byte-compile \
                              ${
                                concatMapStringsSep " \\\n" (
                                  source: ''"$workdir/${source}"''
                                ) lispSources
                              } \
                              2>&1 | tee "$compileLog"

                            if grep -Fq 'Note:' "$compileLog"; then
                              printf '%s\n' \
                                'Byte compilation emitted Note diagnostics:' >&2
                              grep -F 'Note:' "$compileLog" >&2
                              exit 1
                            fi

                            "${emacsWithJiebaRs}/bin/emacs" --batch \
                              --init-directory "$initdir" \
                              -L "$workdir/lisp" \
                              -L "$workdir/tools/elfmt" \
                              --eval '(setq native-comp-jit-compilation nil)' \
                              ${
                                concatMapStringsSep " \\\n" (
                                  source:
                                  ''-l "$workdir/${removeSuffix ".el" source}.elc"''
                                ) lispSources
                              } \
                              --eval '(unless
                                (byte-code-function-p
                                 (symbol-function (quote jieba-rs--content-end)))
                                (error "Expected ordinary Lisp bytecode"))' \
                              -f ert-run-tests-batch-and-exit
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
                                ${concatMapStringsSep " \\\n" (
                                  source: ''"${projectRoot}/${source}"''
                                ) lispSources}
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
                                  (with-temp-buffer
                                    (insert-file-contents file)
                                    (emacs-lisp-mode)
                                    (setq buffer-file-name file)
                                    (goto-char (point-min))
                                    ;; Checkdoc expects the Lisp header first.
                                    (when (looking-at "#!")
                                      (delete-region
                                       (point)
                                       (progn (forward-line 1) (point))))
                                    (let ((checkdoc-autofix-flag (quote never)))
                                      (condition-case error-data
                                          (checkdoc-current-buffer)
                                        (error
                                         (error
                                          "Checkdoc failed for %s: %s"
                                          file
                                          (error-message-string
                                           error-data))))))))'
                          '';
                        };
                  }
                )
                { }
                (
                  with pkgs;
                  [
                    emacs31
                  ]
                );
          };

        systems = [
          "x86_64-linux"
        ];
      };
}
