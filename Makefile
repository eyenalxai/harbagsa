ODIN ?= odin
ODIN_FLAGS ?= -vet -vet-style -vet-semicolon -vet-tabs -vet-using-param -vet-unused-procedures -vet-packages:main,platform,renderer,game,geometry -strict-style -warnings-as-errors -disallow-do
ODIN_COLLECTIONS := -collection:libs=vendor -collection:src=src
# Libraries cannot know which procedures another package calls, so the
# standalone package checks omit -vet-unused-procedures. The main check still
# runs it across every imported package.
ODIN_LIB_CHECK_FLAGS := $(filter-out -vet-unused-procedures,$(ODIN_FLAGS))
BIN := bin/harbagsa

GLSLC ?= glslc
SHADER_SRC := src/renderer/shaders
SHADER_OUT := build/shaders
SHADERS := $(SHADER_OUT)/box.vert.spv $(SHADER_OUT)/box.frag.spv \
	$(SHADER_OUT)/debug.vert.spv $(SHADER_OUT)/debug.frag.spv \
	$(SHADER_OUT)/hud.vert.spv $(SHADER_OUT)/hud.frag.spv

CC ?= cc
BOX3D_DIR := vendor/box3d
BOX3D_SRC := $(wildcard $(BOX3D_DIR)/src/src/*.c)
BOX3D_OBJ := $(patsubst $(BOX3D_DIR)/src/src/%.c,build/box3d/%.o,$(BOX3D_SRC))
BOX3D_LIB := $(BOX3D_DIR)/lib/linux-amd64/libbox3d.a

.PHONY: all build check test run shaders clean

all: build

$(BOX3D_LIB): $(BOX3D_OBJ)
	@mkdir -p $(@D)
	rm -f $@
	ar rcs $@ $(BOX3D_OBJ)

build/box3d/%.o: $(BOX3D_DIR)/src/src/%.c
	@mkdir -p $(@D)
	$(CC) -c -O2 -std=c17 -fPIC -I$(BOX3D_DIR)/src/include $< -o $@

$(SHADER_OUT)/%.vert.spv: $(SHADER_SRC)/%.vert
	@mkdir -p $(@D)
	$(GLSLC) --target-env=vulkan1.3 -fshader-stage=vert $< -o $@

$(SHADER_OUT)/%.frag.spv: $(SHADER_SRC)/%.frag
	@mkdir -p $(@D)
	$(GLSLC) --target-env=vulkan1.3 -fshader-stage=frag $< -o $@

shaders: $(SHADERS)

build: $(BOX3D_LIB) shaders
	mkdir -p bin
	$(ODIN) build . $(ODIN_FLAGS) $(ODIN_COLLECTIONS) -out:$(BIN)

check: $(BOX3D_LIB) shaders
	$(ODIN) check . $(ODIN_FLAGS) $(ODIN_COLLECTIONS)
	$(ODIN) check src/platform $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/renderer $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/game $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/geometry $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point

# Box3D's world registry is not safe for concurrent world creation, so the
# simulation tests share one runner thread.
test: $(BOX3D_LIB)
	$(ODIN) test tests/physics $(ODIN_FLAGS) $(ODIN_COLLECTIONS)
	$(ODIN) test tests/simulation $(ODIN_FLAGS) $(ODIN_COLLECTIONS) -define:ODIN_TEST_THREADS=1

run: $(BOX3D_LIB) shaders
	$(ODIN) run . $(ODIN_FLAGS) $(ODIN_COLLECTIONS)

clean:
	rm -rf bin build $(BOX3D_LIB)
