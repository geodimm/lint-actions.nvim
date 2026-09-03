---@alias LintActions.Edit lsp.TextEdit|lsp.TextEdit[]|lsp.WorkspaceEdit

---@class LintActions.Position
---@field line integer Zero-based line.
---@field character? integer Accepted for protocol shape; matching is line-granular.

---@class LintActions.Range
---@field start LintActions.Position
---@field end LintActions.Position

---@class LintActions.NvimLintIntegrationOptions
---@field golangci? boolean|LintActions.GolangciOptions Enable with defaults using `true`, or pass integration options.
---@field markdownlint? boolean|LintActions.MarkdownlintOptions Enable with defaults using `true`, or pass integration options.
---@field shellcheck? boolean|LintActions.ShellcheckOptions Enable with defaults using `true`, or pass integration options.

---@class LintActions.IntegrationsOptions
---@field nvim_lint? false|LintActions.NvimLintIntegrationOptions Tools whose nvim-lint output should provide actions.

---@class LintActions.SetupOptions
---@field integrations? LintActions.IntegrationsOptions Bundled integrations to attach after their dependencies are configured.

---@class LintActions.CodeAction : lsp.CodeAction
---@field edit? LintActions.Edit A TextEdit or list targets the published buffer; a WorkspaceEdit may target multiple resources.

---@class LintActions.Item
---@field range? LintActions.Range Lines on which the action is offered. Omit for the whole buffer.
---@field action LintActions.CodeAction Action returned to the LSP client.

---@class LintActions.NormalizedItem
---@field range lsp.Range Range filled in by `normalize()`.
---@field action lsp.CodeAction Action with its edit already versioned.

---@class LintActions.ProviderContext
---@field bufnr integer Buffer the request is for.
---@field range lsp.Range Range Neovim asked about.
---@field only? lsp.CodeActionKind[] Requested kinds, when the client filtered.

---@class LintActions.Provider
---@field source string Stable identifier for whatever produced the actions. Replacement key, not shown in the picker.
---@field provide fun(context: LintActions.ProviderContext): LintActions.Item[]? Called synchronously per request.
---@field filetypes? string[] Restrict the provider to these filetypes.
---@field enabled? fun(bufnr: integer): boolean Further restrict the provider per buffer.

---@class LintActions.PublishOptions
---@field bufnr integer
---@field source string Stable identifier for whatever produced the actions. Replacement key, not shown in the picker.
---@field items LintActions.Item[]

---@class LintActions.ClearOptions
---@field bufnr integer
---@field source? string Omit to clear every source for the buffer.

---@class LintActions.AdapterContext
---@field output string
---@field bufnr integer
---@field cwd string
---@field diagnostics? vim.Diagnostic[]

---@class LintActions.Adapter
---@field source string
---@field parse fun(context: LintActions.AdapterContext): LintActions.Item[]

---@class LintActions.IngestOptions : LintActions.AdapterContext
---@field adapter LintActions.Adapter
---@field source? string Overrides the adapter's source.

---@class LintActions.Batch
---@field bufnr integer
---@field uri string
---@field source string
---@field changedtick integer
---@field version integer
---@field items LintActions.NormalizedItem[]

return {}
