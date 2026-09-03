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

Tests run directly inside headless Neovim and have no Lua test-framework dependency.

To exercise the pull-request workflow locally, start Docker and install [`act`](https://github.com/nektos/act):

```sh
brew install act
act pull_request -W .github/workflows/ci.yaml \
  -s GITHUB_TOKEN="$(gh auth token)"
```

Use Conventional Commit prefixes for changes that should be released.
`fix:` produces a patch release, `feat:` a minor release, and a `!` or `BREAKING CHANGE` footer a major release.
After CI passes on `main`, Release Please opens or updates a release PR; merging it creates the SemVer tag and GitHub release.
