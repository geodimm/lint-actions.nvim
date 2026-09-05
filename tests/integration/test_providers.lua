local MiniTest = require('mini.test')
local helpers = require('tests.support.nvim')
local lint_actions = require('lint_actions')
local providers = require('lint_actions.providers')

local eq = helpers.eq
local expect_error = helpers.expect_error

local T = helpers.new_set()

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

  providers.actions(bufnr, helpers.range(1, 0, 1, 1), { 'refactor' })
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

  eq(titles(providers.actions(bufnr, helpers.range(0, 0, 0, 0))), { 'First line' })
  eq(titles(providers.actions(bufnr, helpers.range(2, 0, 2, 0))), { 'Third line' })
  eq(titles(providers.actions(bufnr, helpers.range(2, 0, 2, 0), { 'refactor' })), { 'Third line' })
  eq(titles(providers.actions(bufnr, helpers.range(2, 0, 2, 0), { 'quickfix' })), {})
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

  eq(titles(providers.actions(bufnr, helpers.range(0, 0, 0, 0))), { 'Text action' })

  vim.bo[bufnr].filetype = 'lua'
  eq(titles(providers.actions(bufnr, helpers.range(0, 0, 0, 0))), { 'Lua action' })
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

  eq(titles(providers.actions(bufnr, helpers.range(0, 0, 0, 0))), { 'Second registration' })
end

T['provider results are atomic'] = MiniTest.new_set()
for _, failure in ipairs({ 'callback', 'validation', 'normalization', 'filtering' }) do
  T['provider results are atomic']['discards the entire result on failure during ' .. failure] = function()
    local bufnr = helpers.new_buffer('provider-error.txt', { 'text' })
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
        if failure == 'callback' then
          error('provider failed')
        end
        local invalid_actions = {
          validation = { title = 42 },
          normalization = { title = 'Invalid edit', edit = 'invalid' },
          filtering = { title = 'Invalid kind', kind = 42 },
        }
        return { item('Partial result'), { action = invalid_actions[failure] } }
      end,
    })
    lint_actions.register({
      source = 'healthy',
      provide = function()
        return { item('Healthy result') }
      end,
    })

    local result = providers.actions(bufnr, helpers.range(0, 0, 0, 0), { 'quickfix' })
    eq(titles(result), { 'Healthy result' })
    eq(
      vim.wait(200, function()
        return #notifications > 0
      end),
      true
    )
    eq(#notifications, 1)
    eq(notifications[1]:find('lint-actions: provider broken:', 1, true) ~= nil, true)
  end
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
T['unregister()']['requires a source name'] = function()
  expect_error('source must be string, got nil', function()
    helpers.call(lint_actions.unregister)
  end)
end

return T
