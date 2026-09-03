---@alias LintActions.Edit lsp.TextEdit|lsp.TextEdit[]|lsp.WorkspaceEdit

---@class LintActions.NvimLintIntegrationOptions
---@field golangci? boolean|LintActions.GolangciOptions Enable with defaults using `true`, or pass integration options.
---@field markdownlint? boolean|LintActions.MarkdownlintOptions Enable with defaults using `true`, or pass integration options.

---@class LintActions.IntegrationsOptions
---@field nvim_lint? false|LintActions.NvimLintIntegrationOptions Tools whose nvim-lint output should provide actions.

---@class LintActions.SetupOptions
---@field integrations? LintActions.IntegrationsOptions Bundled integrations to attach after their dependencies are configured.

---@class LintActions.CodeAction : lsp.CodeAction
---@field edit? LintActions.Edit A TextEdit or list targets the published buffer; a WorkspaceEdit may target multiple resources.

---@class LintActions.Item
---@field range lsp.Range Range in which the action is offered.
---@field action LintActions.CodeAction Action returned to the LSP client.

---@class LintActions.PublishOptions
---@field bufnr integer
---@field source string Stable identifier for the action producer.
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
---@field items LintActions.Item[]

return {}
