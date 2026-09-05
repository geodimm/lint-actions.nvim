# Development

The local toolchain is Neovim 0.11 or newer, StyLua, LuaLS, Luacheck, and Make. On macOS:

```sh
brew install neovim stylua lua-language-server luajit luarocks
LUAJIT_PREFIX="$(brew --prefix luajit)"
luarocks --lua-version=5.1 --lua-dir="$LUAJIT_PREFIX" --local install luacheck 1.2.0-1
eval "$(luarocks --lua-version=5.1 --lua-dir="$LUAJIT_PREFIX" --local path)"
```

The `lint` and `typecheck` Make targets load this LuaRocks environment automatically when Homebrew and LuaRocks
are available. Linux CI skips that optional setup and uses its installed standalone tools.

Run the complete check with `make check`.
Individual targets are `make format`, `make format-check`, `make lint`, `make typecheck`, and `make test`.
The test target runs three named suites; run `make test-unit`, `make test-integration`, or `make test-e2e`
when working on one layer.

Tests use [`mini.test`](https://github.com/nvim-mini/mini.test), which is downloaded into the ignored `deps/`
directory by the first `make test`. It is a development-only dependency and is not loaded by the plugin at runtime.

Tests are deliberately separated by the boundary they exercise:

- `tests/unit/` contains deterministic functions and protocol helpers. These tests do not start the plugin's LSP
  client or depend on a tool integration.
- `tests/integration/` exercises stateful modules, adapters, and nvim-lint bridges. Adapter tests use small inline
  tool output; bridge tests use a mocked nvim-lint module.
- `tests/e2e/` uses the public API, a real in-process LSP request, and Neovim's edit application. Recorded tool
  fixtures live here when the assertion is the complete user journey.

Within a file, group cases by behavior (`matching by kind`, `batch freshness`, or `integration.attach()`) and name
each case as a sentence describing the invariant. Shared pure helpers belong in `tests/helpers.lua`; buffer,
fixture, and lifecycle helpers belong in `tests/support/`.

## Fixtures

Each bundled integration has a directory under `tests/fixtures/<tool>/` holding a small source file
(`playground.<ext>`) and the tool's real output for it (`output.json`). A fixture test loads the source file into a
buffer, runs the captured output through the adapter, and applies the resulting edits. Positions in tool output are
byte offsets or line and column pairs into a specific file. A fixture verifies that the adapter places edits correctly
in the exact input processed by the tool. Inline output is sufficient for parsing edge cases and malformed input;
position tests should use real fixture output.

Where the adapter offers a whole-file action, `fixed.<ext>` contains the source after the tool applies its own fixes.
Asserting against that file pins the adapter to the tool's ordering and overlap rules.

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

All three linters exit non-zero when they report findings; this is expected during fixture generation. markdownlint
writes its JSON to stderr, while shellcheck emits JSON on one line. The commands above reformat that output and
reproduce the committed files byte for byte.

The golangci-lint fixture requires manual cleanup. The command prints a summary line after the JSON, and each issue
contains fields the adapter never reads. The committed `output.json` therefore keeps only `Issues` and, within each
issue, `FromLinter`, `Text`, `Pos`, and `SuggestedFixes`, laid out by hand for readability.
`tests/fixtures/golangci/.golangci.yml` pins the enabled linters so the findings do not depend on a personal config
found further up the tree.

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
