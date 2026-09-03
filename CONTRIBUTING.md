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

Run one file with `make test-file FILE=tests/test_offsets.lua`.

To exercise the pull-request workflow locally, start Docker and install [`act`](https://github.com/nektos/act):

```sh
brew install act
act pull_request -W .github/workflows/ci.yaml \
  -s GITHUB_TOKEN="$(gh auth token)"
```

Use Conventional Commit prefixes for changes that should be released.
`fix:` produces a patch release, `feat:` a minor release, and a `!` or `BREAKING CHANGE` footer a major release.
After CI passes on `main`, Release Please opens or updates a release PR; merging it creates the SemVer tag and GitHub release.
