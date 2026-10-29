ODIN ?= odin
ODIN_FLAGS ?= -vet -vet-style -vet-semicolon -vet-tabs -vet-using-param -vet-unused-procedures -vet-packages:main,platform,renderer,font,game,geometry,frame,perf,harness,display,ui,input,bake -strict-style -warnings-as-errors -disallow-do
ODIN_COLLECTIONS := -collection:libs=vendor -collection:src=src
# Library checks cannot know which procedures another package calls, so they
# omit -vet-unused-procedures. The main check still runs it across every
# imported package.
ODIN_LIB_CHECK_FLAGS := $(filter-out -vet-unused-procedures,$(ODIN_FLAGS))
BIN := bin/harbagsa
AGENT_BIN := bin/harbagsa-agent
AGENT := cmd/harbagsa-agent
BAKE_BIN := bin/harbagsa-bake
BAKE_TOOL := cmd/harbagsa-bake
BAKE_OUT := build/bake/arena.hbake
BAKE_SOURCES := $(shell find src cmd -name '*.odin')
HARNESS_REVISION := $(shell git rev-parse --short HEAD 2>/dev/null || printf unknown)
# `git status --porcelain` covers staged and untracked files; `git diff --quiet`
# sees neither.
HARNESS_DIRTY := $(shell if git rev-parse --git-dir >/dev/null 2>&1 && [ -z "$$(git status --porcelain 2>/dev/null)" ]; then printf false; else printf true; fi)
AGENT_DEFINES := -define:HARNESS_REVISION='"$(HARNESS_REVISION)"' -define:HARNESS_DIRTY=$(HARNESS_DIRTY)
AGENT_BUILD := $(ODIN) build $(AGENT) $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) $(AGENT_DEFINES) -out:$(AGENT_BIN)
SCENARIO ?=
OUT ?=
JQ ?= jq

# A selector without a slash or a .json suffix names a file in scenarios/.
scenario_path = $(if $(or $(findstring /,$(1)),$(filter %.json,$(1))),$(1),scenarios/$(1).json)

GLSLC ?= glslc
SPIRV_VAL ?= spirv-val
VULKANINFO ?= vulkaninfo
SHADER_SRC := src/renderer/shaders
SHADER_OUT := build/shaders
SHADER_INCLUDES := $(SHADER_SRC)/gamma.glsl $(SHADER_SRC)/camera.glsl $(SHADER_SRC)/cluster.glsl $(SHADER_SRC)/lightmap.glsl $(SHADER_SRC)/probe.glsl
SHADERS := $(SHADER_OUT)/box.vert.spv $(SHADER_OUT)/box.frag.spv \
	$(SHADER_OUT)/cluster.comp.spv \
	$(SHADER_OUT)/debug.vert.spv $(SHADER_OUT)/debug.frag.spv \
	$(SHADER_OUT)/hud.vert.spv $(SHADER_OUT)/hud.frag.spv \
	$(SHADER_OUT)/taa.vert.spv $(SHADER_OUT)/taa.frag.spv

