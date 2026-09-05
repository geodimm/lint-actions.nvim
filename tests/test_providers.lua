local MiniTest = require('mini.test')
local helpers = require('tests.helpers')
local lint_actions = require('lint_actions')
local providers = require('lint_actions.providers')
local store = require('lint_actions.store')

local eq = helpers.eq
local expect_error = helpers.expect_error

local function reset()
  store._reset()
  providers._reset()
end

local T = MiniTest.new_set({
  hooks = { pre_case = reset, post_case = reset },
})

---@param bufnr integer
local function wait_for_client(bufnr)
  return vim.wait(1000, function()
    local client = vim.lsp.get_clients({ bufnr = bufnr, name = 'lint-actions' })[1]
    return client ~= nil and client.initialized == true
  end)
end

---@param title string
---@param range? table
local function item(title, range)
  return { range = range, action = { title = title, kind = 'quickfix' } }
end

local function titles(actions)
  return vim.tbl_map(function(action)
    return action.title
  end, actions)
end

T['register()'] = MiniTest.new_set()

T['register()']['answers requests from current buffer state without republishing'] = function()
  local bufnr = helpers.new_buffer(vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'provider.txt'), { 'alpha' })

  lint_actions.register({
    source = 'line-counter',
    provide = function(context)
      return { item(('Lines: %d'):format(vim.api.nvim_buf_line_count(context.bufnr))) }
    end,
  })
  eq(wait_for_client(bufnr), true)

  eq(titles(helpers.request(bufnr, helpers.range(0, 0, 0, 0))), { 'Lines: 1' })

  -- The published path would go stale here; a provider recomputes instead.
  vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { 'beta', 'gamma' })
  eq(titles(helpers.request(bufnr, helpers.range(0, 0, 0, 0))), { 'Lines: 3' })
end

T['register()']['passes the requested range and kind filter to the provider'] = function()
  local bufnr = helpers.new_buffer(vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'provider-context.txt'), { 'a', 'b' })
  local seen

  lint_actions.register({
    source = 'context-recorder',
    provide = function(context)
      seen = context
      return {}
    end,
  })
  eq(wait_for_client(bufnr), true)

  helpers.request(bufnr, helpers.range(1, 0, 1, 1), { 'refactor' })
  eq(seen.bufnr, bufnr)
  eq(seen.range, helpers.range(1, 0, 1, 1))
  eq(seen.only, { 'refactor' })
end

T['register()']['filters provider items by range and kind'] = function()
  local bufnr = helpers.new_buffer(vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'provider-filter.txt'), { 'a', 'b', 'c' })

  lint_actions.register({
    source = 'filtered',
    provide = function()
      return {
        { range = helpers.range(0, 0, 0, 1), action = { title = 'First line', kind = 'quickfix' } },
        { range = helpers.range(2, 0, 2, 1), action = { title = 'Third line', kind = 'refactor.extract' } },
      }
    end,
  })
  eq(wait_for_client(bufnr), true)

  eq(titles(helpers.request(bufnr, helpers.range(0, 0, 0, 0))), { 'First line' })
  eq(titles(helpers.request(bufnr, helpers.range(2, 0, 2, 0))), { 'Third line' })
  eq(titles(helpers.request(bufnr, helpers.range(2, 0, 2, 0), { 'refactor' })), { 'Third line' })
  eq(titles(helpers.request(bufnr, helpers.range(2, 0, 2, 0), { 'quickfix' })), {})
end

T['register()']['merges provider and published actions in one sorted response'] = function()
  local bufnr = helpers.new_buffer(vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'provider-merge.txt'), { 'alpha' })

  lint_actions.publish({
    bufnr = bufnr,
    source = 'published',
    items = { item('B published', helpers.range(0, 0, 0, 5)) },
  })
  lint_actions.register({
    source = 'provided',
    provide = function()
      return { item('A provided'), item('C provided') }
    end,
  })
  eq(wait_for_client(bufnr), true)

  eq(titles(helpers.request(bufnr, helpers.range(0, 0, 0, 0))), { 'A provided', 'B published', 'C provided' })
end

T['register()']['restricts providers by filetype and by buffer'] = function()
  local bufnr = helpers.new_buffer(vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'provider-gate.txt'), { 'alpha' })
  vim.bo[bufnr].filetype = 'text'

  lint_actions.register({
    source = 'lua-only',
    filetypes = { 'lua' },
    provide = function()
      return { item('Lua action') }
    end,
  })
  lint_actions.register({
    source = 'text-only',
    filetypes = { 'text' },
    provide = function()
      return { item('Text action') }
    end,
  })
  lint_actions.register({
    source = 'disabled',
    enabled = function()
      return false
    end,
    provide = function()
      return { item('Never offered') }
    end,
  })
  eq(wait_for_client(bufnr), true)

  eq(titles(helpers.request(bufnr, helpers.range(0, 0, 0, 0))), { 'Text action' })

  vim.bo[bufnr].filetype = 'lua'
  eq(titles(helpers.request(bufnr, helpers.range(0, 0, 0, 0))), { 'Lua action' })
end

