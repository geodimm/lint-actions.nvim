# Development

The local toolchain is Neovim 0.11 or newer, StyLua, LuaLS, Luacheck, and Make. On macOS:

```sh
brew install neovim stylua lua-language-server luajit luarocks
LUAJIT_PREFIX="$(brew --prefix luajit)"
luarocks --lua-version=5.1 --lua-dir="$LUAJIT_PREFIX" --local install luacheck 1.2.0-1
eval "$(luarocks --lua-version=5.1 --lua-dir="$LUAJIT_PREFIX" --local path)"
```

Run the complete check with `make check`.
Individual targets are `make format`, `make format-check`, `make lint`, `make typecheck`, and `make test`.

Tests use [`mini.test`](https://github.com/nvim-mini/mini.test), which is downloaded into the ignored `deps/`
directory by the first `make test`. It is a development-only dependency and is not loaded by the plugin at runtime.

Test files follow `tests/test_<area>.lua`, where `<area>` names the module or integration under test (for example,
`test_offsets.lua`, `test_store.lua`, or `test_nvim_lint.lua`). Within a file, nest cases under the public function
name such as `to_position()` or `attach()`. Shared setup belongs in `tests/helpers.lua`.

## Fixtures

Each bundled integration has a directory under `tests/fixtures/<tool>/` holding a small source file
(`playground.<ext>`) and the tool's real output for it (`output.json`). A fixture test loads the source file into a
buffer, runs the captured output through the adapter, and applies the resulting edits. Positions in tool output are
byte offsets or line and column pairs into a specific file, so this is the only way to prove an adapter places its
edits where the tool meant them. Hand-written output in a test file cannot; use inline output for parsing edge cases
and malformed input, and a fixture for "does this actually work against the real thing".

Where the adapter offers a whole-file action, the directory also holds `fixed.<ext>`: the same source after the tool
fixed it itself. Asserting against that file pins the adapter to the tool's own ordering and overlap rules.

Regenerate a fixture by running the tool inside its directory, so the paths it reports stay relative:

```sh
cd tests/fixtures/shellcheck
shellcheck --format json1 playground.sh | python3 -m json.tool --indent 2 > output.json
cp playground.sh fixed.sh && shellcheck --format=diff fixed.sh | patch fixed.sh

cd tests/fixtures/markdownlint
markdownlint --json playground.md 2> output.json
cp playground.md fixed.md && markdownlint --fix fixed.md

cd tests/fixtures/golangci
golangci-lint run --output.json.path stdout | head -n 1
```

All three linters exit non-zero when they find something, which is the point here. markdownlint writes its JSON to
stderr, and shellcheck writes its own on one line, hence the reformatting. Those two commands reproduce the committed
files byte for byte.

golangci-lint needs more handling. It prints a summary line after the JSON, and each issue carries fields the adapter
never reads, so the committed `output.json` keeps only `Issues` and, within each issue, `FromLinter`, `Text`, `Pos`,
and `SuggestedFixes`, laid out by hand for readability. `tests/fixtures/golangci/.golangci.yml` pins which linters
run, so the findings do not depend on a personal config found further up the tree.

Fixtures are exempted from `.editorconfig` normalisation. Do not let an editor add a final newline, trim trailing
whitespace, or reformat these files: `playground.md` deliberately ends without a newline and carries trailing spaces,
and the captured offsets describe the bytes exactly as they are.

## CI

To exercise the pull-request workflow locally, start Docker and install [`act`](https://github.com/nektos/act):

```sh
brew install act
act pull_request -W .github/workflows/ci.yaml \
  -s GITHUB_TOKEN="$(gh auth token)"
```

Use Conventional Commit prefixes for changes that should be released.
`fix:` produces a patch release, `feat:` a minor release, and a `!` or `BREAKING CHANGE` footer a major release.
After CI passes on `main`, Release Please opens or updates a release PR; merging it creates the SemVer tag and GitHub release.
