SHELL := /bin/sh

.DEFAULT_GOAL := all

CL65 ?= cl65
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
HCAT_SRC ?= hcat.c
DEMO_SRC ?= demo.bas

A2HAN_BIN := $(BUILD_DIR)/A2HAN
HCAT_BIN := $(BUILD_DIR)/HCAT
PROGRAM_BINS := $(A2HAN_BIN) $(HCAT_BIN)

PO_IMAGE := $(BUILD_DIR)/a2han.po
DSK_IMAGE := $(BUILD_DIR)/a2han.dsk
PANGRAM_UTF8_SAMPLE := $(SAMPLE_DIR)/pangram_hcat.utf8.txt
PANGRAM_MODIFIED_SAMPLE := $(SAMPLE_DIR)/pangram_hcat.modified.bin
PANGRAM_NBYTES_SAMPLE := $(SAMPLE_DIR)/pangram_hcat.nbytes.txt
HCAT_SAMPLE_FILES := $(PANGRAM_UTF8_SAMPLE) $(PANGRAM_MODIFIED_SAMPLE) $(PANGRAM_NBYTES_SAMPLE)

PRODOS_VOLUME ?= A2HAN
DOS33_VOLUME ?= 254
A2HAN_START_ADDR ?= 0x6000
A2HAN_LOAD_ADDR ?= 24576
HCAT_LOAD_ADDR ?= 2051

.PHONY: all build dsk po images check check-tools check-packager clean help

all: build

build: check-tools $(PROGRAM_BINS)

dsk: check-tools check-packager $(DSK_IMAGE)

po: check-tools check-packager $(PO_IMAGE)

images: dsk po

check:
	$(PYTHON) tests/run_golden.py
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

$(A2HAN_BIN): $(A2HAN_SRC) | $(BUILD_STAMP) $(MAP_STAMP)
	$(CL65) -t $(CC65_TARGET) -C $(LINK_CFG) --start-addr $(A2HAN_START_ADDR) -m $(MAP_DIR)/A2HAN.map -o $@ $<

$(HCAT_BIN): $(HCAT_SRC) | $(BUILD_STAMP) $(MAP_STAMP)
	$(CL65) -t $(CC65_TARGET) -m $(MAP_DIR)/HCAT.map -o $@ $<

$(HCAT_SAMPLE_FILES): tests/han_pangram.utf8.txt tools/gen_hcat_samples.py hconv.py | $(SAMPLE_STAMP)
	$(PYTHON) tools/gen_hcat_samples.py

$(PO_IMAGE): $(PROGRAM_BINS) $(HCAT_SAMPLE_FILES) $(if $(wildcard $(DEMO_SRC)),$(DEMO_SRC),) | $(BUILD_STAMP)
	@rm -f $@
	$(A2KIT) mkdsk -t po -o prodos -v $(PRODOS_VOLUME) -d $@
	$(A2KIT) cp -a $(A2HAN_LOAD_ADDR) $(A2HAN_BIN) $@/A2HAN
	$(A2KIT) cp -a $(HCAT_LOAD_ADDR) $(HCAT_BIN) $@/HCAT
	$(A2KIT) put -d $@ -f PANGUTF8 -t raw < $(PANGRAM_UTF8_SAMPLE)
	$(A2KIT) put -d $@ -f PANGMOD -t raw < $(PANGRAM_MODIFIED_SAMPLE)
	$(A2KIT) put -d $@ -f PANGNBYTES -t raw < $(PANGRAM_NBYTES_SAMPLE)
	@if [ -f "$(DEMO_SRC)" ]; then $(A2KIT) cp "$(DEMO_SRC)" "$@/DEMO"; fi

$(DSK_IMAGE): $(PROGRAM_BINS) $(HCAT_SAMPLE_FILES) $(if $(wildcard $(DEMO_SRC)),$(DEMO_SRC),) | $(BUILD_STAMP)
	@rm -f $@
	$(A2KIT) mkdsk -t do -o dos33 -v $(DOS33_VOLUME) -d $@
	$(A2KIT) cp -a $(A2HAN_LOAD_ADDR) $(A2HAN_BIN) $@/A2HAN
	$(A2KIT) cp -a $(HCAT_LOAD_ADDR) $(HCAT_BIN) $@/HCAT
	$(A2KIT) put -d $@ -f PANGUTF8 -t raw < $(PANGRAM_UTF8_SAMPLE)
	$(A2KIT) put -d $@ -f PANGMOD -t raw < $(PANGRAM_MODIFIED_SAMPLE)
	$(A2KIT) put -d $@ -f PANGNBYTES -t raw < $(PANGRAM_NBYTES_SAMPLE)
	@if [ -f "$(DEMO_SRC)" ]; then $(A2KIT) cp "$(DEMO_SRC)" "$@/DEMO"; fi

$(A2HAN_SRC) $(HCAT_SRC):
	@echo "missing required source: $@" >&2
	@echo "This repository currently has the host-side converter, but the program source is not in the tree yet." >&2
	@exit 1

clean:
	rm -rf $(BUILD_DIR)

help:
	@printf '%s\n' \
		'Targets:' \
		'  make            Build A2HAN (assembly) and HCAT (C) with cc65/cl65' \
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
		'  HCAT_LOAD_ADDR=<addr>       Required for disk packaging'
