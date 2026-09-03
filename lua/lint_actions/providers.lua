local items = require('lint_actions.items')

local M = {}

---@type table<string, LintActions.Provider>
local providers = {}
local group

---@param source string
---@param err string
local function report(source, err)
  vim.schedule(function()
    vim.notify(('lint-actions: provider %s: %s'):format(source, err), vim.log.levels.ERROR)
  end)
end

---A provider serves ordinary file buffers. Anything else is left alone so the
---client is not attached to scratch, terminal, or plugin buffers.
---@param bufnr integer
---@return boolean
local function eligible(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype == ''
end

---@param provider LintActions.Provider
---@param bufnr integer
---@return boolean
local function applies(provider, bufnr)
  if provider.filetypes and not vim.tbl_contains(provider.filetypes, vim.bo[bufnr].filetype) then
    return false
  end
  if not provider.enabled then
    return true
  end

  local ok, enabled = pcall(provider.enabled, bufnr)
  if not ok then
    report(provider.source, tostring(enabled))
    return false
  end
  return enabled and true or false
end

---Run one provider, keeping its failures out of the rest of the request.
---@param provider LintActions.Provider
---@param context LintActions.ProviderContext
---@return LintActions.NormalizedItem[]? items
---@return string? err
local function collect(provider, context)
  local ok, produced = pcall(provider.provide, context)
  if not ok then
    return nil, tostring(produced)
  end

  ---@type LintActions.Item[]
  local candidates = produced or {}
  local valid, invalid = pcall(items.validate, candidates)
  if not valid then
    return nil, tostring(invalid)
  end
  return items.normalize(candidates, context.bufnr)
end

---@param bufnr integer
local function attach(bufnr)
  if not eligible(bufnr) then
    return
  end
  for _, provider in pairs(providers) do
    if applies(provider, bufnr) then
      require('lint_actions.server').attach(bufnr)
      return
    end
  end
end

---Replace the provider registered under a source.
---@param provider LintActions.Provider
function M.register(provider)
  providers[provider.source] = provider

  if not group then
    group = vim.api.nvim_create_augroup('lint_actions_providers', { clear = true })
    vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile', 'FileType' }, {
      group = group,
      desc = 'attach lint-actions to buffers a provider serves',
      callback = function(event)
        attach(event.buf)
      end,
    })
  end

  -- Registration usually happens after startup, so buffers that are already
  -- open would otherwise never see the client.
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    attach(bufnr)
  end
end

---@param source string
function M.unregister(source)
  providers[source] = nil
end

---Ask every applicable provider for actions matching a request.
---@param bufnr integer
---@param range lsp.Range
---@param only? lsp.CodeActionKind[]
---@return lsp.CodeAction[]
function M.actions(bufnr, range, only)
  local actions = {}
  if not eligible(bufnr) then
    return actions
  end

  local sources = vim.tbl_keys(providers)
  table.sort(sources)

  for _, source in ipairs(sources) do
    local provider = providers[source]
    if applies(provider, bufnr) then
      local produced, err = collect(provider, { bufnr = bufnr, range = range, only = only })
      if not produced then
        report(source, err or 'provider failed')
      else
        for _, item in ipairs(produced) do
          if items.matches(item, range, only) then
            table.insert(actions, item.action)
          end
        end
      end
    end
  end

  return actions
end

---Reset all state. Intended for tests.
function M._reset()
  providers = {}
end

return M
