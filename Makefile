.DELETE_ON_ERROR:
.ONESHELL:

SHELL := /bin/sh

# Tools and paths.
CARGO ?= cargo
CARGO_TARGET_DIR ?= target
EMACS ?= emacs
EMACS_BATCH := $(EMACS) -Q --batch
JQ ?= jq
TAR ?= tar

BUILD_FILE := Makefile
DIST_DIR := dist
LISP_DIR := lisp
RUST_DIR := src
TEST_DIR := tests

# Package files.
JIEBA_RS_LISP_FILES := $(LISP_DIR)/jieba-rs.el
JIEBA_RS_MAIN := $(firstword $(JIEBA_RS_LISP_FILES))
JIEBA_RS_ELC_FILES := $(JIEBA_RS_LISP_FILES:.el=.elc)
JIEBA_RS_PKG := $(LISP_DIR)/jieba-rs-pkg.el
JIEBA_RS_AUTOLOADS := $(LISP_DIR)/jieba-rs-autoloads.el
JIEBA_RS_MODULE := $(LISP_DIR)/jieba-rs-module.so
JIEBA_RS_ARCHIVE_STAMP := $(DIST_DIR)/.jieba-rs-archive

# Rust and test files.
RUST_FILES := \
	$(sort $(shell find $(RUST_DIR) -type f -name '*.rs' -print))
RUST_MODULE := \
	$(CARGO_TARGET_DIR)/release/libjieba_rs_module.so
TEST_FILES := $(TEST_DIR)/jieba-rs-tests.el

# Generated files.
GENERATED_FILES := \
	$(JIEBA_RS_MODULE) \
	$(JIEBA_RS_PKG) \
	$(JIEBA_RS_AUTOLOADS) \
	$(JIEBA_RS_ELC_FILES)
GENERATED_BACKUPS := \
	$(addsuffix ~,$(JIEBA_RS_PKG) $(JIEBA_RS_AUTOLOADS))

# Batch Emacs expressions.
# bake-format off
define GENERATE_PKG_ELISP
(progn
  (require (quote package))
  (let ((source
         (expand-file-name (getenv "PACKAGE_SOURCE")))
        (output
         (expand-file-name (getenv "PACKAGE_OUTPUT"))))
    (with-current-buffer (find-file-noselect source)
      (package-generate-description-file
       (package-buffer-info)
       output))))
endef

define GENERATE_AUTOLOADS_ELISP
(progn
  (require (quote package))
  (package-generate-autoloads
   (getenv "PACKAGE_NAME")
   (getenv "PACKAGE_DIR")))
endef

define PACKAGE_VERSION_ELISP
(progn
  (require (quote package))
  (with-current-buffer
      (find-file-noselect
       (expand-file-name (getenv "PACKAGE_SOURCE")))
    (princ
     (package-version-join
      (package-desc-version
       (package-buffer-info))))))
endef

define CHECK_ARCHIVE_ELISP
(progn
  (require (quote package))
  (let ((archive (getenv "PACKAGE_ARCHIVE"))
        (large-file-warning-threshold nil)
        (name (intern (getenv "PACKAGE_NAME")))
        (version (getenv "PACKAGE_VERSION")))
    (with-current-buffer (find-file-noselect archive)
      (let ((desc (package-tar-file-info)))
        (unless
            (and
             (eq (package-desc-name desc) name)
             (equal
              (package-version-join
               (package-desc-version desc))
              version))
          (error "Archive metadata mismatch"))))))
endef

define CHECK_ARCHIVE_INSTALL_ELISP
(progn
  (require (quote package))
  (let ((archive
         (expand-file-name (getenv "PACKAGE_ARCHIVE")))
        (test-dir
         (expand-file-name (getenv "PACKAGE_TEST_DIR"))))
    (setq user-emacs-directory test-dir
          package-user-dir
          (expand-file-name "packages" test-dir)
          package-directory-list nil
          package-native-compile nil)
    (package-initialize)
    (package-install-file archive)
    (require (quote jieba-rs))
    (require (quote jieba-rs-module))
    (unless
        (equal
         (jieba-rs-module-segment
          "我们中出了一个叛徒" nil)
         ["我们" "中" "出" "了" "一个" "叛徒"])
      (error "Installed module smoke test failed"))))
