local items = require('lint_actions.items')

local M = {}
local wrapped_factories = setmetatable({}, { __mode = 'k' })
local wrapped_runners = setmetatable({}, { __mode = 'k' })
local parser_factories = setmetatable({}, { __mode = 'k' })
---@type table<string, LintActions.NvimLintAttachment>
local attachments = {}

---@alias LintActions.NvimLintParser fun(output: string, bufnr: integer, cwd: string): vim.Diagnostic[]

---@class LintActions.NvimLintLinter
---@field parser LintActions.NvimLintParser
---@field cmd? string|fun(): string
---@field args? (string|fun(): string)[]
---@field _lint_actions_attached? string Source that wrapped this linter.

---@alias LintActions.NvimLintConfigure fun(linter: LintActions.NvimLintLinter)

---How nvim-lint stores a linter: a definition, or a factory rebuilt per run.
---@alias LintActions.NvimLintEntry LintActions.NvimLintLinter|(fun(): LintActions.NvimLintLinter)

---@class LintActions.NvimLintAttachment
---@field source string Source the wrapped linter publishes under.
---@field linter? string nvim-lint linter name, absent when a definition was passed directly.

---@class LintActions.NvimLintOptions
---@field linter string|LintActions.NvimLintLinter nvim-lint linter name or concrete definition.
---@field adapter LintActions.Adapter
---@field source? string Overrides the adapter's source.
---@field configure? LintActions.NvimLintConfigure Prepares the resolved linter before its parser is wrapped.

---@class LintActions.NvimLintRun
---@field bufnr integer
---@field changedtick integer
---@field process? { cancelled: boolean }

---Bind the snapshot to the process's parser, not the shared linter definition.
---nvim-lint calls `lint()` for both concrete definitions and resolved factories.
local function guard_runs()
  local lint = require('lint')
  if wrapped_runners[lint.lint] then
    return
  end
  local execute = lint.lint
  local function guarded(linter, options)
    local factory = parser_factories[linter.parser]
    if not factory then
      return execute(linter, options)
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local run = { bufnr = bufnr, changedtick = vim.api.nvim_buf_get_changedtick(bufnr) }
    local definition = vim.tbl_extend('force', linter, { parser = factory(run) })
    run.process = execute(definition, options)
    return run.process
  end
  wrapped_runners[guarded] = true
  lint.lint = guarded
end

---@param parse LintActions.NvimLintParser
---@param adapter LintActions.Adapter
---@param source string
---@param run? LintActions.NvimLintRun
---@return LintActions.NvimLintParser
local function wrap_parser(parse, adapter, source, run)
  return function(output, bufnr, cwd)
    local diagnostics = parse(output, bufnr, cwd)

    if not vim.api.nvim_buf_is_valid(bufnr) then
      return diagnostics
    end
    if run then
      if
        bufnr ~= run.bufnr
        or vim.api.nvim_buf_get_changedtick(bufnr) ~= run.changedtick
        or (run.process and run.process.cancelled)
      then
        -- A newer run may already have published fresh actions. Leave them alone.
        return diagnostics
      end
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

---@param linter LintActions.NvimLintLinter
---@param adapter LintActions.Adapter
---@param source string
---@param configure? LintActions.NvimLintConfigure
local function attach(linter, adapter, source, configure)
  if linter._lint_actions_attached then
    -- The linter's arguments and parser are already wrapped, so a late
    -- configure step could no longer take effect on the running command.
    if configure and linter._lint_actions_attached ~= source then
      error('attach the ' .. source .. ' integration before attaching this linter through nvim_lint')
    end
    return
  end
  if configure then
    configure(linter)
  end
  if type(linter.parser) ~= 'function' then
    error('lint-actions only supports nvim-lint parser functions')
  end

  linter._lint_actions_attached = source
  local parse = linter.parser
  linter.parser = wrap_parser(parse, adapter, source)
  parser_factories[linter.parser] = function(run)
    return wrap_parser(parse, adapter, source, run)
  end
end

---Wrap an nvim-lint parser and publish fixes from the same process output.
---The parser's diagnostics and return value are preserved.
---@param options LintActions.NvimLintOptions
function M.attach(options)
  items.expect(options, 'table', 'options')
  items.expect(options.adapter, 'table', 'options.adapter')
  items.expect(options.adapter.parse, 'function', 'options.adapter.parse')
  if options.configure ~= nil then
    items.expect(options.configure, 'function', 'options.configure')
  end

  local source = options.source
  if source == nil then
    source = options.adapter.source
  end
  items.expect(source, 'string', 'source')
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
        items.expect(definition, 'table', 'linter definition', 0)
        attach(definition, options.adapter, source, options.configure)
        return definition
      end
      wrapped_factories[factory] = true
      lint.linters[linter_option] = factory
    elseif type(linter) == 'table' then
      attach(linter, options.adapter, source, options.configure)
    else
      error(('unknown nvim-lint linter: %s'):format(linter_option))
    end
  elseif type(linter_option) == 'table' then
    attach(linter_option, options.adapter, source, options.configure)
  else
    error('options.linter must be a linter name or table')
  end

  guard_runs()
  local name = type(linter_option) == 'string' and linter_option or nil
  attachments[source .. '\0' .. (name or '')] = { source = source, linter = name }
end

---Report what has been attached, for `:checkhealth`.
---@return LintActions.NvimLintAttachment[]
function M.attachments()
  local list = vim.tbl_values(attachments)
  table.sort(list, function(left, right)
    return left.source < right.source
  end)
  return vim.deepcopy(list)
end

---Reset all state. Intended for tests.
function M._reset()
  attachments = {}
end

return M
