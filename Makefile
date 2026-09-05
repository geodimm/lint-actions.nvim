MINITEST_DIR := deps/mini.test

.PHONY: check format format-check lint test test-unit test-integration test-e2e typecheck

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

check: format-check lint typecheck test

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

test: test-unit test-integration test-e2e

test-unit test-integration test-e2e: $(MINITEST_DIR)
	XDG_STATE_HOME=/tmp/lint-actions.nvim NVIM_LOG_FILE=/tmp/lint-actions-nvim.log nvim --headless -u tests/minimal_init.lua -l tests/run.lua $(@:test-%=%)

$(MINITEST_DIR):
	mkdir -p deps
	git clone --filter=blob:none --branch stable https://github.com/nvim-mini/mini.test $@
