local helpers = require('tests.helpers')
local server = require('lint_actions.server')
local eq = helpers.eq

local function transport()
  local exits = {}
  local rpc = helpers.call(server._cmd, {
    on_exit = function(code, signal)
      table.insert(exits, { code, signal })
    end,
  })
  return rpc, exits
end

describe('LSP transport', function()
  describe('request protocol', function()
    it('advertises only code actions with UTF-8 positions', function()
      local rpc = transport()
      local initialized
      rpc.request('initialize', {}, function(err, result)
        eq(err, nil)
        initialized = result
      end)
      eq(initialized.capabilities, { positionEncoding = 'utf-8', codeActionProvider = true })
    end)

    it('assigns increasing IDs to successful and unsupported requests', function()
      local rpc = transport()
      for index, method in ipairs({ 'initialize', 'unknown/method', 'shutdown' }) do
        local calls = 0
        local ok, id = helpers.call(rpc.request, method, {}, function(err, result)
          calls = calls + 1
          if method == 'unknown/method' then
            eq(err, { code = -32601, message = 'Method not found: unknown/method' })
          else
            eq(err, nil)
          end
          if method == 'shutdown' then
            eq(result, nil)
          end
        end)
        eq(ok, true)
        eq(id, index)
        eq(calls, 1)
      end
    end)
  end)

  describe('shutdown lifecycle', function()
    for _, first in ipairs({ 'exit notification', 'termination' }) do
      it(first .. ' closes once, even when repeated', function()
        local rpc, exits = transport()
        eq(rpc.is_closing(), false)
        if first == 'exit notification' then
          eq(rpc.notify('exit'), true)
        else
          rpc.terminate()
        end
        eq(rpc.is_closing(), true)
        rpc.notify('exit')
        rpc.terminate()
        eq(exits, { { 0, first == 'termination' and 15 or 0 } })
      end)
    end
  end)
end)
