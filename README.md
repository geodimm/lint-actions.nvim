# lint-actions.nvim

Show linter fixes in Neovim's native LSP code actions.

Some linters tell you how to fix what they found, but that fix has nowhere to
go — Neovim's code-action menu only listens to LSP servers. This plugin gives
those fixes a way in, so they show up in `vim.lsp.buf.code_action()`, fzf-lua,
Telescope, or whatever picker you already use.

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
nvim-lint first, then turn on the integrations for the linters you use:

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

You can call `setup()` more than once to turn on more integrations later, and
enabling an already-enabled integration does nothing. `false` means "leave it
off" but it will not turn off an integration you enabled earlier.

lint-actions never runs a linter. The integrations reuse the output from lint
runs you already trigger. Each integration also has its own `attach()`
function if you want finer control.

## Integrations

Each integration has its own help page covering its requirements, options, and quirks:

- [golangci-lint with nvim-lint](doc/lint-actions-golangci.txt)
- [markdownlint-cli with nvim-lint](doc/lint-actions-markdownlint.txt)

Both are also available in Neovim as `:help lint-actions-golangci` and
`:help lint-actions-markdownlint`.

The nvim-lint bridge works for other tools too. It keeps the diagnostics from
any function-based nvim-lint parser while handing the same raw output to a fix
adapter. If your tool needs richer output, set its arguments and a matching
parser before attaching. See `:help lint-actions-nvim-lint`.

## Sending fixes to the menu

Every fix belongs to a **source** — a stable string naming whatever produced
it. There are two ways to get fixes from a source into the menu:

- **`publish()`** — you hand over the fixes when you have them. Good for fixes
  that come out of a tool when it finishes running.
- **`register()`** — you hand over a function, and it gets called when Neovim
  asks. Good for fixes you can work out from the buffer on the spot. See
  [Providers](#providers).

You do not list your own source in `setup()`. That option names bundled
integrations only, and rejects anything else so a typo gets reported instead of
silently ignored. Just call `publish()` or `register()` — both call `setup()`
for you, so order does not matter.

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

`range` says where in the buffer the action shows up. Matching is by line —
`character` is accepted so the shape stays valid, but it never narrows
anything. Leave `range` out to offer the action anywhere in the buffer.

### What `source` is for

`source` is a replacement key, nothing more. Publishing again for the same
source replaces only that source's actions, so several sources can share a
buffer without coordinating.

Neovim never shows it. The code-action menu labels an entry with the LSP
client name — `lint-actions` — and only when the buffer has more than one
client attached.

If you want your tool named in the menu, put it in `action.title` as a
bracketed suffix. The golangci-lint adapter titles its actions
`Apply suggested fix [errcheck]`, which reaches the menu as
`Apply suggested fix [errcheck] [lint-actions]`. A suffix beats a prefix: it
stacks neatly with Neovim's own label, and actions stay sorted by what they do
rather than clumped under whoever made them.

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

Reach for a full workspace edit when the fix touches several files or renames things:

```lua
action.edit = {
  documentChanges = {
    { textDocument = { uri = first_uri }, edits = first_edits },
    { textDocument = { uri = second_uri }, edits = second_edits },
  },
}
```

Either way Neovim gets a `CodeAction` holding a `WorkspaceEdit`, so pickers
that show diffs can diff both. What usually blocks a preview is an action that
carries an opaque `command` instead of an edit — not the choice between
`TextEdit` and `WorkspaceEdit`. (Neovim's built-in selector applies edits but
does not draw a diff itself.)

### Fixes that are not edits

If a fix cannot be written as a text edit, an action can carry an
`lsp.Command` instead of — or alongside — an edit. lint-actions passes it
through untouched and Neovim runs it client-side from `vim.lsp.commands`, so
register the handler before you publish:

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

A provider is the pull side. Instead of tracking when your fixes change and
pushing them, you give the plugin a function and it calls it when Neovim asks
for code actions.

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

`provide` runs while Neovim waits for the answer, so it has to be synchronous
and quick. If it throws, the plugin reports it and skips that provider; the
rest of the request still works. See `:help lint-actions-providers`.

[`examples/foldmarker.lua`](examples/foldmarker.lua) is a small working provider: it offers to add a 
fold marker modeline to a buffer that uses fold markers but has no modeline.
It reads the buffer, returns a rangeless whole-buffer item, and uses `enabled`
to stay out of the way elsewhere. It is an example and not a bundled integration so to use it
just copy it into your config and call its `setup()`.

## Health

`:checkhealth lint_actions` shows the Neovim version requirement, every
attached nvim-lint integration, and every registered provider.

A misconfigured integration would otherwise fail silently, since lint-actions
only ever sees output nvim-lint produces. So the check warns when an attached
linter is missing from `linters_by_ft`, when nvim-lint has no linter by that
name, or when a linter's command is not executable.

---

[ARCHITECTURE.md](ARCHITECTURE.md) explains how the pieces fit together and how stale fixes are kept out.

[CONTRIBUTING.md](CONTRIBUTING.md) has the development setup and commands.
