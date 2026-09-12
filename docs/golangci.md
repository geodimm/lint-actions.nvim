<!-- panvimdoc-ignore-start -->

# golangci-lint with nvim-lint

<!-- panvimdoc-ignore-end -->

golangci-lint reports a `SuggestedFixes` block for many of its findings.
This integration turns those into Neovim code actions.
It reads output nvim-lint has already collected, so golangci-lint does not run twice.

## Requirements

- Neovim 0.11 or newer.

- [nvim-lint](https://github.com/mfussenegger/nvim-lint).

- [golangci-lint](https://github.com/golangci/golangci-lint) v2, available as `golangci-lint`.

## Configuration

Configure nvim-lint first, then enable the integration and trigger the linter as you normally would:

```lua
local lint = require('lint')
lint.linters_by_ft.go = { 'golangcilint' }

require('lint_actions').setup({
  integrations = {
    nvim_lint = {
      golangci = true,
    },
  },
})
```

Trigger nvim-lint from a command, a mapping, or an autocmd.

The default named linter is loaded lazily.
Enabling this integration therefore does not run nvim-lint's golangci-lint version or Go module discovery during Neovim startup; those happen when golangci-lint first runs.

Actions are only kept when the buffer is unmodified.
golangci-lint reads the file from disk, so its fixes describe the saved file.
Applying them to a buffer you have since edited would put the text in the wrong place.

## Advanced configuration

The default linter name is `golangcilint`.
You can point the integration at a different name or at a linter definition, and change the source it publishes under:

```lua
require('lint_actions').setup({
  integrations = {
    nvim_lint = {
      golangci = {
        linter = require('lint').linters.golangcilint,
        source = 'my-golangci',
      },
    },
  },
})
```

`require('lint_actions.integrations.golangci').attach()` accepts the same options for direct use.

Set `defer = false` to resolve a named linter immediately.
Concrete linter definitions are always attached immediately because they are already loaded.

To write an adapter for a different tool, see `:h lint-actions-nvim-lint`.

## Actions

Every usable `SuggestedFix` for the current file becomes a `quickfix` action.
The title uses the suggested-fix message when there is one, and names the linter that found the problem.

The entire suggestion is skipped if any replacement has invalid Base64 or an invalid byte range.
Offsets must be integers within the buffer, with the end at or after the start.
Valid alternative suggestions remain available.
Empty and null replacement text represent deletions.

Edits go out as versioned workspace edits.
They go stale as soon as the buffer changes, and pickers that show diffs can preview them.
