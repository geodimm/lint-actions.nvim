local adapter = require('lint_actions.adapters.markdownlint')
local items = require('lint_actions.items')
local nvim_lint = require('lint_actions.integrations.nvim_lint')

local M = {}

---@class LintActions.MarkdownlintOptions
---@field linter? string|LintActions.NvimLintLinter Defaults to `markdownlint`.
---@field source? string Overrides the adapter's source.

---markdownlint only reports fix metadata in its JSON output, so the linter has
---to run with `--json` and parse it before its output is worth adapting.
---@param linter LintActions.NvimLintLinter
local function configure(linter)
  if linter.args ~= nil and type(linter.args) ~= 'table' then
    error('markdownlint linter args must be a table')
  end

  linter.args = linter.args or {}
  if not vim.tbl_contains(linter.args, '--json') then
    table.insert(linter.args, '--json')
  end
  linter.parser = adapter.diagnostics
end

---Configure markdownlint for JSON output and publish fixes from that output.
---Calling this function more than once is safe.
---@param options? LintActions.MarkdownlintOptions
function M.attach(options)
  if options == nil then
    options = {}
  end
  items.expect(options, 'table', 'options')

  local linter = options.linter
  if linter == nil then
    linter = 'markdownlint'
  end
  local source = options.source
  if source == nil then
    source = adapter.source
  end

  return nvim_lint.attach({
    linter = linter,
    adapter = adapter,
    source = source,
    configure = configure,
  })
end

return M
