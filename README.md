# lint-actions.nvim

Show linter fixes in Neovim's native LSP code actions.

Neovim's code-action UI only queries LSP clients. lint-actions.nvim exposes
structured fixes from linters through an in-process LSP server, so they appear
in `vim.lsp.buf.code_action()`, fzf-lua, Telescope, and other LSP-aware pickers.

![A golangci-lint fix exposed as a Neovim code action](media/demo.png)

Requires Neovim 0.11 or newer. The core has no dependencies and does not run linters.

## Installation

With `vim.pack` on Neovim 0.12 or newer:

```lua
vim.pack.add({
  'https://github.com/geodimm/lint-actions.nvim',
})
```

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'geodimm/lint-actions.nvim',
}
```

## Setup

The core setup has no dependencies:

```lua
require('lint_actions').setup()
```

The bundled integrations need
[nvim-lint](https://github.com/mfussenegger/nvim-lint). Install and configure
nvim-lint first, then enable the integrations for the linters you use:

```lua
require('lint_actions').setup({
  integrations = {
    nvim_lint = {
      golangci = true,
      markdownlint = true,
      shellcheck = true,
    },
  },
})
```

Use `true` for the defaults or an options table for an integration-specific override:

```lua
require('lint_actions').setup({
  integrations = {
    nvim_lint = {
      golangci = {
        linter = 'my_golangcilint',
        source = 'my-golangci',
      },
    },
  },
})
```

You can call `setup()` more than once to enable additional integrations.
Enabling an active integration has no effect. `false` skips an integration but
does not disable one enabled by an earlier call.

lint-actions never runs a linter. The integrations reuse the output from lint
runs you already trigger. Each integration also has its own `attach()`
function if you want finer control.

## Integrations

Each bundled integration or adapter has a help page covering its requirements, options, and quirks:

- [golangci-lint with nvim-lint](doc/lint-actions-golangci.txt)
- [markdownlint-cli with nvim-lint](doc/lint-actions-markdownlint.txt)
- [shellcheck with nvim-lint](doc/lint-actions-shellcheck.txt)
- [Reusable SARIF adapter](doc/lint-actions-sarif.txt)

They are also available in Neovim as `:help lint-actions-golangci`,
`:help lint-actions-markdownlint`, `:help lint-actions-shellcheck`, and
`:help lint-actions-sarif`.

The nvim-lint bridge also supports custom adapters. It preserves the
diagnostics from any function-based parser and passes the same raw output to
the adapter. If the adapter requires another output format, update the linter's
arguments and diagnostic parser together. See `:help lint-actions-nvim-lint`.

Tools that emit SARIF 2.1.0 fixes can share the bundled adapter instead of
needing a tool-specific one:

```lua
require('lint_actions.integrations.nvim_lint').attach({
  linter = 'my_sarif_linter',
  adapter = require('lint_actions.adapters.sarif'),
  source = 'my-sarif-linter',
})
```

The linter must already emit SARIF and parse its diagnostics from the same
output. The adapter supports alternative fixes, ordered text replacements,
URI base IDs, artifact indices, both SARIF column units, and multi-file fixes.
See `:help lint-actions-sarif` for setup details and safety constraints.

## Sending fixes to the menu

Every fix has a `source`, a stable string identifying its producer. Sources
supply actions in one of two ways:

- `publish()` stores actions computed ahead of the request, typically from a
  completed tool run.
- `register()` installs a synchronous provider that computes actions when
  Neovim requests them. See [Providers](#providers).

Custom sources do not belong in `setup()`. That option accepts bundled
integrations only and rejects unknown names. Call `publish()` or `register()`
directly; both initialize the plugin if necessary.

### Publishing

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

`range` controls where the action is offered. Matching is by line;
`character` is accepted as part of the LSP range but does not narrow the
match. Omit `range` to offer the action throughout the buffer.

### Source identity

`source` is the replacement key for a published batch. Publishing again for
the same source replaces only that source's actions, so several sources can
share a buffer without coordinating.

Neovim does not display `source`. When a buffer has multiple LSP clients, the
code-action menu labels each entry with its client name, `lint-actions` in this
case.

If you want your tool named in the menu, put it in `action.title` as a
bracketed suffix. The golangci-lint adapter titles its actions
`Apply suggested fix [errcheck]`, which reaches the menu as
`Apply suggested fix [errcheck] [lint-actions]`. A suffix composes with
Neovim's client label and keeps actions sorted by operation rather than source.

### Edits

`action.edit` takes one `lsp.TextEdit`, a list of them, or a full `lsp.WorkspaceEdit`.

A text edit only says "replace this range with this text", so `publish()`
points it at `bufnr` and wraps it in a versioned workspace edit for you. This
is the form to use for ordinary same-buffer linter fixes:

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

Use a full workspace edit when the fix touches several files or renames things:

```lua
action.edit = {
  documentChanges = {
    { textDocument = { uri = first_uri }, edits = first_edits },
    { textDocument = { uri = second_uri }, edits = second_edits },
  },
}
```

Both forms reach Neovim as a `CodeAction` containing a `WorkspaceEdit`, so a
preview-capable picker can diff either one. Actions that contain only an opaque
`command` usually cannot be previewed. Neovim's built-in selector applies
edits but does not display a diff.

### Fixes that are not edits

If a fix cannot be written as a text edit, an action can contain an
`lsp.Command` instead of or alongside an edit. lint-actions passes the command
through unchanged. Register its client-side handler in `vim.lsp.commands`
before publishing it:

```lua
vim.lsp.commands['my-tool.run'] = function(command, context)
  run(command.arguments[1], context.bufnr)
end
```

lint-actions advertises no `executeCommandProvider`, so Neovim does not execute
an unregistered command and warns instead. Prefer an edit wherever the fix can
be expressed as one: edits are previewable, version-checked against the
buffer, and undo as a single change.

## Providers

A provider computes actions when Neovim requests them. This avoids storing and
invalidating fixes derived directly from the current buffer.

```lua
require('lint_actions').register({
  source = 'my-tool',
  filetypes = { 'lua' },
  provide = function(context)
    return {
      {
        action = {
          title = 'Apply my fix',
          kind = 'quickfix',
          edit = { range = edit_range, newText = replacement },
        },
      },
    }
  end,
})
```

`provide` runs synchronously in the code-action request path and must return
quickly. If it raises an error, the plugin reports it and skips that provider;
the rest of the request still completes. See `:help lint-actions-providers`.

[`examples/foldmarker.lua`](examples/foldmarker.lua) is a small working provider. It offers to add a
fold marker modeline to a buffer that uses fold markers but has no modeline.
It reads the buffer, returns a rangeless whole-buffer item, and uses `enabled`
to limit the provider to relevant buffers. To use it, copy it into your config
and call its `setup()`; it is not a bundled integration.

## Health

`:checkhealth lint_actions` shows the Neovim version requirement, every
attached nvim-lint integration, and every registered provider.

lint-actions only receives output from linter runs, so some integration problems
would otherwise be silent. The check warns when an attached linter is missing
from `linters_by_ft`, when nvim-lint has no linter by that name, or when a
linter's command is not executable.

---

[ARCHITECTURE.md](ARCHITECTURE.md) explains how the pieces fit together and how stale fixes are kept out.

[CONTRIBUTING.md](CONTRIBUTING.md) has the development setup and commands.
