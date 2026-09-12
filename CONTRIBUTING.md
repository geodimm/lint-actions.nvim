# Contributing

Issues and pull requests are welcome. Open an issue first for anything that changes the public API or adds a
bundled integration. [ARCHITECTURE.md](ARCHITECTURE.md) explains how the pieces fit together.

Use Conventional Commits: `fix:` releases a patch, `feat:` a minor, and `!` or a `BREAKING CHANGE` footer a
major. Release Please owns `CHANGELOG.md` and `version.txt`.

## Setup

[Install Nix](https://nixos.org/download/) with flakes enabled, then enter the pinned development environment:

```sh
nix develop
```

With direnv installed, run `direnv allow` once instead. `flake.lock` pins Neovim, Busted, nlua, StyLua,
Luacheck, LuaLS, panvimdoc, and just, so local development and CI use the same toolchain.

## Checks

```sh
just check
```

This checks formatting, generated docs, Luacheck, LuaLS, then the tests. Use `just fmt`, `just docs`,
`just lint`, `just typecheck`, or `just test` individually. `just fmt-check` checks formatting without
changing files.

Run the same checks without an interactive shell with `nix develop .#ci --command just check`.

## Tests

Busted runs all specs inside Neovim through nlua. `.busted` defines the runner and loads `tests/init.lua`.
Name spec files `<module>_spec.lua`, group related cases with `describe()`, and define cases with `it()`.

Tests are organized by the part of the plugin they exercise:

| Area | Directory |
| --- | --- |
| Core modules | `tests/core/` |
| Output adapters | `tests/adapters/` |
| nvim-lint integrations | `tests/nvim_lint/` |
| LSP requests and edits | `tests/lsp/` |
| Example providers | `tests/examples/` |

Core specs cover the public API, action store, providers, protocol, offsets, buffers, health, and edit
normalization. LSP specs send real requests through Neovim's client and apply the returned edits.

Name each case as a sentence describing the invariant. Pure helpers go in `tests/helpers.lua`, buffer and
lifecycle helpers in `tests/support/`.

`just test` runs everything in one Neovim process. Power users can pass any Busted path or option through
`BUSTED_ARGS`:

```sh
BUSTED_ARGS='tests/core' just test
BUSTED_ARGS='--filter=provider' just test
BUSTED_ARGS='--shuffle' just test
```

CI also runs all tests against Neovim 0.11 and nightly using separate shells:

```sh
nix develop .#ci-0_11 --command just test
nix develop .#ci-nightly --command just test
```

The nightly build comes from the [nix-community binary cache](https://nix-community.org/cache/).
Without that cache configured, Nix builds Neovim from source. CI updates `neovim-nightly-overlay` before
running the nightly suite. To test the latest nightly locally, run `nix flake update neovim-nightly-overlay`
first.

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

`just docs` regenerates them with [panvimdoc](https://github.com/kdheepak/panvimdoc) and rebuilds `doc/tags`.
Commit the result alongside the Markdown change; CI runs `just docs-check`. The flake pins panvimdoc and its
Pandoc dependency, so local development and CI generate identical output.

`just docs` fails with a specific message on a heading too long for its tag, a duplicate tag, or a dangling
cross-reference. The conventions it cannot check for you:

- One sentence per line, and a blank line between list items. Tight lists come out as a single long line, and
  numbered lists get no hanging indent either way, so use bullets.

- No emoji, and no table wider than two short columns. Both get mangled.

- Link within a document as `[Providers](#providers)`, where the text is the target heading. Link across
  documents as `` `:h lint-actions-sarif.txt` ``.

- `##### name({opts})` is what gives an API entry its bare `*name()*` tag.

- GitHub-only content goes between `<!-- panvimdoc-ignore-start -->` and `<!-- panvimdoc-ignore-end -->`.
