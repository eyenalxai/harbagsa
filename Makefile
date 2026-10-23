ODIN ?= odin
ODIN_FLAGS ?= -vet -vet-style -vet-semicolon -vet-tabs -vet-using-param -vet-unused-procedures -vet-packages:main,platform,renderer,game,geometry -strict-style -warnings-as-errors -disallow-do
ODIN_COLLECTIONS := -collection:libs=vendor -collection:src=src
# Library checks and the renderer test cannot know which procedures another
# package calls, so they omit -vet-unused-procedures. The main check still runs
# it across every imported package.
ODIN_LIB_CHECK_FLAGS := $(filter-out -vet-unused-procedures,$(ODIN_FLAGS))
BIN := bin/harbagsa

GLSLC ?= glslc
SHADER_SRC := src/renderer/shaders
SHADER_OUT := build/shaders
SHADER_INCLUDES := $(SHADER_SRC)/gamma.glsl $(SHADER_SRC)/camera.glsl
SHADERS := $(SHADER_OUT)/box.vert.spv $(SHADER_OUT)/box.frag.spv \
	$(SHADER_OUT)/shadow.vert.spv \
	$(SHADER_OUT)/debug.vert.spv $(SHADER_OUT)/debug.frag.spv \
	$(SHADER_OUT)/hud.vert.spv $(SHADER_OUT)/hud.frag.spv \
	$(SHADER_OUT)/taa.vert.spv $(SHADER_OUT)/taa.frag.spv

CC ?= cc
BOX3D_DIR := vendor/box3d
BOX3D_SRC := $(wildcard $(BOX3D_DIR)/src/src/*.c)
BOX3D_OBJ := $(patsubst $(BOX3D_DIR)/src/src/%.c,build/box3d/%.o,$(BOX3D_SRC))
BOX3D_LIB := $(BOX3D_DIR)/lib/linux-amd64/libbox3d.a

.PHONY: all build check check-lines test run shaders clean

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

$(SHADER_OUT)/%.vert.spv: $(SHADER_SRC)/%.vert $(SHADER_INCLUDES)
	@mkdir -p $(@D)
	$(GLSLC) --target-env=vulkan1.3 -fshader-stage=vert $< -o $@

$(SHADER_OUT)/%.frag.spv: $(SHADER_SRC)/%.frag $(SHADER_INCLUDES)
	@mkdir -p $(@D)
	$(GLSLC) --target-env=vulkan1.3 -fshader-stage=frag $< -o $@

shaders: $(SHADERS)

build: $(BOX3D_LIB) shaders
	mkdir -p bin
	$(ODIN) build . $(ODIN_FLAGS) $(ODIN_COLLECTIONS) -out:$(BIN)

check: check-lines $(BOX3D_LIB) shaders
	$(ODIN) check . $(ODIN_FLAGS) $(ODIN_COLLECTIONS)
	$(ODIN) check src/platform $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/renderer $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/game $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/geometry $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point

check-lines:
	@status=0; \
	for file in $$(find . -name '*.odin' -not -path './vendor/*'); do \
		lines=$$(wc -l < "$$file"); \
		if [ "$$lines" -ge 300 ]; then \
			printf '%s: %d lines\n' "$$file" "$$lines" >&2; \
			status=1; \
		fi; \
	done; \
	exit $$status

# Box3D's world registry is not safe for concurrent world creation, so the test
# programs share one runner thread.
test: $(BOX3D_LIB) shaders
	$(ODIN) test tests/physics $(ODIN_FLAGS) $(ODIN_COLLECTIONS) -define:ODIN_TEST_THREADS=1
	$(ODIN) test tests/simulation $(ODIN_FLAGS) $(ODIN_COLLECTIONS) -define:ODIN_TEST_THREADS=1
	$(ODIN) test tests/renderer $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -define:ODIN_TEST_THREADS=1

run: $(BOX3D_LIB) shaders
	$(ODIN) run . $(ODIN_FLAGS) $(ODIN_COLLECTIONS)

clean:
	rm -rf bin build $(BOX3D_LIB)
