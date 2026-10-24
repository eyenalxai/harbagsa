ODIN ?= odin
ODIN_FLAGS ?= -vet -vet-style -vet-semicolon -vet-tabs -vet-using-param -vet-unused-procedures -vet-packages:main,platform,renderer,game,geometry,frame,harness,display -strict-style -warnings-as-errors -disallow-do
ODIN_COLLECTIONS := -collection:libs=vendor -collection:src=src
# Library checks and the renderer test cannot know which procedures another
# package calls, so they omit -vet-unused-procedures. The main check still runs
# it across every imported package.
ODIN_LIB_CHECK_FLAGS := $(filter-out -vet-unused-procedures,$(ODIN_FLAGS))
BIN := bin/harbagsa
AGENT_BIN := bin/harbagsa-agent
AGENT := cmd/harbagsa-agent
VALIDATE_AGENT_BIN := bin/harbagsa-agent-validate
VALIDATE_SCENARIO := scenarios/smoke.json
VALIDATE_OUT := build/validate

GLSLC ?= glslc
SPIRV_VAL ?= spirv-val
VULKANINFO ?= vulkaninfo
SHADER_SRC := src/renderer/shaders
SHADER_OUT := build/shaders
SHADER_INCLUDES := $(SHADER_SRC)/gamma.glsl $(SHADER_SRC)/camera.glsl
SHADERS := $(SHADER_OUT)/box.vert.spv $(SHADER_OUT)/box.frag.spv \
	$(SHADER_OUT)/debug.vert.spv $(SHADER_OUT)/debug.frag.spv \
	$(SHADER_OUT)/hud.vert.spv $(SHADER_OUT)/hud.frag.spv \
	$(SHADER_OUT)/taa.vert.spv $(SHADER_OUT)/taa.frag.spv

CC ?= cc
BOX3D_DIR := vendor/box3d
BOX3D_SRC := $(wildcard $(BOX3D_DIR)/src/src/*.c)
BOX3D_OBJ := $(patsubst $(BOX3D_DIR)/src/src/%.c,build/box3d/%.o,$(BOX3D_SRC))
BOX3D_LIB := $(BOX3D_DIR)/lib/linux-amd64/libbox3d.a

VULKAN_LAYER_DIRS ?= \
	$(HOME)/.config/vulkan/explicit_layer.d \
	/etc/xdg/vulkan/explicit_layer.d \
	/etc/vulkan/explicit_layer.d \
	$(HOME)/.local/share/vulkan/explicit_layer.d \
	/usr/local/share/vulkan/explicit_layer.d \
	/usr/share/vulkan/explicit_layer.d
VALIDATION_LAYER := VK_LAYER_KHRONOS_validation

.PHONY: all build check check-spirv check-lines test run shaders validate validate-demo check-validation-layer clean

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

build: $(BOX3D_LIB) shaders
	mkdir -p bin
	$(ODIN) build . $(ODIN_FLAGS) $(ODIN_COLLECTIONS) -out:$(BIN)
	$(ODIN) build $(AGENT) $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -out:$(AGENT_BIN)

check: check-lines check-spirv $(BOX3D_LIB) shaders
	$(ODIN) check . $(ODIN_FLAGS) $(ODIN_COLLECTIONS)
	$(ODIN) check $(AGENT) $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS)
	$(ODIN) check src/platform $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/renderer $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/game $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/display $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/geometry $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/frame $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point
	$(ODIN) check src/harness $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -no-entry-point

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
	$(ODIN) test tests/display $(ODIN_FLAGS) $(ODIN_COLLECTIONS) -define:ODIN_TEST_THREADS=1
	$(ODIN) test tests/physics $(ODIN_FLAGS) $(ODIN_COLLECTIONS) -define:ODIN_TEST_THREADS=1
	$(ODIN) test tests/simulation $(ODIN_FLAGS) $(ODIN_COLLECTIONS) -define:ODIN_TEST_THREADS=1
	$(ODIN) test tests/frame $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -define:ODIN_TEST_THREADS=1
	$(ODIN) test tests/harness $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -define:ODIN_TEST_THREADS=1
	$(ODIN) test tests/renderer $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) -define:ODIN_TEST_THREADS=1

run: $(BOX3D_LIB) shaders
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

# The harness keeps validation bounded: a fixed scenario exits on its own.
validate: check-validation-layer $(BOX3D_LIB) shaders
	@mkdir -p $(dir $(VALIDATE_AGENT_BIN))
	$(ODIN) build $(AGENT) $(ODIN_LIB_CHECK_FLAGS) $(ODIN_COLLECTIONS) \
		-define:ENABLE_VALIDATION_LAYERS=true -out:$(VALIDATE_AGENT_BIN)
	$(VALIDATE_AGENT_BIN) run $(VALIDATE_SCENARIO) --out $(VALIDATE_OUT)/offscreen
	@if [ -n "$${WAYLAND_DISPLAY:-}$${DISPLAY:-}" ]; then \
		$(VALIDATE_AGENT_BIN) run $(VALIDATE_SCENARIO) --present --out $(VALIDATE_OUT)/present; \
	else \
		printf '%s\n' 'make validate: no display, skipping the present run'; \
	fi

validate-demo: check-validation-layer $(BOX3D_LIB) shaders
	$(ODIN) run . $(ODIN_FLAGS) $(ODIN_COLLECTIONS) -define:ENABLE_VALIDATION_LAYERS=true

clean:
	rm -rf bin build $(BOX3D_LIB)
