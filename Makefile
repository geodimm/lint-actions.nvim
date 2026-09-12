MINITEST_DIR := deps/mini.test
PANVIMDOC_DIR := deps/panvimdoc

# The generated help files must be byte-identical everywhere, and panvimdoc
# output tracks the Pandoc release, so both are pinned. CI reads the Pandoc
# version from `make pandoc-version` and installs that build.
PANVIMDOC_REV := v4.0.1
PANDOC_VERSION := 3.11

.PHONY: check docs docs-check format format-check lint pandoc-version test test-unit test-integration test-e2e typecheck

# Homebrew's LuaRocks install is tied to Lua 5.1/LuaJIT on macOS. Keep this
# optional: CI installs standalone tools and has no Homebrew dependency.
define LOAD_LUAJIT_ROCKS
if command -v brew >/dev/null 2>&1 && command -v luarocks >/dev/null 2>&1; then \
	LUAJIT_PREFIX="$$(brew --prefix luajit 2>/dev/null || true)"; \
	if [ -n "$$LUAJIT_PREFIX" ]; then \
		eval "$$(luarocks --lua-version=5.1 --lua-dir="$$LUAJIT_PREFIX" --local path)"; \
	fi; \
fi;
endef

check: format-check docs-check lint typecheck test

format:
	stylua examples lua tests

format-check:
	stylua --check examples lua tests

lint:
	@$(LOAD_LUAJIT_ROCKS) \
	luacheck examples lua tests

typecheck:
	@$(LOAD_LUAJIT_ROCKS) \
	VIMRUNTIME="$$(NVIM_LOG_FILE=/tmp/lint-actions-typecheck-nvim.log nvim --clean --headless --cmd 'lua io.write(vim.env.VIMRUNTIME)' --cmd 'quitall')" \
		lua-language-server --check=. --checklevel=Warning --check_format=pretty --configpath=.luarc.json --logpath=.tmp/luals

docs: $(PANVIMDOC_DIR)
	PANVIMDOC_DIR=$(PANVIMDOC_DIR) PANDOC_VERSION=$(PANDOC_VERSION) scripts/gen-docs.sh .

docs-check: $(PANVIMDOC_DIR)
	@tmpdir="$$(mktemp -d)"; \
	trap 'rm -rf "$$tmpdir"' EXIT; \
	PANVIMDOC_DIR=$(PANVIMDOC_DIR) PANDOC_VERSION=$(PANDOC_VERSION) scripts/gen-docs.sh "$$tmpdir" || exit 1; \
	if ! diff -ru doc "$$tmpdir/doc"; then \
		echo >&2 "The Markdown sources and doc/ disagree. Run 'make docs' and commit the result."; \
		exit 1; \
	fi

pandoc-version:
	@echo $(PANDOC_VERSION)

test: test-unit test-integration test-e2e

test-unit test-integration test-e2e: $(MINITEST_DIR)
	XDG_STATE_HOME=/tmp/lint-actions.nvim NVIM_LOG_FILE=/tmp/lint-actions-nvim.log nvim --headless -u tests/minimal_init.lua -l tests/run.lua $(@:test-%=%)

$(MINITEST_DIR):
	mkdir -p deps
	git clone --filter=blob:none --branch stable https://github.com/nvim-mini/mini.test $@

$(PANVIMDOC_DIR):
	mkdir -p deps
	git -c advice.detachedHead=false clone --filter=blob:none --branch $(PANVIMDOC_REV) \
		https://github.com/kdheepak/panvimdoc $@
