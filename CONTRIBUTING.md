# Contributing

Issues and pull requests are welcome. Open an issue first for anything that changes the public API or adds a
bundled integration. [ARCHITECTURE.md](ARCHITECTURE.md) explains how the pieces fit together.

Use Conventional Commits: `fix:` releases a patch, `feat:` a minor, and `!` or a `BREAKING CHANGE` footer a
major. Release Please owns `CHANGELOG.md` and `version.txt`.

## Setup

Neovim 0.11 or newer, StyLua, LuaLS, Luacheck, Pandoc, and Make. On macOS:

```sh
brew install neovim stylua lua-language-server luajit luarocks pandoc
LUAJIT_PREFIX="$(brew --prefix luajit)"
luarocks --lua-version=5.1 --lua-dir="$LUAJIT_PREFIX" --local install luacheck 1.2.0-1
eval "$(luarocks --lua-version=5.1 --lua-dir="$LUAJIT_PREFIX" --local path)"
```

`make lint` and `make typecheck` load that LuaRocks environment themselves. `mini.test` and panvimdoc download
into the ignored `deps/` on first use.

## Checks

```sh
make check
```

Formatting, docs, Luacheck, LuaLS, then the tests. Each is also its own target, and `make test-unit`,
`make test-integration`, and `make test-e2e` run a single suite.

## Tests

- `tests/unit/` — pure functions and protocol helpers. No LSP client, no tool integration.
- `tests/integration/` — stateful modules, adapters, and nvim-lint bridges, against inline output and a mocked
  nvim-lint.
- `tests/e2e/` — the public API through a real LSP request and Neovim's edit application.

Name each case as a sentence describing the invariant. Pure helpers go in `tests/helpers.lua`, buffer and
lifecycle helpers in `tests/support/`.

## Fixtures

`tests/fixtures/<tool>/` pairs a real source file with the tool's real output for it, so adapters are tested
against the exact bytes the tool saw. Inline output is fine for parsing edge cases; anything position-sensitive
needs a fixture. Where the adapter offers a whole-file action, `fixed.<ext>` is the source after the tool fixes
it, which pins the adapter to the tool's own ordering and overlap rules.

Regenerate from inside the fixture directory, so reported paths stay relative:

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

All three exit non-zero when they report findings. The golangci-lint output needs hand-trimming to `Issues`,
keeping only `FromLinter`, `Text`, `Pos`, and `SuggestedFixes`.

Fixtures are exempt from `.editorconfig`. Never let an editor add a final newline, trim trailing whitespace, or
reformat them: the captured offsets describe those bytes exactly.

## Documentation

`doc/` is generated. Never edit it by hand.

| Source | Help file |
| --- | --- |
| `README.md` | `doc/lint-actions.txt` |
| `docs/<tool>.md` | `doc/lint-actions-<tool>.txt` |

`make docs` regenerates them with [panvimdoc](https://github.com/kdheepak/panvimdoc) and rebuilds `doc/tags`.
Commit the result alongside the Markdown change; CI runs `make docs-check`. Pandoc is pinned in the `Makefile`
because panvimdoc's output tracks its version.

`make docs` fails with a specific message on a heading too long for its tag, a duplicate tag, or a dangling
cross-reference. The conventions it cannot check for you:

- One sentence per line, and a blank line between list items. Tight lists come out as a single long line, and
  numbered lists get no hanging indent either way, so use bullets.

- No emoji, and no table wider than two short columns. Both get mangled.

- Link within a document as `[Providers](#providers)`, where the text is the target heading. Link across
  documents as `` `:h lint-actions-sarif.txt` ``.

- `##### name({opts})` is what gives an API entry its bare `*name()*` tag.

- GitHub-only content goes between `<!-- panvimdoc-ignore-start -->` and `<!-- panvimdoc-ignore-end -->`.
