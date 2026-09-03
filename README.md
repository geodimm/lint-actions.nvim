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
        edit = { range = edit_range, newText = replacement },
      },
    },
  },
})
```

`action.edit` accepts one `lsp.TextEdit`, a list of text edits, or an
`lsp.WorkspaceEdit`. A text edit only describes a range replacement, so
`publish()` targets it at `bufnr` and wraps it in a versioned workspace edit.
This is the recommended form for ordinary same-buffer linter fixes:

```lua
action = {
  title = 'Apply all replacements',
  kind = 'quickfix',
  edit = {
    { range = first_range, newText = first_replacement },
    { range = second_range, newText = second_replacement },
  },
}
```

Use a full workspace edit when an action changes several documents or performs
ordered file operations:

```lua
action.edit = {
  documentChanges = {
    { textDocument = { uri = first_uri }, edits = first_edits },
    { textDocument = { uri = second_uri }, edits = second_edits },
  },
}
```

Both inputs are returned to Neovim as `CodeAction`s containing a
`WorkspaceEdit`, so preview-capable code-action pickers can compute a diff for
either one. An opaque `command`, rather than the choice between `TextEdit` and
`WorkspaceEdit`, is what normally prevents an edit preview. Neovim's built-in
code-action selector applies edits but does not itself render a diff preview.

See [the architecture note](ARCHITECTURE.md) for the data flow and stale-edit guarantees.

Development setup and commands are in [CONTRIBUTING.md](CONTRIBUTING.md).