endef
# bake-format on

.PHONY: \
	all \
	autoloads \
	check \
	check-release-archive \
	clean \
	local \
	module \
	pkg \
	release-archive \
	release-artifact \
	release-version \
	test

all: module

local: module autoloads pkg

module: $(JIEBA_RS_MODULE)

autoloads: $(JIEBA_RS_AUTOLOADS)

pkg: $(JIEBA_RS_PKG)

release-version:
	@set -eu
	lisp_version=$$(env \
		PACKAGE_SOURCE="$(JIEBA_RS_MAIN)" \
		$(EMACS_BATCH) \
		--eval '$(PACKAGE_VERSION_ELISP)')
	cargo_version=$$($(CARGO) metadata \
		--locked \
		--no-deps \
		--format-version 1 \
		| $(JQ) -er \
		'[
		  .packages[]
		  | select(.name == "emacs-jieba-rs")
		  | .version
		 ]
		 | if length == 1
		   then .[0]
		   else error("Expected one emacs-jieba-rs package")
		   end')
	if test "$$lisp_version" != "$$cargo_version"; then
		printf 'Version mismatch: Lisp %s, Cargo %s\n' \
			"$$lisp_version" "$$cargo_version" >&2
		exit 1
	fi
	printf '%s\n' "$$lisp_version"

release-archive: $(JIEBA_RS_ARCHIVE_STAMP)
	@set -eu
	IFS= read -r archive < "$(JIEBA_RS_ARCHIVE_STAMP)"
	test -f "$$archive"

release-artifact: release-archive
	@set -eu
	IFS= read -r archive < "$(JIEBA_RS_ARCHIVE_STAMP)"
	printf '%s\n' "$$archive"

check-release-archive: release-archive
	@set -eu
	version=$$($(MAKE) --silent release-version)
	package_dir="jieba-rs-$${version}"
	expected_archive="$(DIST_DIR)/$${package_dir}.tar"
	IFS= read -r archive < "$(JIEBA_RS_ARCHIVE_STAMP)"
	if test "$$archive" != "$$expected_archive"; then
		printf 'Archive path mismatch: %s != %s\n' \
			"$$archive" "$$expected_archive" >&2
		exit 1
	fi
	temp_dir=$$(mktemp -d)
	trap 'rm -rf "$$temp_dir"' EXIT HUP INT TERM
	{
		printf '%s/\n' "$$package_dir"
		printf '%s/COPYING\n' "$$package_dir"
		printf '%s/jieba-rs.el\n' "$$package_dir"
		printf '%s/jieba-rs-pkg.el\n' "$$package_dir"
		printf '%s/jieba-rs-module.so\n' "$$package_dir"
	} | LC_ALL=C sort > "$$temp_dir/expected-members"
	$(TAR) -tf "$$archive" \
		| LC_ALL=C sort > "$$temp_dir/actual-members"
	cmp "$$temp_dir/expected-members" \
		"$$temp_dir/actual-members"
	env \
		PACKAGE_ARCHIVE="$$archive" \
		PACKAGE_NAME="jieba-rs" \
		PACKAGE_VERSION="$$version" \
		$(EMACS_BATCH) \
		--eval '$(CHECK_ARCHIVE_ELISP)'
	env \
		PACKAGE_ARCHIVE="$$archive" \
		PACKAGE_TEST_DIR="$$temp_dir/install" \
		$(EMACS_BATCH) \
		--eval '$(CHECK_ARCHIVE_INSTALL_ELISP)'

test: module
	$(EMACS_BATCH) -L $(LISP_DIR) \
		-l $(TEST_FILES) \
		-f ert-run-tests-batch-and-exit

check: module
	@set -eu
	$(CARGO) test --locked
	$(EMACS_BATCH) -L $(LISP_DIR) \
		-l $(TEST_FILES) \
		-f ert-run-tests-batch-and-exit

$(JIEBA_RS_MODULE): \
	$(RUST_FILES) \
	Cargo.toml \
	Cargo.lock \
	$(BUILD_FILE)
	@set -eu
	$(CARGO) build \
		--locked \
		--release \
		--lib \
		--target-dir "$(CARGO_TARGET_DIR)"
	cp "$(RUST_MODULE)" "$@"

