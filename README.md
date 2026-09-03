# lint-actions.nvim

Expose structured linter fixes as native Neovim LSP code actions. Actions work with `vim.lsp.buf.code_action()`, fzf-lua, Telescope, and other LSP clients without replacing their UI.

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

The bundled integrations require
[nvim-lint](https://github.com/mfussenegger/nvim-lint). After installing and
configuring nvim-lint, enable the integrations for the linters you use:

```lua
require('lint_actions').setup({
  integrations = {
    nvim_lint = {
      golangci = true,
      markdownlint = true,
    },
  },
})
```

Use `true` for the defaults or an options table for an integration-specific
override:

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

Setup is additive and idempotent: later calls may enable more integrations,
and attaching an already attached integration is harmless. `false` leaves an
integration disabled; it does not detach one enabled by an earlier call.

lint-actions does not run linters itself. Its integrations reuse output from
your existing nvim-lint runs. The direct integration `attach()` functions
remain available for lower-level configuration.

## Integrations

Integration-specific dependencies, configuration, and behavior live in
versioned Vim help guides:

- [golangci-lint with nvim-lint](doc/lint-actions-golangci.txt)
- [markdownlint-cli with nvim-lint](doc/lint-actions-markdownlint.txt)

They are also available inside Neovim with `:help lint-actions-golangci` and
`:help lint-actions-markdownlint`.

The nvim-lint bridge is also an extension point for other tools. It preserves
diagnostics from any function-based nvim-lint parser while passing the same
raw output to a fix adapter. If a tool needs a richer output format, configure
its arguments and matching parser before attaching the bridge. See
`:help lint-actions-nvim-lint`.

## Publishing actions

Actions belong to a source: a stable string naming whatever produced them. A
source supplies its actions one of two ways. It can *push* them with
`publish()`, which suits fixes that arrive from a tool when it finishes, or it
can be *pulled* by registering a [provider](#providers), which suits actions
derived from buffer content.

`setup()` names bundled integrations only and rejects any other key, so a typo
is reported rather than ignored. A third-party source is not registered there —
it calls `publish()` or `register()` directly, and both call `setup()`
themselves, so no ordering is required.

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

`source` is a replacement key, not provenance shown to the user. Republishing
a source replaces only its own actions, so several sources coexist without
coordinating. Neovim never displays it — its code-action UI labels an entry
with the LSP client name, `lint-actions`, and only when more than one client is
attached to the buffer.

A source that wants to name itself does so in `action.title`, as a bracketed
suffix matching that convention. The bundled golangci-lint adapter titles its
actions `Apply suggested fix [errcheck]`, which renders as `Apply suggested fix
[errcheck] [lint-actions]`. Prefer a suffix over a prefix: it stacks with
Neovim's own label, and it leaves actions sorted by what they do rather than
clustered under whoever produced them.

An item's `range` says where the action is offered, and matching is
line-granular — `character` is accepted for protocol shape but never narrows a
match. Omit `range` to offer the action anywhere in the buffer.

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

An action may carry an `lsp.Command` instead of, or alongside, an edit, for a
fix that cannot be expressed as a text edit. lint-actions returns it unchanged
and Neovim resolves it client-side against `vim.lsp.commands`, so register the
handler before publishing the action:

```lua
vim.lsp.commands['my-tool.run'] = function(command, context)
  run(command.arguments[1], context.bufnr)
end
```

lint-actions advertises no `executeCommandProvider`, so an unregistered name is
not executed and warns instead. Prefer an edit wherever the fix can be
expressed as one: edits are previewable, version-checked against the buffer,
and undo as a single change.

## Providers

A provider is the pull half of the two ways above. Rather than deciding when
its actions change and pushing them, it is asked for them when Neovim requests
code actions — no autocmds, no debouncing, and nothing to keep fresh:

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

`provide` runs inside the code-action request, so it must be synchronous and
fast. A provider that raises is reported and skipped without affecting the
rest of the request. See `:help lint-actions-providers`.

See [the architecture note](ARCHITECTURE.md) for the data flow and stale-edit guarantees.

Development setup and commands are in [CONTRIBUTING.md](CONTRIBUTING.md).
