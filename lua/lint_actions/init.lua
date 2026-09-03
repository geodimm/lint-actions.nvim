local items = require('lint_actions.items')

local M = {}

local configured = false
local integration_modules = {
  nvim_lint = {
    golangci = 'lint_actions.integrations.golangci',
    markdownlint = 'lint_actions.integrations.markdownlint',
    shellcheck = 'lint_actions.integrations.shellcheck',
  },
}

---@param integrations table<string, boolean|table>
local function validate_integrations(integrations)
  items.expect(integrations, 'table', 'options.integrations')

  for integration, tools in pairs(integrations) do
    local modules = integration_modules[integration]
    if not modules then
      error(('unknown integration: %s'):format(integration), 3)
    end
    if tools ~= false then
      if type(tools) ~= 'table' then
        error(('options.integrations.%s must be table, got %s'):format(integration, type(tools)), 3)
      end
      for tool, options in pairs(tools) do
        if not modules[tool] then
          error(('unknown %s integration: %s'):format(integration, tool), 3)
        end
        if options ~= false then
          if options ~= true and type(options) ~= 'table' then
            error(
              ('options.integrations.%s.%s must be boolean or table, got %s'):format(integration, tool, type(options)),
              3
            )
          end
        end
      end
    end
  end
end

---@param integrations table<string, boolean|table>
local function attach_integrations(integrations)
  for integration, tools in pairs(integrations) do
    if tools ~= false then
      ---@cast tools table
      for tool, options in pairs(tools) do
        if options ~= false then
          require(integration_modules[integration][tool]).attach(options == true and {} or options)
        end
      end
    end
  end
end

---Set up buffer cleanup and enable configured integrations.
---Calling this function more than once is safe; new integrations are attached.
---@param options? LintActions.SetupOptions
function M.setup(options)
  if options == nil then
    options = {}
  end
  items.expect(options, 'table', 'options')
  for name in pairs(options) do
    if name ~= 'integrations' then
      error(('unknown setup option: %s'):format(name), 2)
    end
  end

  if options.integrations ~= nil then
    validate_integrations(options.integrations)
  end

  if not configured then
    configured = true
    vim.api.nvim_create_autocmd('BufWipeout', {
      group = vim.api.nvim_create_augroup('lint_actions', { clear = true }),
      callback = function(event)
        require('lint_actions.store').clear(event.buf)
      end,
    })
  end

  if options.integrations ~= nil then
    attach_integrations(options.integrations)
  end
end

---Replace the actions published by one source for a buffer.
---An empty item list clears that source without starting the LSP client.
---@param options LintActions.PublishOptions
function M.publish(options)
  items.expect(options, 'table', 'options')
  items.expect(options.bufnr, 'number', 'bufnr')
  items.expect(options.source, 'string', 'source')
  local valid, invalid = pcall(items.validate, options.items)
  if not valid then
    error(invalid, 2)
  end
  if options.source == '' then
    error('source must not be empty', 2)
  end
  if not vim.api.nvim_buf_is_valid(options.bufnr) then
    error('bufnr must refer to a valid buffer', 2)
  end

  M.setup()
  if #options.items == 0 then
    require('lint_actions.store').clear(options.bufnr, options.source)
    return
  end
  require('lint_actions.server').attach(options.bufnr)

  require('lint_actions.store').publish({
    bufnr = options.bufnr,
    uri = vim.uri_from_bufnr(options.bufnr),
    source = options.source,
    changedtick = vim.api.nvim_buf_get_changedtick(options.bufnr),
    version = vim.lsp.util.buf_versions[options.bufnr],
    items = items.normalize(options.items, options.bufnr),
  })
end

---Clear actions for one source, or every source when `source` is omitted.
---@param options LintActions.ClearOptions
function M.clear(options)
  items.expect(options, 'table', 'options')
  items.expect(options.bufnr, 'number', 'bufnr')
  if options.source ~= nil then
    items.expect(options.source, 'string', 'source')
  end
  require('lint_actions.store').clear(options.bufnr, options.source)
end

---Register a provider that is asked for actions when Neovim requests them,
---instead of publishing them ahead of time. Registering the same source twice
---replaces the earlier provider.
---@param provider LintActions.Provider
function M.register(provider)
  items.expect(provider, 'table', 'provider')
  items.expect(provider.source, 'string', 'provider.source')
  items.expect(provider.provide, 'function', 'provider.provide')
  if provider.source == '' then
    error('provider.source must not be empty', 2)
  end
  if provider.filetypes ~= nil then
    items.expect(provider.filetypes, 'table', 'provider.filetypes')
  end
  if provider.enabled ~= nil then
    items.expect(provider.enabled, 'function', 'provider.enabled')
  end

  M.setup()
  require('lint_actions.providers').register(provider)
end

---Remove a registered provider. Buffers stay attached; they simply stop
---receiving actions from that source.
---@param source string
function M.unregister(source)
  items.expect(source, 'string', 'source')
  require('lint_actions.providers').unregister(source)
end

---Parse tool output through an adapter and publish the resulting actions.
---@param options LintActions.IngestOptions
function M.ingest(options)
  items.expect(options, 'table', 'options')
  items.expect(options.adapter, 'table', 'adapter')
  items.expect(options.adapter.parse, 'function', 'adapter.parse')

  local parsed = options.adapter.parse({
    output = options.output,
    bufnr = options.bufnr,
    cwd = options.cwd,
    diagnostics = options.diagnostics,
  })
  return M.publish({
    bufnr = options.bufnr,
    source = options.source or options.adapter.source,
    items = parsed,
  })
end

return M
