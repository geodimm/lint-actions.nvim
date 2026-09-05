local MiniTest = require('mini.test')
local helpers = require('tests.helpers')
local store = require('lint_actions.store')

local eq = helpers.eq
local T = MiniTest.new_set({
  hooks = { pre_case = store._reset, post_case = store._reset },
})

T['LSP transport'] = MiniTest.new_set()

for _, form in ipairs({ 'changes', 'documentChanges' }) do
  T['LSP transport']['applies multi-file ' .. form .. ' with unknown secondary versions'] = function()
    local primary = helpers.new_buffer('multi-primary-' .. form .. '.txt', { 'old' })
    local secondary = helpers.new_buffer('multi-secondary-' .. form .. '.txt', { 'old' })
    local primary_uri, secondary_uri = vim.uri_from_bufnr(primary), vim.uri_from_bufnr(secondary)
    local range = helpers.range(0, 0, 0, 3)
    local edits = { { range = range, newText = 'new' } }
    local edit = form == 'changes' and { changes = { [primary_uri] = edits, [secondary_uri] = edits } }
      or {
        documentChanges = {
          { textDocument = { uri = secondary_uri }, edits = edits },
          { textDocument = { uri = primary_uri }, edits = edits },
        },
      }
    local original = vim.deepcopy(edit)
    require('lint_actions').publish({
      bufnr = primary,
      source = 'multi-file',
      items = { { action = { title = 'Update both files', edit = edit } } },
    })
    eq(
      vim.wait(1000, function()
        local client = vim.lsp.get_clients({ bufnr = primary, name = 'lint-actions' })[1]
        return client ~= nil and client.initialized == true
      end),
      true
    )

    local found = helpers.request(primary, range)
    eq(#found, 1)
    local version = vim.api.nvim_buf_get_changedtick(primary)
    vim.lsp.util.apply_workspace_edit(found[1].edit, 'utf-8')
    eq(vim.api.nvim_buf_get_lines(primary, 0, -1, false), { 'new' })
    eq(vim.api.nvim_buf_get_lines(secondary, 0, -1, false), { 'new' })
    for _, change in ipairs(found[1].edit.documentChanges) do
      local expected = change.textDocument.uri == primary_uri and version
        or (vim.fn.has('nvim-0.12') == 1 and vim.NIL or nil)
      eq(change.textDocument.version, expected)
    end
    eq(edit, original)
  end
end

T['LSP transport']['publishes native actions, filters them, and rejects stale batches'] = function()
  local actions = require('lint_actions')
  local bufnr = helpers.new_buffer(vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'server.txt'), { 'alpha', 'beta' })
  local uri = vim.uri_from_bufnr(bufnr)
  local range = helpers.range(1, 0, 1, 4)

  actions.publish({
    bufnr = bufnr,
    source = 'first',
    items = {
      {
        range = range,
        action = {
          title = 'Replace beta',
          kind = 'source.fixAll',
          edit = { changes = { [uri] = { { range = range, newText = 'gamma' } } } },
        },
      },
    },
  })

  eq(
    vim.wait(1000, function()
      local clients = vim.lsp.get_clients({ bufnr = bufnr, name = 'lint-actions' })
      return clients[1] ~= nil and clients[1].initialized == true
    end),
    true
  )

  eq(#helpers.request(bufnr, helpers.range(0, 0, 0, 1)), 0)

  local found = helpers.request(bufnr, range, { 'source' })
  eq(#found, 1)
  eq(#helpers.request(bufnr, helpers.range(1, 4, 1, 4)), 1)
  eq(found[1].edit.changes, nil)
  eq(found[1].edit.documentChanges[1].textDocument.version, vim.api.nvim_buf_get_changedtick(bufnr))
  eq(#helpers.request(bufnr, range, { 'refactor' }), 0)

  vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { 'changed' })
  eq(#helpers.request(bufnr, range), 0)
  local original_print = print
  MiniTest.finally(function()
    _G.print = original_print
  end)
  _G.print = function() end
  vim.lsp.util.apply_workspace_edit(found[1].edit, 'utf-8')
  _G.print = original_print
  eq(vim.api.nvim_buf_get_lines(bufnr, 1, 2, false)[1], 'changed')
end

T['LSP transport']['returns command-carrying actions unchanged'] = function()
  local actions = require('lint_actions')
  local bufnr = helpers.new_buffer(vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'command.txt'), { 'alpha' })
  local range = helpers.range(0, 0, 0, 5)
  local command = { title = 'Run it', command = 'my-tool.run', arguments = { 'alpha' } }

  actions.publish({
    bufnr = bufnr,
    source = 'tool',
    items = { { range = range, action = { title = 'Run it', kind = 'quickfix', command = command } } },
  })
  eq(
    vim.wait(1000, function()
      local client = vim.lsp.get_clients({ bufnr = bufnr, name = 'lint-actions' })[1]
      return client ~= nil and client.initialized == true
    end),
    true
  )

  -- Neovim routes this to `vim.lsp.commands`, so the whole command has to
  -- survive publication rather than being reduced to its edit.
  local found = helpers.request(bufnr, range)
  eq(#found, 1)
  eq(found[1].command, command)
end

T['LSP transport']['requires fresh publication after a buffer rename'] = function()
  local actions = require('lint_actions')
  local bufnr = helpers.new_buffer('server-before-rename.txt', { 'old' })
  local range = helpers.range(0, 0, 0, 3)
  local publication = {
    bufnr = bufnr,
    source = 'tool',
    items = { { action = { title = 'Replace text', edit = { range = range, newText = 'new' } } } },
  }
  actions.publish(publication)
  eq(
    vim.wait(1000, function()
      local client = vim.lsp.get_clients({ bufnr = bufnr, name = 'lint-actions' })[1]
      return client ~= nil and client.initialized == true
    end),
    true
  )
  eq(#helpers.request(bufnr, range), 1)

  vim.api.nvim_buf_set_name(bufnr, 'server-after-rename.txt')
  eq(helpers.request(bufnr, range), {})

  actions.publish(publication)
  local found = helpers.request(bufnr, range)
  eq(#found, 1)
  eq(found[1].edit.documentChanges[1].textDocument.uri, vim.uri_from_bufnr(bufnr))
  vim.lsp.util.apply_workspace_edit(found[1].edit, 'utf-8')
  eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { 'new' })
end

T['_cmd()'] = MiniTest.new_set()

T['_cmd()']['implements initialization, shutdown, unsupported methods, and one exit'] = function()
  local exits = {}
  local dispatchers = {
    on_exit = function(code, signal)
      table.insert(exits, { code, signal })
    end,
  }
  local rpc = helpers.call(require('lint_actions.server')._cmd, dispatchers)

  local initialize
  local ok, request_id = rpc.request('initialize', {}, function(err, result)
    eq(err, nil)
    initialize = result
  end)
  eq(ok, true)
  eq(request_id, 1)
  eq(initialize.capabilities.positionEncoding, 'utf-8')
  eq(initialize.capabilities.codeActionProvider, true)

  local shutdown = 'not called'
  rpc.request('shutdown', {}, function(err, result)
    eq(err, nil)
    shutdown = result
  end)
  eq(shutdown, nil)

  local method_error
  helpers.call(rpc.request, 'unknown/method', {}, function(err)
    method_error = err
  end)
  eq(method_error, { code = -32601, message = 'Method not found: unknown/method' })

  eq(rpc.is_closing(), false)
  eq(rpc.notify('exit'), true)
  eq(rpc.is_closing(), true)
  rpc.terminate()
  eq(exits, { { 0, 0 } })
end

return T
