local M = {}

---@class LintActions.NvimLintOptions
---@field linter table nvim-lint linter definition with a function parser.
---@field adapter LintActions.Adapter
---@field source? string Overrides the adapter's source.

---Wrap an nvim-lint parser and publish fixes from the same process output.
---The parser's diagnostics and return value are preserved.
---@param options LintActions.NvimLintOptions
function M.attach(options)
  vim.validate('options', options, 'table')
  vim.validate('options.linter', options.linter, 'table')
  vim.validate('options.adapter', options.adapter, 'table')
  vim.validate('options.adapter.parse', options.adapter.parse, 'function')
  vim.validate('source', options.source or options.adapter.source, 'string')

  local linter = options.linter
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
    local source = options.source or options.adapter.source

    if not vim.api.nvim_buf_is_valid(bufnr) then
      return diagnostics
    end
    if vim.bo[bufnr].modified then
      require('lint_actions').clear({ bufnr = bufnr, source = source })
      return diagnostics
    end

    local ok, err = pcall(require('lint_actions').ingest, {
      adapter = options.adapter,
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

return M
