.DELETE_ON_ERROR:
.DEFAULT_GOAL := all

MAKEINFO ?= makeinfo
MAKEINFO_FLAGS ?=
HTML_CSS_URL ?= https://www.gnu.org/software/texinfo/manual.css
OUTPUT_DIR ?= ../dist/manuals

INFO := $(OUTPUT_DIR)/info/jieba-rs.info
HTML := $(OUTPUT_DIR)/html/jieba-rs.html

.PHONY: all info html clean

all: info html

info: $(INFO)

html: $(HTML)

$(INFO): jieba-rs.texi fdl.texi Makefile
	@mkdir -p "$(@D)"
	$(MAKEINFO) $(MAKEINFO_FLAGS) -I . --no-split -o "$@" "$<"

$(HTML): jieba-rs.texi fdl.texi Makefile
	@mkdir -p "$(@D)"
	$(MAKEINFO) $(MAKEINFO_FLAGS) -I . --html --no-split \
		--css-ref="$(HTML_CSS_URL)" -o "$@" "$<"

clean:
	$(RM) $(INFO) $(HTML)
