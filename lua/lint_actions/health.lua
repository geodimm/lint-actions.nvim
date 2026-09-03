local M = {}

---A linter nvim-lint never runs produces no actions, and nothing else reports
---it, so resolve what the attached name actually maps to.
---@param name string
---@return string[] filetypes
---@return LintActions.NvimLintEntry? definition
local function resolve(name)
  local ok, lint = pcall(require, 'lint')
  if not ok or type(lint) ~= 'table' then
    return {}, nil
  end

  local filetypes = {}
  for filetype, linters in pairs(lint.linters_by_ft or {}) do
    if type(linters) == 'table' and vim.tbl_contains(linters, name) then
      table.insert(filetypes, filetype)
    end
  end
  table.sort(filetypes)
  return filetypes, (lint.linters or {})[name]
end

---@param attachment LintActions.NvimLintAttachment
local function check_attachment(attachment)
  local label = ('%s publishes as %s'):format(attachment.linter or 'a linter definition', attachment.source)
  if not attachment.linter then
    vim.health.ok(label)
    return
  end

  local filetypes, definition = resolve(attachment.linter)
  if definition == nil then
    vim.health.warn(label, ('nvim-lint has no linter named %s'):format(attachment.linter))
    return
  end

  if #filetypes == 0 then
    vim.health.warn(
      label,
      ('%s is in no linters_by_ft entry, so nvim-lint never runs it and no actions are published'):format(
        attachment.linter
      )
    )
  else
    vim.health.ok(('%s, on %s'):format(label, table.concat(filetypes, ', ')))
  end

  -- Factories are resolved per run, so only a concrete definition has a
  -- command to look for here.
  local command = type(definition) == 'table' and definition.cmd or nil
  if type(command) == 'string' and vim.fn.executable(command) ~= 1 then
    vim.health.warn(('%s is not executable'):format(command), 'nvim-lint cannot run the linter without it')
  end
end

function M.check()
  vim.health.start('lint-actions.nvim')

  if vim.fn.has('nvim-0.11') == 1 then
    vim.health.ok('Neovim 0.11 or newer')
  else
    vim.health.error('Neovim 0.11 or newer is required')
  end

  vim.health.start('lint-actions.nvim: nvim-lint integrations')
  local attachments = require('lint_actions.integrations.nvim_lint').attachments()
  if #attachments == 0 then
    vim.health.info('No nvim-lint integration is attached')
  end
  for _, attachment in ipairs(attachments) do
    check_attachment(attachment)
  end

  vim.health.start('lint-actions.nvim: providers')
  local sources = require('lint_actions.providers').sources()
  if #sources == 0 then
    vim.health.info('No provider is registered')
  end
  for _, source in ipairs(sources) do
    vim.health.ok(('%s is registered'):format(source))
  end
end

return M
