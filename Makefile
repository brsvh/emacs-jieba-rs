EMACS ?= emacs
LISP = lisp
SO = target/release/libjieba_rs_module.so

.PHONY: all module autoloads pkg local test check clean

all: module

local: module autoloads pkg

module:
	cargo build --release --lib
	cp $(SO) $(LISP)/jieba-rs-module.so

autoloads:
	$(EMACS) -Q --batch -L $(LISP) \
		-l build-aux/generate-autoloads.el \
		-f batch-update-autoloads $(LISP)

pkg:
	$(EMACS) -Q --batch -l build-aux/generate-pkg.el

test: module
	$(EMACS) -Q --batch -L $(LISP) \
		-l tests/jieba-rs-tests.el \
		-f ert-run-tests-batch-and-exit

check: module
	cargo test
	$(EMACS) -Q --batch -L $(LISP) \
		-l tests/jieba-rs-tests.el \
		-f ert-run-tests-batch-and-exit

clean:
	rm -f $(LISP)/jieba-rs-module.so \
	      $(LISP)/jieba-rs-pkg.el \
	      $(LISP)/jieba-rs-pkg.el~ \
	      $(LISP)/jieba-rs-autoloads.el \
	      $(LISP)/jieba-rs-autoloads.el~ \
	      $(LISP)/*.elc