T['register()']['isolates a failing provider from the rest of the request'] = function()
  local bufnr = helpers.new_buffer(vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'provider-error.txt'), { 'alpha' })
  local notifications = {}
  local notify = vim.notify
  MiniTest.finally(function()
    vim.notify = notify
  end)
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(message)
    table.insert(notifications, message)
  end

  lint_actions.register({
    source = 'broken',
    provide = function()
      error('provider blew up')
    end,
  })
  lint_actions.register({
    source = 'invalid-items',
    provide = function()
      return { { action = { title = 42 } } }
    end,
  })
  lint_actions.register({
    source = 'healthy',
    provide = function()
      return { item('Still offered') }
    end,
  })
  eq(wait_for_client(bufnr), true)

  eq(titles(helpers.request(bufnr, helpers.range(0, 0, 0, 0))), { 'Still offered' })

  vim.wait(200, function()
    return #notifications >= 2
  end)
  table.sort(notifications)
  eq(#notifications, 2)
  eq(notifications[1]:match('provider broken: .*provider blew up') ~= nil, true)
  eq(notifications[2], 'lint-actions: provider invalid-items: items[1].action.title must be string, got number')
end

T['register()']['replaces a provider registered under the same source'] = function()
  local bufnr = helpers.new_buffer(vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'provider-replace.txt'), { 'alpha' })

  lint_actions.register({
    source = 'repeated',
    provide = function()
      return { item('First registration') }
    end,
  })
  lint_actions.register({
    source = 'repeated',
    provide = function()
      return { item('Second registration') }
    end,
  })
  eq(wait_for_client(bufnr), true)

  eq(titles(helpers.request(bufnr, helpers.range(0, 0, 0, 0))), { 'Second registration' })
end

for _, field in ipairs({ 'edit', 'kind' }) do
  T['register()']['isolates malformed ' .. field .. ' fields throughout action processing'] = function()
    local bufnr = helpers.new_buffer('provider-malformed-' .. field .. '.txt', { 'text' })
    local notifications = {}
    local notify = vim.notify
    MiniTest.finally(function()
      vim.notify = notify
    end)
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    lint_actions.register({
      source = 'a-malformed',
      provide = function()
        local malformed = item('Malformed action')
        rawset(malformed.action, field, field == 'edit' and 'invalid' or 42)
        return { item('Partial result'), malformed }
      end,
    })
    lint_actions.register({
      source = 'z-healthy',
      provide = function()
        return { item('Healthy result') }
      end,
    })
    lint_actions.publish({ bufnr = bufnr, source = 'published', items = { item('Published result') } })
    eq(wait_for_client(bufnr), true)

    local result = helpers.request(bufnr, helpers.range(0, 0, 0, 0), { 'quickfix' })
    eq(titles(result), { 'Healthy result', 'Published result' })
    eq(
      vim.wait(200, function()
        return #notifications > 0
      end),
      true
    )
    eq(#notifications, 1)
    eq(notifications[1]:find('lint-actions: provider a-malformed:', 1, true) ~= nil, true)
  end
end

T['register()']['attaches to files opened after registration'] = function()
  local path = vim.fs.joinpath(vim.fn.tempname() .. '-provider.txt')
  vim.fn.writefile({ 'alpha' }, path)
  MiniTest.finally(function()
    vim.fn.delete(path)
  end)

  lint_actions.register({
    source = 'on-read',
    provide = function()
      return { item('Opened action') }
    end,
  })

  vim.cmd.edit(path)
  local bufnr = vim.api.nvim_get_current_buf()
  MiniTest.finally(function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  eq(wait_for_client(bufnr), true)
  eq(titles(helpers.request(bufnr, helpers.range(0, 0, 0, 0))), { 'Opened action' })
end

T['register()']['leaves buffers that are not ordinary files alone'] = function()
  local bufnr = helpers.new_buffer(vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'provider-scratch.txt'), { 'alpha' })
  vim.bo[bufnr].buftype = 'nofile'

  lint_actions.register({
    source = 'any-buffer',
    provide = function()
      return { item('Never offered') }
    end,
  })

  eq(vim.lsp.get_clients({ bufnr = bufnr, name = 'lint-actions' })[1], nil)
  eq(providers.actions(bufnr, helpers.range(0, 0, 0, 0)), {})
end

T['register()']['validates its provider'] = function()
  expect_error('provider must be table, got nil', function()
    helpers.call(lint_actions.register)
  end)
  expect_error('provider.source must be string, got nil', function()
    helpers.call(lint_actions.register, {})
  end)
  expect_error('provider.provide must be function, got nil', function()
    helpers.call(lint_actions.register, { source = 'tool' })
  end)
  expect_error('provider.source must not be empty', function()
    helpers.call(lint_actions.register, { source = '', provide = function() end })
  end)
  expect_error('provider.filetypes must be table, got string', function()
    helpers.call(lint_actions.register, { source = 'tool', provide = function() end, filetypes = 'lua' })
  end)
  expect_error('provider.enabled must be function, got boolean', function()
    helpers.call(lint_actions.register, { source = 'tool', provide = function() end, enabled = true })
  end)
end

T['unregister()'] = MiniTest.new_set()

T['unregister()']['stops a provider from answering'] = function()
  local bufnr = helpers.new_buffer(vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'provider-unregister.txt'), { 'alpha' })

  lint_actions.register({
    source = 'temporary',
    provide = function()
      return { item('Temporary action') }
    end,
  })
  eq(wait_for_client(bufnr), true)
  eq(#helpers.request(bufnr, helpers.range(0, 0, 0, 0)), 1)

  lint_actions.unregister('temporary')
  eq(helpers.request(bufnr, helpers.range(0, 0, 0, 0)), {})

  expect_error('source must be string, got nil', function()
    helpers.call(lint_actions.unregister)
  end)
end

return T
