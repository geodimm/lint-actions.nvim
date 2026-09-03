.PHONY: check format format-check lint test typecheck

check: format-check lint typecheck test

format:
	stylua lua tests

format-check:
	stylua --check lua tests

lint:
	luacheck lua tests

typecheck:
	VIMRUNTIME="$$(NVIM_LOG_FILE=/tmp/lint-actions-typecheck-nvim.log nvim --clean --headless --cmd 'lua io.write(vim.env.VIMRUNTIME)' --cmd 'quitall')" \
		lua-language-server --check=. --checklevel=Warning --check_format=pretty --configpath=.luarc.json --logpath=.tmp/luals

test:
	XDG_STATE_HOME=/tmp/lint-actions.nvim NVIM_LOG_FILE=/tmp/lint-actions-nvim.log nvim --headless -u tests/minimal_init.lua -l tests/run.lua