CC ?= cc
CXX ?= c++
BOX3D_DIR := vendor/box3d
BOX3D_SRC := $(wildcard $(BOX3D_DIR)/src/src/*.c)
BOX3D_OBJ := $(patsubst $(BOX3D_DIR)/src/src/%.c,build/box3d/%.o,$(BOX3D_SRC))
BOX3D_LIB := $(BOX3D_DIR)/lib/linux-amd64/libbox3d.a

FREETYPE_DIR := vendor/freetype
FREETYPE_CONFIG := vendor/freetype-config
FREETYPE_SRC := \
	$(FREETYPE_DIR)/src/base/ftsystem.c \
	$(FREETYPE_DIR)/src/base/ftinit.c \
	$(FREETYPE_DIR)/src/base/ftdebug.c \
	$(FREETYPE_DIR)/src/base/ftbase.c \
	$(FREETYPE_DIR)/src/base/ftbbox.c \
	$(FREETYPE_DIR)/src/base/ftglyph.c \
	$(FREETYPE_DIR)/src/base/ftbitmap.c \
	$(FREETYPE_DIR)/src/base/ftmm.c \
	$(FREETYPE_DIR)/src/truetype/truetype.c \
	$(FREETYPE_DIR)/src/sfnt/sfnt.c \
	$(FREETYPE_DIR)/src/psnames/psnames.c \
	$(FREETYPE_DIR)/src/smooth/smooth.c
FREETYPE_OBJ := $(patsubst %.c,build/freetype/%.o,$(notdir $(FREETYPE_SRC))) build/freetype/ftgzip_stub.o
FREETYPE_LIB := $(FREETYPE_DIR)/lib/linux-amd64/libfreetype.a
FREETYPE_DEFS := -DFT_CONFIG_OPTIONS_H='"ftoption.h"' -DFT_CONFIG_MODULES_H='"ftmodule.h"'

HARFBUZZ_DIR := vendor/harfbuzz
HARFBUZZ_OBJ := build/harfbuzz/harfbuzz.o
HARFBUZZ_LIB := $(HARFBUZZ_DIR)/lib/linux-amd64/libharfbuzz.a
# HB_NO_VAR must stay off: it removes variable-font support.
HARFBUZZ_DEFS := -DHB_NO_MT -DHB_NO_AAT -DHB_NO_LEGACY -DHB_NO_COLOR -DHB_NO_DRAW \
	-DHB_NO_MATH -DHB_NO_NAME -DHB_NO_META -DHB_NO_METRICS -DHB_NO_STYLE \
	-DHB_NO_HINTING -DHB_NO_OT_SHAPE_FRACTIONS -DHB_NO_EMOJI_SEQUENCES

VULKAN_LAYER_DIRS ?= \
	$(HOME)/.config/vulkan/explicit_layer.d \
	/etc/xdg/vulkan/explicit_layer.d \
	/etc/vulkan/explicit_layer.d \
	$(HOME)/.local/share/vulkan/explicit_layer.d \
	/usr/local/share/vulkan/explicit_layer.d \
	/usr/share/vulkan/explicit_layer.d
VALIDATION_LAYER := VK_LAYER_KHRONOS_validation

.PHONY: all FORCE build agent bake check check-spirv check-lines run shaders check-validation-layer validate-demo check-references shot clean

FORCE:

all: build

# Build aside so a failed ar never leaves a broken archive.
$(BOX3D_LIB): $(BOX3D_OBJ)
	@mkdir -p $(@D)
	rm -f $@.tmp
	ar rcs $@.tmp $(BOX3D_OBJ)
	mv $@.tmp $@

build/box3d/%.o: $(BOX3D_DIR)/src/src/%.c
	@mkdir -p $(@D)
	$(CC) -c -O2 -std=c17 -fPIC -I$(BOX3D_DIR)/src/include $< -o $@

vpath %.c $(FREETYPE_DIR)/src/base $(FREETYPE_DIR)/src/truetype \
	$(FREETYPE_DIR)/src/sfnt $(FREETYPE_DIR)/src/psnames $(FREETYPE_DIR)/src/smooth

build/freetype/%.o: %.c
	@mkdir -p $(@D)
	$(CC) -c -O2 -std=c99 -fPIC -DFT2_BUILD_LIBRARY $(FREETYPE_DEFS) \
		-I$(FREETYPE_DIR)/include -I$(FREETYPE_CONFIG) $< -o $@

build/freetype/ftgzip_stub.o: $(FREETYPE_CONFIG)/ftgzip_stub.c
	@mkdir -p $(@D)
	$(CC) -c -O2 -std=c99 -fPIC -DFT2_BUILD_LIBRARY -I$(FREETYPE_DIR)/include $< -o $@

$(FREETYPE_LIB): $(FREETYPE_OBJ)
	@mkdir -p $(@D)
	rm -f $@.tmp
	ar crsD $@.tmp $(FREETYPE_OBJ)
	mv $@.tmp $@

$(HARFBUZZ_OBJ): $(HARFBUZZ_DIR)/src/harfbuzz.cc
	@mkdir -p $(@D)
	$(CXX) -std=c++11 -O2 -fPIC -fno-exceptions -fno-rtti -fno-threadsafe-statics \
		-DNDEBUG $(HARFBUZZ_DEFS) -I$(HARFBUZZ_DIR)/src -c $< -o $@

$(HARFBUZZ_LIB): $(HARFBUZZ_OBJ)
	@mkdir -p $(@D)
	rm -f $@.tmp
	ar crsD $@.tmp $(HARFBUZZ_OBJ)
	mv $@.tmp $@

$(SHADER_OUT)/%.vert.spv: $(SHADER_SRC)/%.vert $(SHADER_INCLUDES)
	@mkdir -p $(@D)
	$(GLSLC) --target-env=vulkan1.3 -fshader-stage=vert $< -o $@

$(SHADER_OUT)/%.frag.spv: $(SHADER_SRC)/%.frag $(SHADER_INCLUDES)
	@mkdir -p $(@D)
	$(GLSLC) --target-env=vulkan1.3 -fshader-stage=frag $< -o $@

$(SHADER_OUT)/%.comp.spv: $(SHADER_SRC)/%.comp $(SHADER_INCLUDES)
	@mkdir -p $(@D)
	$(GLSLC) --target-env=vulkan1.3 -fshader-stage=comp $< -o $@

shaders: $(SHADERS)

check-spirv: shaders
	@if ! command -v $(SPIRV_VAL) >/dev/null 2>&1; then \
		printf '%s\n' '$(SPIRV_VAL) not found; skipping SPIR-V validation'; \
	else \
		status=0; \
		for file in $(SHADERS); do \
			$(SPIRV_VAL) --target-env vulkan1.3 "$$file" || status=1; \
		done; \
		exit $$status; \
	fi

agent: $(BOX3D_LIB) $(FREETYPE_LIB) $(HARFBUZZ_LIB) shaders
	@mkdir -p $(dir $(AGENT_BIN))
	$(AGENT_BUILD)

build: $(BOX3D_LIB) $(FREETYPE_LIB) $(HARFBUZZ_LIB) shaders
	mkdir -p bin
	$(ODIN) build . $(ODIN_FLAGS) $(ODIN_COLLECTIONS) -out:$(BIN)
	$(AGENT_BUILD)

$(BAKE_BIN): $(BAKE_SOURCES) $(BOX3D_LIB)
	@mkdir -p $(dir $(BAKE_BIN))
	$(ODIN) build $(BAKE_TOOL) $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -out:$(BAKE_BIN)

$(BAKE_OUT): $(BAKE_BIN) $(BAKE_SOURCES)
	@mkdir -p $(@D)
	$(BAKE_BIN) --out $(@)

bake: $(BAKE_OUT)

check: check-lines check-spirv $(BOX3D_LIB) $(FREETYPE_LIB) $(HARFBUZZ_LIB) shaders
	$(ODIN) check . $(ODIN_FLAGS) $(ODIN_COLLECTIONS)
	$(ODIN) check $(AGENT) $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS)
	$(ODIN) check $(BAKE_TOOL) $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS)
	$(ODIN) check src/platform $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/renderer $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/renderer/font $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/game $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/bake $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/display $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/geometry $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/frame $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/perf $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/harness $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/ui $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/input $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point

check-references:
	@python3 tools/check-references.py

check-lines:
	@status=0; \
	for file in $$(find . -name '*.odin' -not -path './vendor/*'); do \
		lines=$$(wc -l < "$$file"); \
		if [ "$$lines" -ge 400 ]; then \
			printf '%s: %d lines\n' "$$file" "$$lines" >&2; \
			status=1; \
		fi; \
	done; \
	exit $$status

run: $(BOX3D_LIB) $(FREETYPE_LIB) $(HARFBUZZ_LIB) shaders
	$(ODIN) run . $(ODIN_FLAGS) $(ODIN_COLLECTIONS)

check-validation-layer:
	@found=false; \
	if command -v $(VULKANINFO) >/dev/null 2>&1; then \
		$(VULKANINFO) --summary 2>/dev/null | grep -qF '$(VALIDATION_LAYER)' && found=true; \
	fi; \
	if [ "$$found" = false ]; then \
		grep -rqsE '"name"[[:space:]]*:[[:space:]]*"$(VALIDATION_LAYER)"' \
			$(VULKAN_LAYER_DIRS) 2>/dev/null && found=true; \
	fi; \
	if [ "$$found" = false ]; then \
		printf '%s\n' \
			'Vulkan validation layer not found.' \
			'Install it with: sudo pacman -S vulkan-validation-layers'; \
		exit 1; \
	fi

# Evidence targets run the normal agent, never the validation build. They share
# bin/harbagsa-agent so a capture always comes from the same code path.
shot: agent
	@if [ -z '$(strip $(SCENARIO))' ]; then \
		printf '%s\n' 'make shot: set SCENARIO=<name> or SCENARIO=scenarios/<name>.json' >&2; \
		exit 2; \
	fi
	@if ! command -v $(JQ) >/dev/null 2>&1; then \
		printf '%s\n' 'make shot: jq is required to read report.json' >&2; \
		exit 1; \
	fi
	@selector=$(call scenario_path,$(firstword $(SCENARIO))); \
	stem=$$(basename "$$selector" .json); \
	out=$(if $(strip $(OUT)),$(OUT),runs/$$stem); \
	report="$$out/report.json"; \
	printf '%s\n' "make shot: $$selector -> $$out"; \
	$(AGENT_BIN) run "$$selector" --out "$$out" || exit $$?; \
	if [ ! -f "$$report" ]; then \
		printf 'make shot: no report at %s\n' "$$report" >&2; \
		exit 1; \
	fi; \
	paths=$$($(JQ) -r '.captures[].path // empty' "$$report") || { \
		printf 'make shot: cannot read captures from %s\n' "$$report" >&2; \
		exit 1; \
	}; \
	if [ -z "$$paths" ]; then \
		printf 'make shot: %s recorded no captures\n' "$$report" >&2; \
		exit 1; \
	fi; \
	printf '%s\n' "$$paths"

validate-demo: check-validation-layer $(BOX3D_LIB) $(FREETYPE_LIB) $(HARFBUZZ_LIB) shaders
	$(ODIN) run . $(ODIN_FLAGS) $(ODIN_COLLECTIONS) -define:ENABLE_VALIDATION_LAYERS=true

clean:
	rm -rf bin build $(BOX3D_LIB) $(FREETYPE_LIB) $(HARFBUZZ_LIB)
