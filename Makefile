ODIN ?= odin
ODIN_FLAGS ?= -vet -strict-style
BIN := bin/game

.PHONY: all build run clean

all: build

build:
	mkdir -p bin
	$(ODIN) build . $(ODIN_FLAGS) -out:$(BIN)

run:
	$(ODIN) run . $(ODIN_FLAGS)

clean:
	rm -rf bin
