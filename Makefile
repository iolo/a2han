SHELL := /bin/sh

.DEFAULT_GOAL := all

CL65 ?= cl65
HOST_CC ?= cc
HOST_CFLAGS ?= -O2 -std=c99 -Wall -Wextra
PYTHON ?= python3
A2KIT ?= a2kit
PACKAGER ?= a2kit

CC65_TARGET ?= apple2
LINK_CFG ?= apple2-asm.cfg

BUILD_DIR ?= build
MAP_DIR := $(BUILD_DIR)/map
SAMPLE_DIR := $(BUILD_DIR)/samples
BUILD_STAMP := $(BUILD_DIR)/.dir
MAP_STAMP := $(MAP_DIR)/.dir
SAMPLE_STAMP := $(SAMPLE_DIR)/.dir

A2HAN_SRC ?= a2han.s
A2HVIEW_SRC ?= a2hview.c
DEMO_SRC ?= demo.bas
HCONV_HOST_SRC ?= hconv.c
HCONV_HOST_DEFS ?= -DHCONV_MAIN

A2HAN_PRODOS_BIN := $(BUILD_DIR)/A2HAN.PRO
A2HAN_DOS33_BIN := $(BUILD_DIR)/A2HAN.DOS
A2HVIEW_BIN := $(BUILD_DIR)/A2HVIEW
HCONV_HOST_BIN := $(BUILD_DIR)/hconv
PROGRAM_BINS := $(A2HAN_PRODOS_BIN) $(A2HAN_DOS33_BIN) $(A2HVIEW_BIN)

PO_IMAGE := $(BUILD_DIR)/a2han.po
DSK_IMAGE := $(BUILD_DIR)/a2han.dsk
PANGRAM_UTF8_SAMPLE := $(SAMPLE_DIR)/pangram_a2hview.utf8.txt
PANGRAM_MODIFIED_SAMPLE := $(SAMPLE_DIR)/pangram_a2hview.modified.bin
PANGRAM_NBYTES_SAMPLE := $(SAMPLE_DIR)/pangram_a2hview.nbytes.txt
A2HVIEW_SAMPLE_FILES := $(PANGRAM_UTF8_SAMPLE) $(PANGRAM_MODIFIED_SAMPLE) $(PANGRAM_NBYTES_SAMPLE)

PRODOS_VOLUME ?= A2HAN
DOS33_VOLUME ?= 254
A2HAN_START_ADDR ?= 0x6000
A2HAN_LOAD_ADDR ?= 24576
A2HVIEW_LOAD_ADDR ?= 2051

.PHONY: all build dsk po images check check-tools check-packager clean help

all: build

build: check-tools $(PROGRAM_BINS)

dsk: check-tools check-packager $(DSK_IMAGE)

po: check-tools check-packager $(PO_IMAGE)

images: dsk po

check:
	$(PYTHON) tests/run_golden.py
	$(HOST_CC) $(HOST_CFLAGS) $(HCONV_HOST_DEFS) -o $(HCONV_HOST_BIN) $(HCONV_HOST_SRC)
	$(PYTHON) tests/run_c_hconv.py $(HCONV_HOST_BIN)
	$(PYTHON) tests/run_corpus_roundtrip.py
	$(PYTHON) tests/run_console_output_path.py

check-tools:
	@command -v $(CL65) >/dev/null 2>&1 || { echo "missing required tool: $(CL65)" >&2; exit 1; }
	@command -v $(PYTHON) >/dev/null 2>&1 || { echo "missing required tool: $(PYTHON)" >&2; exit 1; }

check-packager:
ifeq ($(PACKAGER),a2kit)
	@command -v $(A2KIT) >/dev/null 2>&1 || { echo "missing required packager: $(A2KIT)" >&2; exit 1; }
else ifeq ($(PACKAGER),applecommander)
	@echo "PACKAGER=applecommander is reserved, but AppleCommander commands are not wired in this scaffold yet." >&2
	@echo "Use PACKAGER=a2kit for now, or extend this Makefile with your AppleCommander command templates." >&2
	@exit 1
else
	@echo "unsupported PACKAGER: $(PACKAGER)" >&2
	@echo "supported values: a2kit, applecommander" >&2
	@exit 1
endif

$(BUILD_STAMP):
	@mkdir -p $(BUILD_DIR)
	@touch $@

$(MAP_STAMP): | $(BUILD_STAMP)
	@mkdir -p $(MAP_DIR)
	@touch $@

$(SAMPLE_STAMP): | $(BUILD_STAMP)
	@mkdir -p $(SAMPLE_DIR)
	@touch $@

$(A2HAN_PRODOS_BIN): $(A2HAN_SRC) | $(BUILD_STAMP) $(MAP_STAMP)
	$(CL65) -t $(CC65_TARGET) -C $(LINK_CFG) --start-addr $(A2HAN_START_ADDR) --asm-define A2HAN_TARGET_PRODOS=1 -m $(MAP_DIR)/A2HAN-PRODOS.map -o $@ $<

