# `lint-actions.nvim` plan

## GitHub repository

Suggested repository name: `lint-actions.nvim`

Suggested description:

> Turn structured linter fixes into native Neovim LSP code actions, with previews, stale-edit protection, and optional nvim-lint adapters.

Suggested topics: `neovim`, `lua`, `lsp`, `code-actions`, `linting`, `nvim-lint`, `golangci-lint`

## Goal

Build a small, dependency-free Neovim plugin that turns fixes produced by linters and other tools into ordinary LSP code actions. The actions should work with `vim.lsp.buf.code_action()`, fzf-lua, Telescope, and any other standard LSP UI without wrapping or replacing those entry points.

The initial motivating integration is golangci-lint's JSON `SuggestedFixes`, but the core must not know anything about Go or golangci-lint.

## Design principles

- Use Neovim's native in-process LSP support through a Lua `cmd` function and `vim.lsp.rpc.PublicClient`.
- Return real `lsp.CodeAction` objects with `WorkspaceEdit`s, not opaque commands, so previews work normally.
- Keep the core independent of none-ls, nvim-lint, particular pickers, and external executables.
- Do not run linters in the core. Producers run tools; this plugin publishes their fixes.
- Make integrations and tool-specific adapters optional modules.
- Reject stale edits instead of applying offsets to content that has changed.
- Prefer standard LSP types at the public boundary whenever practical.

## Architecture

```text
linters / plugins / user callbacks
              │
              ▼
       adapter or publish()
              │
              ▼
       versioned action store
              │
              ▼
 tiny in-process LSP transport
              │
              ▼
vim.lsp.buf.code_action / fzf-lua / Telescope
```

The plugin has four layers:

1. **Transport** implements the minimal in-process LSP server.
2. **Store** owns actions by buffer, producer, and document version.
3. **Adapters** translate a tool's output into normalized actions.
4. **Integrations** capture output from another plugin and feed an adapter.

## Public API

### Publish normalized actions

This is the lowest-level, generic API. An item contains the range where it is applicable and the standard LSP action returned to clients.

```lua
local actions = require('lint-actions')

actions.setup()

actions.publish({
  bufnr = bufnr,
  source = 'my-tool',
  items = {
    {
      range = diagnostic_range,
      action = {
        title = 'Replace deprecated call',
        kind = 'quickfix',
        edit = workspace_edit,
      },
    },
  },
})

actions.clear({
  bufnr = bufnr,
  source = 'my-tool',
})
```

`publish()` should:

- associate the batch with the current changed tick / LSP document version;
- lazily attach the in-process client to the buffer;
- replace the previous batch from the same source;
- accept an empty `items` list as a successful clear;
- validate enough of the shape to produce useful errors for adapter authors.

### Ingest tool output through an adapter

Raw JSON is not generic because every tool has a different schema. `ingest()` is generic because the caller supplies the schema adapter.

```lua
actions.ingest({
  adapter = require('lint-actions.adapters.golangci'),
  output = raw_json,
  bufnr = bufnr,
  cwd = cwd,
  diagnostics = diagnostics,
})
```

Initial adapter contract:

```lua
---@class LintActionsAdapterContext
---@field output string
---@field bufnr integer
---@field cwd string
---@field diagnostics? vim.Diagnostic[]

---@param ctx LintActionsAdapterContext
---@return LintActionItem[]
function adapter.parse(ctx)
end
```

The API should accept an adapter module/table directly. A global adapter registry and string names can be added later only if they improve real configurations.

### Optional nvim-lint integration

```lua
require('lint-actions.integrations.nvim-lint').attach({
  linter = require('lint').linters.golangcilint,
  adapter = require('lint-actions.adapters.golangci'),
})
```

The integration wraps the existing parser, preserving its return value and diagnostic behavior. After parsing, it passes the same raw output, buffer, working directory, and parsed diagnostics to the adapter.

It must:

