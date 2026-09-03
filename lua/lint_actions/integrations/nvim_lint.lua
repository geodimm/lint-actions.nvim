local M = {}
local wrapped_factories = setmetatable({}, { __mode = 'k' })

---@alias LintActions.NvimLintParser fun(output: string, bufnr: integer, cwd: string): vim.Diagnostic[]

---@class LintActions.NvimLintLinter
---@field parser LintActions.NvimLintParser
---@field _lint_actions_attached? boolean

---@class LintActions.NvimLintOptions
---@field linter string|LintActions.NvimLintLinter nvim-lint linter name or concrete definition.
---@field adapter LintActions.Adapter
---@field source? string Overrides the adapter's source.

---@param linter LintActions.NvimLintLinter
---@param adapter LintActions.Adapter
---@param source string
local function attach(linter, adapter, source)
  if linter._lint_actions_attached then
    return
  end
  if type(linter.parser) ~= 'function' then
    error('lint-actions only supports nvim-lint parser functions')
  end

  linter._lint_actions_attached = true
  local parse = linter.parser
  linter.parser = function(output, bufnr, cwd)
    local diagnostics = parse(output, bufnr, cwd)

    if not vim.api.nvim_buf_is_valid(bufnr) then
      return diagnostics
    end
    if vim.bo[bufnr].modified then
      require('lint_actions').clear({ bufnr = bufnr, source = source })
      return diagnostics
    end

    local ok, err = pcall(require('lint_actions').ingest, {
      adapter = adapter,
      source = source,
      output = output,
      bufnr = bufnr,
      cwd = cwd,
      diagnostics = diagnostics,
    })
    if not ok then
      vim.schedule(function()
        vim.notify('lint-actions: ' .. err, vim.log.levels.ERROR)
      end)
    end
    return diagnostics
  end
end

---Wrap an nvim-lint parser and publish fixes from the same process output.
---The parser's diagnostics and return value are preserved.
---@param options LintActions.NvimLintOptions
function M.attach(options)
  vim.validate('options', options, 'table')
  vim.validate('options.adapter', options.adapter, 'table')
  vim.validate('options.adapter.parse', options.adapter.parse, 'function')
  vim.validate('source', options.source or options.adapter.source, 'string')

  local source = options.source or options.adapter.source
  local linter_option = options.linter
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
        attach(definition, options.adapter, source)
        return definition
      end
      wrapped_factories[factory] = true
      lint.linters[linter_option] = factory
    elseif type(linter) == 'table' then
      attach(linter, options.adapter, source)
    else
      error(('unknown nvim-lint linter: %s'):format(linter_option))
    end
  elseif type(linter_option) == 'table' then
    attach(linter_option, options.adapter, source)
  else
    error('options.linter must be a linter name or table')
  end
end

return M
