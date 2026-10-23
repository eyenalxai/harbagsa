ODIN ?= odin
ODIN_FLAGS ?= -vet -vet-style -vet-semicolon -vet-tabs -vet-using-param -vet-unused-procedures -vet-packages:main -strict-style -warnings-as-errors -disallow-do
BIN := bin/game

.PHONY: all build check run clean

all: build

build:
	mkdir -p bin
	$(ODIN) build . $(ODIN_FLAGS) -out:$(BIN)

check:
	$(ODIN) check . $(ODIN_FLAGS)

run:
	$(ODIN) run . $(ODIN_FLAGS)

clean:
	rm -rf bin
