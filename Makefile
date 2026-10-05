# The build itself lives in tools/build.lua. These targets are shortcuts.
LUA ?= luajit
MPVCONFIGDIR := ~/.config/mpv/

.PHONY: all test unit golden lint format typecheck check install clean

all:
	$(LUA) tools/build.lua

test: unit golden

unit:
	busted

golden: all
	$(LUA) tests/golden/run.lua

lint:
	stylua --check .
	luacheck .

format:
	stylua .

typecheck:
	lua-language-server --check=. --checklevel=Warning --configpath=.luarc.json

check: lint typecheck test

install: all
	install -d $(MPVCONFIGDIR)/scripts/
	install -m 644 build/webm.lua $(MPVCONFIGDIR)/scripts/

clean:
	rm -rf build
