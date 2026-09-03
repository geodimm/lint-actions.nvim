local adapter = require('lint_actions.adapters.markdownlint')
local nvim_lint = require('lint_actions.integrations.nvim_lint')

local M = {}
local wrapped_factories = setmetatable({}, { __mode = 'k' })

---@class LintActions.MarkdownlintLinter : LintActions.NvimLintLinter
---@field _lint_actions_markdownlint_attached? boolean

---@class LintActions.MarkdownlintOptions
---@field linter? string|LintActions.MarkdownlintLinter Defaults to `markdownlint`.
---@field source? string Overrides the adapter's source.

---@param linter LintActions.MarkdownlintLinter
---@param source string
local function configure(linter, source)
  if linter._lint_actions_markdownlint_attached then
    return
  end
  if linter._lint_actions_attached then
    error('attach the markdownlint integration before attaching this linter through nvim_lint')
  end
  if linter.args ~= nil and type(linter.args) ~= 'table' then
    error('markdownlint linter args must be a table')
  end

  linter._lint_actions_markdownlint_attached = true
  linter.args = linter.args or {}
  if not vim.tbl_contains(linter.args, '--json') then
    table.insert(linter.args, '--json')
  end
  linter.parser = adapter.diagnostics
  nvim_lint.attach({ linter = linter, adapter = adapter, source = source })
end

---Configure markdownlint for JSON output and publish fixes from that output.
---Calling this function more than once is safe.
---@param options? LintActions.MarkdownlintOptions
function M.attach(options)
  if options == nil then
    options = {}
  end
  vim.validate('options', options, 'table')

  local source = options.source
  if source == nil then
    source = adapter.source
  end
  vim.validate('source', source, 'string')
  local linter_option = options.linter
  if linter_option == nil then
    linter_option = 'markdownlint'
  end
  if type(linter_option) == 'string' then
    local lint = require('lint')
    local linter = lint.linters[linter_option]
    if type(linter) == 'function' then
      if wrapped_factories[linter] then
        return
      end
      local factory = function()
        local definition = linter()
        vim.validate('linter definition', definition, 'table')
        configure(definition, source)
        return definition
      end
      wrapped_factories[factory] = true
      lint.linters[linter_option] = factory
    elseif type(linter) == 'table' then
      configure(linter, source)
    else
      error(('unknown nvim-lint linter: %s'):format(linter_option))
    end
  elseif type(linter_option) == 'table' then
    configure(linter_option, source)
  else
    error('options.linter must be a linter name or table')
  end
end

return M
