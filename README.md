# lint-actions.nvim

Expose structured linter fixes as native Neovim LSP code actions. Actions work with `vim.lsp.buf.code_action()`, fzf-lua, Telescope, and other LSP clients without replacing their UI.

![A golangci-lint fix exposed as a Neovim code action](media/demo.png)

Requires Neovim 0.11 or newer. The core has no dependencies and does not run linters.

## Installation

With `vim.pack` on Neovim 0.12 or newer:

```lua
vim.pack.add({
  'https://github.com/geodimm/lint-actions.nvim',
  'https://github.com/mfussenegger/nvim-lint',
})
```

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'geodimm/lint-actions.nvim',
  dependencies = { 'mfussenegger/nvim-lint' },
}
```

## Setup

Connect fixes produced by [nvim-lint](https://github.com/mfussenegger/nvim-lint) and [golangci-lint](https://github.com/golangci/golangci-lint):

```lua
local lint = require('lint')

require('lint_actions').setup()
require('lint_actions.integrations.nvim_lint').attach({
  linter = 'golangcilint',
  adapter = require('lint_actions.adapters.golangci'),
})

lint.linters_by_ft.go = { 'golangcilint' }
```

Install the `golangci-lint` executable and trigger `nvim-lint` as usual. This plugin reuses the same process output; it does not run the linter again.

## Publishing actions

Other tools can publish native actions directly:

```lua
local lint_actions = require('lint_actions')

lint_actions.setup()

lint_actions.publish({
  bufnr = bufnr,
  source = 'my-tool',
  items = {
    {
      range = range,
      action = {
        title = 'Apply suggested fix',
        kind = 'quickfix',
        edit = workspace_edit,
      },
    },
  },
})
```

See [the architecture note](ARCHITECTURE.md) for the data flow and stale-edit guarantees.

Development setup and commands are in [CONTRIBUTING.md](CONTRIBUTING.md).
