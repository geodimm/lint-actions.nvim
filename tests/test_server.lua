local MiniTest = require('mini.test')
local helpers = require('tests.helpers')
local store = require('lint_actions.store')

local eq = helpers.eq
local T = MiniTest.new_set({
  hooks = { pre_case = store._reset, post_case = store._reset },
})

T['LSP transport'] = MiniTest.new_set()

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