$(A2HAN_DOS33_BIN): $(A2HAN_SRC) | $(BUILD_STAMP) $(MAP_STAMP)
	$(CL65) -t $(CC65_TARGET) -C $(LINK_CFG) --start-addr $(A2HAN_START_ADDR) --asm-define A2HAN_TARGET_DOS33=1 -m $(MAP_DIR)/A2HAN-DOS33.map -o $@ $<

$(A2HVIEW_BIN): $(A2HVIEW_SRC) $(HCONV_HOST_SRC) | $(BUILD_STAMP) $(MAP_STAMP)
	$(CL65) -t $(CC65_TARGET) -m $(MAP_DIR)/A2HVIEW.map -o $@ $^

$(HCONV_HOST_BIN): $(HCONV_HOST_SRC) | $(BUILD_STAMP)
	$(HOST_CC) $(HOST_CFLAGS) $(HCONV_HOST_DEFS) -o $@ $(HCONV_HOST_SRC)

$(A2HVIEW_SAMPLE_FILES): tests/han_pangram.utf8.txt tools/gen_a2hview_samples.py hconv.py | $(SAMPLE_STAMP)
	$(PYTHON) tools/gen_a2hview_samples.py

$(PO_IMAGE): $(A2HAN_PRODOS_BIN) $(A2HVIEW_BIN) $(A2HVIEW_SAMPLE_FILES) $(if $(wildcard $(DEMO_SRC)),$(DEMO_SRC),) | $(BUILD_STAMP)
	@rm -f $@
	$(A2KIT) mkdsk -t po -o prodos -v $(PRODOS_VOLUME) -d $@
	$(A2KIT) cp -a $(A2HAN_LOAD_ADDR) $(A2HAN_PRODOS_BIN) $@/A2HAN
	$(A2KIT) cp -a $(A2HVIEW_LOAD_ADDR) $(A2HVIEW_BIN) $@/A2HVIEW
	$(A2KIT) put -d $@ -f PANGUTF8 -t raw < $(PANGRAM_UTF8_SAMPLE)
	$(A2KIT) put -d $@ -f PANGMOD -t raw < $(PANGRAM_MODIFIED_SAMPLE)
	$(A2KIT) put -d $@ -f PANGNBYTES -t raw < $(PANGRAM_NBYTES_SAMPLE)
	@if [ -f "$(DEMO_SRC)" ]; then $(A2KIT) cp "$(DEMO_SRC)" "$@/DEMO"; fi

$(DSK_IMAGE): $(A2HAN_DOS33_BIN) $(A2HVIEW_BIN) $(A2HVIEW_SAMPLE_FILES) $(if $(wildcard $(DEMO_SRC)),$(DEMO_SRC),) | $(BUILD_STAMP)
	@rm -f $@
	$(A2KIT) mkdsk -t do -o dos33 -v $(DOS33_VOLUME) -d $@
	$(A2KIT) cp -a $(A2HAN_LOAD_ADDR) $(A2HAN_DOS33_BIN) $@/A2HAN
	$(A2KIT) cp -a $(A2HVIEW_LOAD_ADDR) $(A2HVIEW_BIN) $@/A2HVIEW
	$(A2KIT) put -d $@ -f PANGUTF8 -t raw < $(PANGRAM_UTF8_SAMPLE)
	$(A2KIT) put -d $@ -f PANGMOD -t raw < $(PANGRAM_MODIFIED_SAMPLE)
	$(A2KIT) put -d $@ -f PANGNBYTES -t raw < $(PANGRAM_NBYTES_SAMPLE)
	@if [ -f "$(DEMO_SRC)" ]; then $(A2KIT) cp "$(DEMO_SRC)" "$@/DEMO"; fi

$(A2HAN_SRC) $(A2HVIEW_SRC):
	@echo "missing required source: $@" >&2
	@echo "This repository currently has the host-side converter, but the program source is not in the tree yet." >&2
	@exit 1

clean:
	rm -rf $(BUILD_DIR)

help:
		@printf '%s\n' \
			'Targets:' \
			'  make            Build A2HAN.PRO, A2HAN.DOS, and A2HVIEW with cc65/cl65' \
			'  make dsk        Create build/a2han.dsk with a2kit' \
			'  make po         Create build/a2han.po with a2kit' \
			'  make images     Build both disk images' \
		'  make check      Run host-side converter tests' \
		'  make clean      Remove build artifacts' \
		'' \
		'Variables:' \
		'  PACKAGER=a2kit              Disk image packager (implemented)' \
		'  CC65_TARGET=apple2          cc65 target passed to cl65' \
		'  LINK_CFG=apple2-asm.cfg     ld65 config used by cl65' \
		'  A2HAN_START_ADDR=38400      Resident load/link address for A2HAN' \
		'  A2HAN_LOAD_ADDR=<addr>      Required for disk packaging' \
		'  A2HVIEW_LOAD_ADDR=<addr>    Required for disk packaging'
