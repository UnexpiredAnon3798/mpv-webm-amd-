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

# lua-language-server is called by its full path because on Windows, started
# through sh by its bare name, it can't spawn its workers and exits 0 without
# checking anything. Requiring the success message catches any other way it
# could skip the check.
typecheck:
	@luals="$$(command -v lua-language-server)" && \
	out="$$("$$luals" --check=. --checklevel=Warning --configpath=.luarc.json 2>&1)"; \
	status=$$?; printf '%s\n' "$$out"; \
	[ $$status -eq 0 ] && printf '%s' "$$out" | grep -q "no problems found"

check: lint typecheck test

install: all
	install -d $(MPVCONFIGDIR)/scripts/
	install -m 644 build/webm.lua $(MPVCONFIGDIR)/scripts/

clean:
	rm -rf build
