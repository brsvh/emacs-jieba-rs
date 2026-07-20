.DELETE_ON_ERROR:
.ONESHELL:

SHELL := /bin/sh

# Tools and paths.
CARGO ?= cargo
EMACS ?= emacs
EMACS_BATCH := $(EMACS) -Q --batch

BUILD_FILE := Makefile
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

# Rust and test files.
RUST_FILES := \
	$(sort $(shell find $(RUST_DIR) -type f -name '*.rs' -print))
RUST_MODULE := target/release/libjieba_rs_module.so
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
# bake-format on

.PHONY: \
	all \
	autoloads \
	check \
	clean \
	local \
	module \
	pkg \
	test

all: module

local: module autoloads pkg

module: $(JIEBA_RS_MODULE)

autoloads: $(JIEBA_RS_AUTOLOADS)

pkg: $(JIEBA_RS_PKG)

test: module
	$(EMACS_BATCH) -L $(LISP_DIR) \
		-l $(TEST_FILES) \
		-f ert-run-tests-batch-and-exit

check: module
	@set -eu
	$(CARGO) test
	$(EMACS_BATCH) -L $(LISP_DIR) \
		-l $(TEST_FILES) \
		-f ert-run-tests-batch-and-exit

$(JIEBA_RS_MODULE): \
	$(RUST_FILES) \
	Cargo.toml \
	Cargo.lock \
	$(BUILD_FILE)
	@set -eu
	$(CARGO) build --release --lib
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

clean:
	$(RM) $(GENERATED_FILES) $(GENERATED_BACKUPS)