$(JIEBA_RS_PKG): $(JIEBA_RS_MAIN) $(BUILD_FILE)
	@env \
		PACKAGE_SOURCE="$<" \
		PACKAGE_OUTPUT="$@" \
		$(EMACS_BATCH) \
		--eval '$(GENERATE_PKG_ELISP)'

$(JIEBA_RS_AUTOLOADS): \
	$(JIEBA_RS_LISP_FILES) \
	$(BUILD_FILE)
	@set -eu
	temp_dir=$$(mktemp -d)
	trap 'rm -rf "$$temp_dir"' EXIT HUP INT TERM
	cp $(filter %.el,$^) "$$temp_dir/"
	env \
		PACKAGE_DIR="$$temp_dir" \
		PACKAGE_NAME="jieba-rs" \
		$(EMACS_BATCH) \
		--eval '$(GENERATE_AUTOLOADS_ELISP)'
	cp "$$temp_dir/$(notdir $(JIEBA_RS_AUTOLOADS))" "$@"

$(JIEBA_RS_ARCHIVE_STAMP): \
	$(JIEBA_RS_LISP_FILES) \
	$(JIEBA_RS_PKG) \
	$(JIEBA_RS_MODULE) \
	Cargo.toml \
	Cargo.lock \
	COPYING \
	$(BUILD_FILE)
	@set -eu
	version=$$($(MAKE) --silent release-version)
	package_dir="jieba-rs-$${version}"
	archive="$(DIST_DIR)/$${package_dir}.tar"
	temp_dir=$$(mktemp -d)
	trap 'rm -rf "$$temp_dir"' EXIT HUP INT TERM
	mkdir -p "$$temp_dir/$$package_dir" "$(DIST_DIR)"
	cp \
		COPYING \
		$(JIEBA_RS_LISP_FILES) \
		$(JIEBA_RS_PKG) \
		$(JIEBA_RS_MODULE) \
		"$$temp_dir/$$package_dir/"
	chmod -R u=rwX,go=rX "$$temp_dir/$$package_dir"
	$(TAR) \
		--sort=name \
		--mtime=@0 \
		--owner=0 \
		--group=0 \
		--numeric-owner \
		-cf "$$temp_dir/$${package_dir}.tar" \
		-C "$$temp_dir" \
		"$$package_dir"
	{
		printf '%s/\n' "$$package_dir"
		printf '%s/COPYING\n' "$$package_dir"
		printf '%s/jieba-rs.el\n' "$$package_dir"
		printf '%s/jieba-rs-pkg.el\n' "$$package_dir"
		printf '%s/jieba-rs-module.so\n' "$$package_dir"
	} | LC_ALL=C sort > "$$temp_dir/expected-members"
	$(TAR) -tf "$$temp_dir/$${package_dir}.tar" \
		| LC_ALL=C sort > "$$temp_dir/actual-members"
	cmp "$$temp_dir/expected-members" \
		"$$temp_dir/actual-members"
	env \
		PACKAGE_ARCHIVE="$$temp_dir/$${package_dir}.tar" \
		PACKAGE_NAME="jieba-rs" \
		PACKAGE_VERSION="$$version" \
		$(EMACS_BATCH) \
		--eval '$(CHECK_ARCHIVE_ELISP)'
	old_archive=
	if test -f "$@"; then
		IFS= read -r old_archive < "$@" || :
	fi
	mv "$$temp_dir/$${package_dir}.tar" "$$archive"
	if test -n "$$old_archive" \
		&& test "$$old_archive" != "$$archive"; then
		case "$$old_archive" in
			"$(DIST_DIR)/jieba-rs-"*.tar)
				$(RM) "$$old_archive"
				;;
			*)
				printf 'Refusing to remove unexpected archive: %s\n' \
					"$$old_archive" >&2
				exit 1
				;;
		esac
	fi
	printf '%s\n' "$$archive" > "$@"
	printf 'Created %s\n' "$$archive" >&2

clean:
	$(RM) $(GENERATED_FILES) $(GENERATED_BACKUPS)
	rm -rf "$(DIST_DIR)"