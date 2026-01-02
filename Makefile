.PHONY: all build install clean fmt lint test

BINARY = planz
INSTALL_PATH = $(HOME)/.local/bin

all: fmt lint build install

build:
	zig build

install: build
	mkdir -p $(INSTALL_PATH)
	cp zig-out/bin/$(BINARY) $(INSTALL_PATH)/$(BINARY)

clean:
	rm -rf zig-out .zig-cache

fmt:
	zig fmt src/

lint:
	./scripts/lint.sh

test: install
	./tests/test_runner.sh
