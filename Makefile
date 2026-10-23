ODIN ?= odin
ODIN_FLAGS ?= -vet -vet-style -vet-semicolon -vet-tabs -vet-using-param -vet-unused-procedures -vet-packages:main -strict-style -warnings-as-errors -disallow-do
ODIN_COLLECTIONS := -collection:libs=vendor -collection:src=src
BIN := bin/harbagsa

CC ?= cc
BOX3D_DIR := vendor/box3d
BOX3D_SRC := $(wildcard $(BOX3D_DIR)/src/src/*.c)
BOX3D_OBJ := $(patsubst $(BOX3D_DIR)/src/src/%.c,build/box3d/%.o,$(BOX3D_SRC))
BOX3D_LIB := $(BOX3D_DIR)/lib/linux-amd64/libbox3d.a

.PHONY: all build check test run clean

all: build

$(BOX3D_LIB): $(BOX3D_OBJ)
	@mkdir -p $(@D)
	rm -f $@
	ar rcs $@ $(BOX3D_OBJ)

build/box3d/%.o: $(BOX3D_DIR)/src/src/%.c
	@mkdir -p $(@D)
	$(CC) -c -O2 -std=c17 -fPIC -I$(BOX3D_DIR)/src/include $< -o $@

build: $(BOX3D_LIB)
	mkdir -p bin
	$(ODIN) build . $(ODIN_FLAGS) $(ODIN_COLLECTIONS) -out:$(BIN)

check: $(BOX3D_LIB)
	$(ODIN) check . $(ODIN_FLAGS) $(ODIN_COLLECTIONS)

test: $(BOX3D_LIB)
	$(ODIN) test tests/physics $(ODIN_FLAGS) $(ODIN_COLLECTIONS)
	# Box3D's world registry is not safe for concurrent world creation, so the
	# simulation tests share one runner thread.
	$(ODIN) test tests/simulation $(ODIN_FLAGS) $(ODIN_COLLECTIONS) -define:ODIN_TEST_THREADS=1

run: $(BOX3D_LIB)
	$(ODIN) run . $(ODIN_FLAGS) $(ODIN_COLLECTIONS)

clean:
	rm -rf bin build $(BOX3D_LIB)
