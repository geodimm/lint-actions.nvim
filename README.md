<!-- panvimdoc-ignore-start -->

# lint-actions.nvim

[![CI](https://github.com/geodimm/lint-actions.nvim/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/geodimm/lint-actions.nvim/actions/workflows/ci.yaml)

Show linter fixes and custom actions in Neovim's native LSP code-action UI.

![A golangci-lint fix exposed as a Neovim code action](media/demo.png)

<!-- panvimdoc-ignore-end -->

## Features

- Fixes from external tools appear in `vim.lsp.buf.code_action()`, so every LSP-aware picker lists them: the built-in menu, fzf-lua, Telescope, and the rest.

- Bundled integrations for golangci-lint, markdownlint, and shellcheck reuse the output of lint runs you already trigger, so no tool runs twice.

- A reusable SARIF 2.1.0 adapter covers any tool that emits standard `result.fixes`, including fixes that span several files.

- Actions carry real workspace edits, so a preview-capable picker can diff them and Neovim undoes each one in a single step.

- Stale fixes are dropped rather than misapplied: every batch is tied to the buffer's changed tick when the tool ran, and edits are version-checked when applied.

- Lua providers compute actions on demand for fixes derived from the buffer itself, with no cache to invalidate.

## How it works

Neovim's code-action UI only queries LSP clients.
lint-actions.nvim exposes structured actions from external tools and Lua providers through an in-process LSP server, so they appear in `vim.lsp.buf.code_action()`, fzf-lua, Telescope, and other LSP-aware pickers.

Linters are the primary use case, but actions do not have to come from a linter.
`publish()` accepts actions computed elsewhere, while `register()` lets lightweight providers derive actions directly from the current buffer.

The scope is deliberately narrow: lint-actions implements `textDocument/codeAction`.
It neither runs tools nor advertises diagnostics, formatting, or other LSP capabilities, and it provides no code-action UI.
The selected UI handles selection and any preview; Neovim applies the action and manages undo.

## Requirements

- Neovim 0.11 or newer.

- The core has no dependencies.

- The bundled integrations need [nvim-lint](https://github.com/mfussenegger/nvim-lint).

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

## Quickstart

Install [nvim-lint](https://github.com/mfussenegger/nvim-lint) alongside lint-actions, then:

```lua
local lint = require('lint')
lint.linters_by_ft.sh = { 'shellcheck' }

require('lint_actions').setup({
  integrations = {
    nvim_lint = {
      shellcheck = true,
    },
  },
})

vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost' }, {
  pattern = '*.sh',
  callback = function()
    lint.try_lint()
  end,
})

vim.keymap.set({ 'n', 'v' }, '<leader>ca', vim.lsp.buf.code_action)
```

Open a shell script that shellcheck can fix, save it, then press `<leader>ca`.
The menu offers `Fix SC2086: Double quote to prevent globbing and word splitting. [lint-actions]` next to whatever your language server contributes, and one `Fix all shellcheck issues` for the whole file.

Nothing in the menu? Run `:checkhealth lint_actions`.

Swap `shellcheck` for `golangci` or `markdownlint` to do the same for Go or Markdown.

## Setup

The core setup has no dependencies:

```lua
require('lint_actions').setup()
```

Install and configure nvim-lint first, then enable the integrations for the linters you use:

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

lint-actions never runs a linter.
The integrations reuse the output from lint runs you already trigger.
Each integration also has its own `attach()` function if you want finer control.

Custom sources do not belong in `setup()`.
That option accepts bundled integrations only and rejects unknown names.
Call `:h lint_actions.publish()` or `:h lint_actions.register()` directly; both initialize the plugin if necessary.

##### lint_actions.setup({opts})

Initializes lint-actions.
`opts.integrations.nvim_lint` enables the bundled integrations, each with `true` or an options table.

You can call `setup()` more than once to enable additional integrations.
Enabling an active integration has no effect.
`false` skips an integration but does not disable one enabled by an earlier call.

When an integration attaches a linter by name, `setup()` fails immediately if nvim-lint is unavailable.

## Integrations

Each bundled integration or adapter has a guide covering its requirements, options, and quirks:

- [golangci-lint](docs/golangci.md), or `:h lint-actions-golangci.txt`

- [markdownlint](docs/markdownlint.md), or `:h lint-actions-markdownlint.txt`

- [shellcheck](docs/shellcheck.md), or `:h lint-actions-shellcheck.txt`

- [SARIF](docs/sarif.md), or `:h lint-actions-sarif.txt`

The first three read nvim-lint's output. The SARIF adapter is reusable and not tied to a particular linter.

The golangci-lint integration defers loading nvim-lint's linter definition until its first run.
This keeps golangci-lint's version and Go module discovery out of Neovim startup.

Tools that emit SARIF 2.1.0 fixes can share the bundled adapter instead of needing a tool-specific one:

```lua
require('lint_actions.integrations.nvim_lint').attach({
  linter = 'my_sarif_linter',
  adapter = require('lint_actions.adapters.sarif'),
  source = 'my-sarif-linter',
})
```

The linter must already emit SARIF and parse its diagnostics from the same output.
The adapter supports alternative fixes, ordered text replacements, URI base IDs, artifact indices, both SARIF column units, and multi-file fixes.
See the [SARIF](docs/sarif.md) guide for setup details and safety constraints.

## nvim-lint

nvim-lint runs the linter process and publishes diagnostics.
Each linter's `parser` function reads the output.
lint-actions wraps that parser without changing the diagnostics:

- lint-actions records the buffer's changed tick before nvim-lint runs the configured command.

- The linter's parser turns the output into `vim.Diagnostic[]`.

- lint-actions hands the same raw output and those diagnostics to the adapter, unless the buffer changed during the run or the run was cancelled.

- The adapter returns code-action items.

- The original diagnostics go back to nvim-lint unchanged.

Saving the buffer again while a linter runs does not make its old output fresh.
Each run retains its own snapshot.
Rejected output leaves any actions from a newer run alone.
The integration installs one wrapper around nvim-lint's `lint()` entry point and only binds snapshots for attached parsers.

Any function-based nvim-lint parser can be wrapped this way.
To connect one to an adapter:

```lua
require('lint_actions.integrations.nvim_lint').attach({
  linter = 'linter-name',
  adapter = require('my_adapter'),
  source = 'optional-source-override',
  configure = optional_function,
  defer = false,
})
```

- `linter` takes a registered nvim-lint name or a linter definition.

- `adapter` is a table with a `source` field and a `parse(context)` function.

- `source` overrides the adapter's own source name.

- `configure` runs against the resolved linter immediately before its parser is wrapped.

- `defer` set to `true` waits until nvim-lint first runs a named built-in linter.
  User-defined linters already stored in `lint.linters` and concrete definitions are attached immediately.

On its own, `attach()` does not touch the linter's command or arguments.
Use `configure` for that.

If you already have finished actions, skip nvim-lint entirely and call `:h lint_actions.publish()`.
To run raw output through an adapter yourself, use `:h lint_actions.ingest()`.

### Output format

An adapter may need structured output that the default parser cannot read, such as JSON instead of plain text.
Adding a `--json` argument alone would break diagnostics because the old parser would receive the wrong format.
The argument and parser must change together.

For a table-based linter, update both before attaching:

```lua
local lint = require('lint')
local adapter = require('my_json_adapter')
local linter = lint.linters.my_linter

table.insert(linter.args, '--json')
linter.parser = adapter.diagnostics

require('lint_actions.integrations.nvim_lint').attach({
  linter = linter,
  adapter = adapter,
})
```

The replacement parser must take `(output, bufnr, cwd)` and return `vim.Diagnostic[]`.
The adapter's `parse(context)` then receives `context.output`, `context.bufnr`, `context.cwd`, and those diagnostics as `context.diagnostics`.

Editing the linter directly only works if it is a plain table.
nvim-lint also supports factories, which rebuild the definition on every run.
Pass `configure` to modify the resolved definition before lint-actions wraps its parser:

```lua
require('lint_actions.integrations.nvim_lint').attach({
  linter = 'my_linter',
  adapter = adapter,
  configure = function(linter)
    linter.args = linter.args or {}
    table.insert(linter.args, '--json')
    linter.parser = adapter.diagnostics
  end,
})
```

`configure` receives the resolved linter immediately before its parser is wrapped.
It runs once for a table definition and once per generated definition for a factory.
Attaching without `configure` and adding one later raises an error, because configuration must precede the wrapper.

The [markdownlint](docs/markdownlint.md) guide has a complete configuration.

## Publishing

Every action has a source: a stable string identifying its producer.
Sources supply actions in one of two ways.

- `publish()` stores actions computed ahead of the request, typically from a completed tool run.

- `register()` installs a synchronous provider that computes actions when Neovim requests them.
  See [Providers](#providers).

##### lint_actions.publish({opts})

Replaces the actions for one buffer and source.
An empty `items` list clears that source.

- `bufnr` is the buffer the actions belong to.

- `source` is a stable name for whatever produced them.

- `items` is a list of `{ range = range, action = action }`.
  Each action is an `lsp.CodeAction`, except that its `edit` may also be one `lsp.TextEdit` or a list of text edits aimed at `bufnr`.

An item's `range` controls where the action is offered.
Matching is by line; `character` is accepted as part of the LSP range but does not narrow the match.
Omit `range` to offer the action throughout the buffer.

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

##### lint_actions.clear({opts})

Clears one source for a buffer.
Omit `source` to clear all of them.

##### lint_actions.ingest({opts})

Runs tool output through `opts.adapter` and publishes what comes back.

### Source identity

`source` is the replacement key for a published batch.
Publishing again for the same source replaces only that source's actions, so several sources can share a buffer without coordinating.

Neovim does not display `source`.
When a buffer has multiple LSP clients, the code-action menu labels each entry with its client name, `lint-actions` in this case.

To name your tool in the menu, put it in `action.title` as a bracketed suffix.
The golangci-lint adapter titles its actions `Apply suggested fix [errcheck]`, which reaches the menu as `Apply suggested fix [errcheck] [lint-actions]`.
Keep the tool name as a suffix so actions remain sorted by operation rather than source.

### Edits

`action.edit` takes one `lsp.TextEdit`, a list of them, or a full `lsp.WorkspaceEdit`.

An `lsp.TextEdit` has no document URI.
For the same-buffer shorthand, `publish()` targets the edit at `bufnr` and wraps it in a versioned workspace edit:

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

Both forms reach Neovim as a `CodeAction` containing a `WorkspaceEdit`, so a preview-capable picker can diff either one.
Actions that contain only an opaque `command` usually cannot be previewed.
Neovim's built-in selector applies edits but does not display a diff.

### Commands

If a fix cannot be written as a text edit, an action can carry an `lsp.Command` instead of, or alongside, an edit.
lint-actions passes the command through unchanged.
Register its client-side handler in `vim.lsp.commands` before publishing it:

```lua
vim.lsp.commands['my-tool.run'] = function(command, context)
  run(command.arguments[1], context.bufnr)
end
```

Neovim looks the name up in `vim.lsp.commands` and in the client's own command table before asking the server.
lint-actions advertises no `executeCommandProvider`, so Neovim does not execute an unregistered command and warns instead.
Prefer an edit wherever the fix can be expressed as one: edits are previewable, version-checked against the buffer, and undo as a single change.

## Providers

A provider computes actions when Neovim requests them.
This avoids the autocmds, debouncing, and invalidation needed to keep published actions in sync with the current buffer.

##### lint_actions.register({provider})

Registers a provider.
Registering the same `source` again replaces the earlier one.

- `source` is a stable name for whatever produced the actions.

- `provide` is `fun(context): items`, called synchronously on every request.
  It may return `nil` for no actions.
  Its `context` carries `bufnr`, the requested `range`, and `only` when the client filtered by kind.
  Returned items are matched the same way published ones are.

- `filetypes` is an optional list limiting the provider to those filetypes.

- `enabled` is an optional `fun(bufnr): boolean` limiting it further.

```lua
require('lint_actions').register({
  source = 'my-tool',
  filetypes = { 'lua' },
  provide = function(context)
    if not needs_fix(context.bufnr) then
      return {}
    end
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

`provide` runs while Neovim waits for the response, so it must be synchronous and quick.
A slow provider delays the menu.
Publish fixes produced by an external process instead.

Errors while running `provide` or validating, normalizing, or filtering its results are reported with `:h vim.notify()`.
That provider's entire result is skipped.
Other providers and published actions still answer the request.

Registering a provider attaches the in-process client to the ordinary file buffers it applies to (empty `buftype`), including ones already open.
Declaring `filetypes` keeps that narrow.

##### lint_actions.unregister({source})

Removes a provider.
Buffers stay attached but stop receiving actions from that source.

### Example provider

`examples/foldmarker.lua` registers a provider that adds a fold-marker modeline when the current buffer uses fold markers but does not define a modeline.
Its `enabled` callback limits the provider to matching buffers, and `provide` returns a rangeless whole-buffer action.
Copy the file into your config and call its `setup()` to use it.

## Health

Run `:checkhealth lint_actions`.
It shows the Neovim version requirement, every attached nvim-lint integration, and every registered provider.

lint-actions only receives output from linter runs, so some integration problems would otherwise be silent.
The check warns when:

- `linters_by_ft` assigns an attached linter to no filetype, so nvim-lint never runs it and no actions are published;

- nvim-lint has no linter under the attached name; or

- a linter's command is not executable.

This check does not report a missing nvim-lint installation.
`:h lint_actions.setup()` already fails immediately in that case.

<!-- panvimdoc-ignore-start -->

## Development

Install [Nix](https://nixos.org/download/) with flakes enabled, then enter the pinned development environment:

```sh
git clone https://github.com/geodimm/lint-actions.nvim
cd lint-actions.nvim
nix develop
just check
```

`just check` checks formatting, generated documentation, Luacheck, LuaLS, and the Busted tests.
Run one at a time with `just fmt`, `just docs`, `just lint`, `just typecheck`, and `just test`.
With direnv installed, `direnv allow` loads the same environment automatically.

## Contributing

Issues and pull requests are welcome.

[CONTRIBUTING.md](CONTRIBUTING.md) covers the toolchain, the test layout, the fixtures, and how the help files are generated.
[ARCHITECTURE.md](ARCHITECTURE.md) explains how the pieces fit together and how stale actions are kept out.

## License

[MIT](LICENSE).

<!-- panvimdoc-ignore-end -->
