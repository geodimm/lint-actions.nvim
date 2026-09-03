local adapter = require('lint_actions.adapters.golangci')
local items = require('lint_actions.items')
local nvim_lint = require('lint_actions.integrations.nvim_lint')

local M = {}

---@class LintActions.GolangciOptions
---@field linter? string|LintActions.NvimLintLinter Defaults to `golangcilint`.
---@field source? string Overrides the adapter's source.

---Publish golangci-lint SuggestedFixes from nvim-lint's existing output.
---Calling this function more than once is safe.
---@param options? LintActions.GolangciOptions
function M.attach(options)
  if options == nil then
    options = {}
  end
  items.expect(options, 'table', 'options')

  local linter = options.linter
  if linter == nil then
    linter = 'golangcilint'
  end
  local source = options.source
  if source == nil then
    source = adapter.source
  end

  return nvim_lint.attach({
    linter = linter,
    adapter = adapter,
    source = source,
  })
end

return M
