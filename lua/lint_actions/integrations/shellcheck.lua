local adapter = require('lint_actions.adapters.shellcheck')
local items = require('lint_actions.items')
local nvim_lint = require('lint_actions.integrations.nvim_lint')

local M = {}

---@class LintActions.ShellcheckOptions
---@field linter? string|LintActions.NvimLintLinter Defaults to `shellcheck`.
---@field source? string Overrides the adapter's source.

---Publish shellcheck fix replacements from nvim-lint's existing output.
---Calling this function more than once is safe.
---@param options? LintActions.ShellcheckOptions
function M.attach(options)
  if options == nil then
    options = {}
  end
  items.expect(options, 'table', 'options')

  local linter = options.linter
  if linter == nil then
    linter = 'shellcheck'
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