- never launch a second linter process;
- remain optional, with nvim-lint required only when this module is used;
- support ordinary parser functions first;
- either support nvim-lint's streaming parser objects or fail with a clear message until that support is implemented;
- avoid wrapping the same linter more than once.

## In-process LSP transport

Use `vim.lsp.start()` with `cmd` set to a Lua function returning a `vim.lsp.rpc.PublicClient`.

The first version only needs:

- `initialize`: advertise `codeActionProvider` and the chosen position encoding;
- `textDocument/codeAction`: return matching, non-stale actions from the store;
- `shutdown`: acknowledge shutdown;
- `exit`: call `dispatchers.on_exit()`;
- `is_closing` and `terminate`: satisfy the public client contract.

No `workspace/executeCommand` support is needed for ordinary fixes. Neovim applies the returned `WorkspaceEdit` itself.

Start one reusable client and attach it lazily when a producer first publishes actions for a buffer. Do not attach it to every buffer during startup.

The request handler should:

- resolve the buffer from `params.textDocument.uri`;
- discard batches whose changed tick or version is stale;
- filter items to the requested range;
- honor `params.context.only` using hierarchical code-action kinds;
- return direct actions with edits intact;
- return an empty list when no action matches.

## Internal data model

Tentative normalized item:

```lua
---@class LintActionItem
---@field range lsp.Range                Where the action should be offered
---@field action lsp.CodeAction          The action returned to the client

---@class LintActionBatch
---@field bufnr integer
---@field uri string
---@field source string                  Stable producer identifier
---@field changedtick integer
---@field version integer
---@field items LintActionItem[]
```

Store batches as `buffer -> source -> batch`. Multiple producers can coexist without overwriting each other. Clear buffer state on `BufWipeout` and detach/stop cleanly on shutdown.

Before returning an action, ensure its edits use a versioned `documentChanges` entry. This lets Neovim reject an edit if the buffer changes while the action picker is open.

## Golangci-lint adapter

The first bundled adapter parses golangci-lint v2 JSON and:

- reads `Issues[*].SuggestedFixes`;
- filters issues to the current buffer while accepting absolute and cwd-relative filenames;
- uses the issue position and/or matching diagnostic as the action's applicability range;
- decodes `TextEdits[*].NewText` from base64 because golangci-lint serializes Go `[]byte` values that way;
- treats `TextEdits[*].Pos` and `End` as zero-based byte offsets;
- converts byte offsets to the position encoding advertised by the in-process server;
- supports multiple text edits in one suggested fix;
- emits one quick-fix action per suggested fix;
- uses the suggested-fix message as the title, falling back to the issue message;
- includes the originating linter in the title or diagnostic metadata.

Only issues containing `SuggestedFixes` become actions. Other issues remain diagnostics owned by the producer, such as nvim-lint.

## Proposed repository layout

```text
lint-actions.nvim/
├── LICENSE
├── README.md
├── doc/
│   └── lint-actions.txt
├── lua/
│   └── lint-actions/
│       ├── init.lua
│       ├── server.lua
│       ├── store.lua
│       ├── offsets.lua
│       ├── adapters/
│       │   └── golangci.lua
│       └── integrations/
│           └── nvim-lint.lua
└── tests/
    ├── minimal_init.lua
    ├── server_spec.lua
    ├── store_spec.lua
    ├── offsets_spec.lua
    ├── golangci_spec.lua
    ├── nvim_lint_spec.lua
    └── fixtures/
```

Use `lint_actions` instead of `lint-actions` for Lua module names if hyphens make LuaLS annotations, test tooling, or require paths awkward. Decide this while scaffolding and use one spelling consistently.

## Implementation phases

### Phase 1: dependency-free core

- Scaffold the plugin and test harness.
- Implement the action store.
- Implement the minimal `PublicClient` transport.
- Add lazy client attachment and buffer cleanup.
- Add `setup()`, `publish()`, and `clear()`.
- Prove actions appear through `vim.lsp.buf.code_action()` and include previewable edits.

### Phase 2: golangci-lint adapter

