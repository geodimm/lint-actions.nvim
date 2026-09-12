# Run every check CI runs
check: fmt-check docs-check lint typecheck test

# Format Lua sources
fmt:
    stylua examples lua tests

# Fail if any Lua source is unformatted
fmt-check:
    stylua --check examples lua tests

# Run Luacheck
lint:
    luacheck examples lua tests

# Run LuaLS type checking
typecheck:
    #!/usr/bin/env bash
    set -euo pipefail
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT
    export NVIM_LOG_FILE="${TEST_NVIM_LOG_FILE:-/dev/null}"
    VIMRUNTIME="$(nvim --clean -i NONE --headless --cmd 'lua io.write(vim.env.VIMRUNTIME)' --cmd 'quitall')" \
      lua-language-server --check=. --checklevel=Warning --check_format=pretty \
      --configpath=.luarc.json --logpath="$tmpdir/luals"

# Regenerate doc/ and doc/tags from the Markdown sources
docs:
    scripts/gen-docs.sh .

# Fail if the generated docs are stale
docs-check:
    #!/usr/bin/env bash
    set -euo pipefail
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT
    scripts/gen-docs.sh "$tmpdir"
    if ! diff -ru doc "$tmpdir/doc"; then
      echo >&2 "The Markdown sources and doc/ disagree. Run 'just docs' and commit the result."
      exit 1
    fi

# Run Busted inside Neovim; set BUSTED_ARGS for a focused run.
[private]
busted args:
    XDG_STATE_HOME="${TEST_STATE_HOME:-/tmp/lint-actions.nvim}" \
      NVIM_LOG_FILE="${TEST_NVIM_LOG_FILE:-/dev/null}" \
      busted {{ args }} ${BUSTED_ARGS:-} < /dev/null

# Run every spec. For example: `BUSTED_ARGS='tests/core' just test`.
test: (busted "")
