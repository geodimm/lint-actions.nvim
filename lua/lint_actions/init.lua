local M = {}

local configured = false
local integration_modules = {
  nvim_lint = {
    golangci = 'lint_actions.integrations.golangci',
    markdownlint = 'lint_actions.integrations.markdownlint',
  },
}

local function expect(value, expected, name)
  if type(value) ~= expected then
    error(('%s must be %s, got %s'):format(name, expected, type(value)), 3)
  end
end

local function validate_position(position, name)
  expect(position, 'table', name)
  expect(position.line, 'number', name .. '.line')
  expect(position.character, 'number', name .. '.character')
end

---@param items LintActions.Item[]
local function validate_items(items)
  expect(items, 'table', 'items')
  for index, item in ipairs(items) do
    local name = ('items[%d]'):format(index)
    expect(item, 'table', name)
    expect(item.range, 'table', name .. '.range')
    validate_position(item.range.start, name .. '.range.start')
    validate_position(item.range['end'], name .. '.range.end')
    expect(item.action, 'table', name .. '.action')
    expect(item.action.title, 'string', name .. '.action.title')
  end
end

---@param action lsp.CodeAction
---@param uri string
---@param version integer
---@return lsp.CodeAction
local function version_edit(action, uri, version)
  action = vim.deepcopy(action)
  local edit = action.edit
  if not edit then
    return action
  end

  -- Text edits do not identify their target document. Accept one edit or a
  -- list as a convenient same-buffer shorthand, then put the protocol-correct
  -- WorkspaceEdit on the CodeAction returned to Neovim.
  local text_edit_range = rawget(edit, 'range')
  if text_edit_range or vim.islist(edit) then
    local edits = text_edit_range and { edit } or edit
    action.edit = {
      documentChanges = {
        {
          textDocument = { uri = uri, version = version },
          edits = edits,
        },
      },
    }
    return action
  end

  if edit.changes then
    edit.documentChanges = edit.documentChanges or {}
    for edit_uri, edits in pairs(edit.changes) do
      table.insert(edit.documentChanges, {
        textDocument = { uri = edit_uri, version = edit_uri == uri and version or nil },
        edits = edits,
      })
    end
    edit.changes = nil
  end

  for _, change in ipairs(edit.documentChanges or {}) do
    if change.textDocument and change.textDocument.uri == uri then
      change.textDocument.version = version
    end
  end
  return action
end

---@param integrations table<string, boolean|table>
local function validate_integrations(integrations)
  expect(integrations, 'table', 'options.integrations')

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
  expect(options, 'table', 'options')
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
  expect(options, 'table', 'options')
  expect(options.bufnr, 'number', 'bufnr')
  expect(options.source, 'string', 'source')
  validate_items(options.items)
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

  local uri = vim.uri_from_bufnr(options.bufnr)
  local version = vim.lsp.util.buf_versions[options.bufnr]
  local changedtick = vim.api.nvim_buf_get_changedtick(options.bufnr)
  local items = vim.tbl_map(function(item)
    return {
      range = vim.deepcopy(item.range),
      action = version_edit(item.action, uri, changedtick),
    }
  end, options.items)

  require('lint_actions.store').publish({
    bufnr = options.bufnr,
    uri = uri,
    source = options.source,
    changedtick = changedtick,
    version = version,
    items = items,
  })
end

---Clear actions for one source, or every source when `source` is omitted.
---@param options LintActions.ClearOptions
function M.clear(options)
  expect(options, 'table', 'options')
  expect(options.bufnr, 'number', 'bufnr')
  if options.source ~= nil then
    expect(options.source, 'string', 'source')
  end
  require('lint_actions.store').clear(options.bufnr, options.source)
end

---Parse tool output through an adapter and publish the resulting actions.
---@param options LintActions.IngestOptions
function M.ingest(options)
  expect(options, 'table', 'options')
  expect(options.adapter, 'table', 'adapter')
  expect(options.adapter.parse, 'function', 'adapter.parse')

  local items = options.adapter.parse({
    output = options.output,
    bufnr = options.bufnr,
    cwd = options.cwd,
    diagnostics = options.diagnostics,
  })
  return M.publish({
    bufnr = options.bufnr,
    source = options.source or options.adapter.source,
    items = items,
  })
end

return M
