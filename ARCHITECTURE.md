# Architecture

`lint-actions.nvim` connects fix producers to Neovim's existing LSP code-action UI.
It makes structured fixes available to tools that already understand LSP code actions.
It does not run linters or provide a picker for code actions.

```mermaid
flowchart LR
    A["Linter or producer"] -->|raw output| B["Adapter"]
    A -->|normalized actions| C["publish()"]
    B -->|normalized actions| C
    C --> D["Versioned action store"]
    E["Neovim LSP UI<br/>built-in, fzf-lua, Telescope"] -->|textDocument/codeAction| F["In-process LSP transport"]
    F -->|buffer, range, kind| D
    D -->|fresh CodeActions| F
    F -->|WorkspaceEdits| E
```

## Publishing

A producer can call `publish()` directly with normalized actions.
Tool-specific adapters handle formats such as golangci-lint and markdownlint
JSON, while integrations capture output another plugin already produced.
The [nvim-lint](https://github.com/mfussenegger/nvim-lint) integration wraps its parser and never launches a second process.

### Parser interposition

nvim-lint owns process execution and diagnostic publication, while each
linter definition owns output interpretation through its `parser` function.
The integration calls that parser first, passes both its diagnostics and the
same raw output to the selected adapter, then returns the diagnostics to
nvim-lint unchanged.

This also supports richer output formats than a bundled linter definition
uses by default. The producer must switch the command arguments and parser as
one operation: for example, a `--json` argument must be paired with a JSON
parser returning `vim.Diagnostic[]`. The adapter can then consume the JSON for
fix metadata without disrupting nvim-lint's normal diagnostic flow.

For same-buffer fixes, producers may put one `TextEdit` or a list of text edits in an action's `edit` field.
Publication wraps that shorthand in a versioned `WorkspaceEdit`, which is the type required by the LSP `CodeAction` protocol.
Producers can instead supply a full `WorkspaceEdit` for multi-document changes or resource operations.

Actions are stored by buffer and source.
Republishing replaces only that source, so several producers can coexist without coordinating with each other.

## Serving actions

The first non-empty publication starts a small in-process LSP client.
The same client is reused and attached only to buffers that publish actions.
When Neovim requests `textDocument/codeAction`, the transport asks the store for actions matching the buffer, requested range, and optional action-kind filter.

The response contains ordinary `CodeAction` objects.
Neovim and third-party pickers therefore handle selection, preview, and application through their normal LSP paths.

## Stale-edit protection

Each publication records both the buffer changed tick and its current LSP document version.
A batch is discarded when either value no longer matches.

Edits for the current buffer are returned as versioned `documentChanges`.
This second check matters when the buffer changes after the action picker opens: Neovim rejects the selected edit instead of applying old offsets to new content.