- Move the proven JSON parsing and offset conversion out of the dotfiles prototype.
- Add fixtures for real golangci-lint v2 output.
- Support multiple suggested fixes and multiple edits.
- Test absolute and relative paths, Unicode, empty output, malformed JSON, and missing fields.

### Phase 3: nvim-lint integration

- Extract parser wrapping into the optional integration.
- Preserve diagnostics exactly.
- Publish actions without starting another process.
- Document setup for overriding/configuring the golangci-lint linter.

### Phase 4: migrate the dotfiles

- Add the new repository to `vim.pack`.
- Replace `utils/golangci.lua` and the none-ls source with the plugin configuration.
- Remove none-ls again if it has no other active sources.
- Keep gopls as the owner of interactive `modernize` findings.
- Keep golangci-lint's `modernize` disabled only in the nvim-lint editor invocation to avoid duplicate diagnostics.
- Re-run the playground integration test.

### Phase 5: documentation and release

- Write a concise README with generic, golangci-lint, and nvim-lint examples.
- Add Vim help.
- Document the minimum supported Neovim version.
- Add CI for formatting, Lua diagnostics if practical, and headless tests.
- Tag `v0.1.0` after the public API survives the dotfiles migration.

## Test matrix

Core behavior:

- actions are returned only for the requested buffer and range;
- normal and visual-range requests work;
- `context.only = { 'quickfix' }` is honored;
- multiple sources coexist;
- republishing replaces only that source;
- clearing and wiping a buffer removes its actions;
- actions expose direct `WorkspaceEdit`s and therefore support picker previews;
- actions published for an older changed tick/version are not returned or applied.

Offset and edit handling:

- beginning and end of file;
- zero-based offsets;
- ASCII and multibyte UTF-8 before the edited span;
- UTF-16 character conversion;
- LF and CRLF input;
- one fix containing multiple edits;
- edits touching multiple files if/when supported.

Integration behavior:

- the original nvim-lint diagnostics are unchanged;
- only one golangci-lint process runs;
- malformed/empty JSON does not break diagnostics;
- diagnostics without `SuggestedFixes` create no action;
- the real `404` fixture becomes exactly `http.StatusNotFound`;
- the real errorlint fixture changes `%v` to `%w` exactly once.

## Non-goals for `v0.1`

- Running or scheduling external linters.
- Replacing nvim-lint diagnostics.
- Formatting, hover, completion, or other none-ls features.
- A picker or custom code-action UI.
- Tool installation or Mason integration.
- A declarative framework for every possible JSON schema.
- Automatic fix-all unless the producer explicitly supplies a safe `source.fixAll` action.

## Open decisions

- Minimum Neovim version: prefer the oldest version that supports the required in-process client contract cleanly, but optimize for current stable Neovim rather than compatibility shims.
- Module spelling: `lint-actions` versus `lint_actions`.
- Whether `publish()` should require complete `WorkspaceEdit`s or also offer helpers for single-buffer `TextEdit`s.
- Whether actions should copy related diagnostics into `CodeAction.diagnostics`.
- Whether multi-file fixes belong in `v0.1` or immediately after it.
- Final license; MIT is the conventional default for this kind of plugin.

## Existing prototype to extract

The dotfiles currently contain the working experiment:

- `nvim/lua/utils/golangci.lua` preserves and converts golangci-lint fixes;
- `nvim/lua/plugins/none-ls.lua` exposes them through none-ls;
- `nvim/lua/plugins/nvim-lint.lua` installs the parser integration;
- `../repos/wip/golangci-modernize-playground` is the end-to-end fixture project.

The prototype has already established two important facts:

1. Golangci-lint JSON offsets are zero-based bytes, not one-based token positions.
2. Returning a direct, versioned `WorkspaceEdit` is necessary for correct fzf-lua previews and stale-edit protection.

Keep the none-ls version working until the standalone transport passes the same real-output integration test, then migrate rather than rewriting both sides simultaneously.
