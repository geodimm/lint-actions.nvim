local MiniTest = require('mini.test')
local helpers = require('tests.helpers')
local integration = require('lint_actions.integrations.nvim_lint')
local store = require('lint_actions.store')

local eq = helpers.eq
local expect_error = helpers.expect_error
local T = MiniTest.new_set({
  hooks = { pre_case = store._reset, post_case = store._reset },
})

local function adapter(parse)
  return {
    source = 'tool',
    parse = parse or function()
      return {}
    end,
  }
end

T['attach()'] = MiniTest.new_set()

T['attach()']['preserves parser results and wraps a concrete linter once'] = function()
  local diagnostics = { { lnum = 0, col = 0, message = 'message', source = 'tool' } }
  local calls = 0
  local linter = {
    parser = function(_output, _bufnr, _cwd)
      calls = calls + 1
      return diagnostics
    end,
  }
  integration.attach({ linter = linter, adapter = adapter() })
  local wrapped = linter.parser
  integration.attach({ linter = linter, adapter = adapter() })
  eq(linter.parser, wrapped)

  local bufnr = helpers.new_buffer('nvim-lint-concrete.txt', { 'text' })
  eq(linter.parser('', bufnr, vim.fn.getcwd()), diagnostics)
  eq(calls, 1)
end

T['attach()']['forwards output, diagnostics, buffer, and cwd to the adapter'] = function()
  local observed
  local diagnostics = { { message = 'message' } }
  local linter = {
    parser = function(_output, _bufnr, _cwd)
      return diagnostics
    end,
  }
  integration.attach({
    linter = linter,
    adapter = adapter(function(context)
      observed = context
      return {}
    end),
  })

  local bufnr = helpers.new_buffer('nvim-lint-context.txt', { 'text' })
  eq(linter.parser('output', bufnr, '/work'), diagnostics)
  eq(observed.output, 'output')
  eq(observed.bufnr, bufnr)
  eq(observed.cwd, '/work')
  eq(observed.diagnostics, diagnostics)
end

T['attach()']['resolves and wraps factory linters by name once'] = function()
  local diagnostics = { { lnum = 0, col = 0, message = 'message', source = 'tool' } }
  local lint = helpers.mock_nvim_lint({
    dynamic = function()
      return {
        parser = function()
          return diagnostics
        end,
      }
    end,
  })

  integration.attach({ linter = 'dynamic', adapter = adapter() })
  local factory = lint.linters.dynamic
  integration.attach({ linter = 'dynamic', adapter = adapter() })
  eq(lint.linters.dynamic, factory)

  local definition = factory()
  eq(definition._lint_actions_attached, 'tool')
  eq(definition.parser('', -1, vim.fn.getcwd()), diagnostics)
end

T['attach()']['does not ingest an invalid buffer'] = function()
  local adapter_calls = 0
  local diagnostics = { { message = 'message' } }
  local linter = {
    parser = function(_output, _bufnr, _cwd)
      return diagnostics
    end,
  }
  integration.attach({
    linter = linter,
    adapter = adapter(function()
      adapter_calls = adapter_calls + 1
      return {}
    end),
  })

  eq(linter.parser('', -1, vim.fn.getcwd()), diagnostics)
  eq(adapter_calls, 0)
end

T['attach()']['clears actions instead of ingesting a modified buffer'] = function()
  local adapter_calls = 0
  local linter = {
    parser = function(_output, _bufnr, _cwd)
      return {}
    end,
  }
  integration.attach({
    linter = linter,
    adapter = adapter(function()
      adapter_calls = adapter_calls + 1
      return {}
    end),
  })

  local bufnr = helpers.new_buffer('nvim-lint-modified.txt', { 'text' })
  local range = helpers.range(0, 0, 0, 4)
  store.publish(helpers.batch(bufnr, 'tool', 'Old action', range))
  vim.bo[bufnr].modified = true
  linter.parser('', bufnr, vim.fn.getcwd())
  vim.bo[bufnr].modified = false

  eq(adapter_calls, 0)
  eq(store.actions(bufnr, range), {})
end

T['attach()']['rejects a non-existing linter name'] = function()
  helpers.mock_nvim_lint({})
  expect_error('unknown nvim-lint linter: missing', function()
    integration.attach({ linter = 'missing', adapter = adapter() })
  end)
end

T['attach()']['rejects concrete linter tables without a parser function'] = function()
  expect_error('lint-actions only supports nvim-lint parser functions', function()
    helpers.call(integration.attach, { linter = {}, adapter = adapter() })
  end)
  expect_error('lint-actions only supports nvim-lint parser functions', function()
    helpers.call(integration.attach, { linter = { parser = {} }, adapter = adapter() })
  end)
end

T['attach()']['rejects factories returning invalid linter definitions'] = function()
  local lint = helpers.mock_nvim_lint({
    broken = function()
      return 'invalid'
    end,
  })
  integration.attach({ linter = 'broken', adapter = adapter() })

  expect_error('linter definition', function()
    lint.linters.broken()
  end)
end

T['attach()']['rejects invalid options, adapters, and linter values'] = function()
  expect_error('options', function()
    helpers.call(integration.attach)
  end)
  expect_error('options.adapter', function()
    helpers.call(integration.attach, { linter = {} })
  end)
  expect_error('options.adapter.parse', function()
    helpers.call(integration.attach, { linter = {}, adapter = { source = 'tool', parse = 'invalid' } })
  end)
  expect_error('source', function()
    helpers.call(integration.attach, { linter = {}, adapter = { parse = function() end } })
  end)
  expect_error('options.configure', function()
    helpers.call(integration.attach, { linter = {}, adapter = adapter(), configure = 'invalid' })
  end)
  expect_error('options.linter must be a linter name or table', function()
    helpers.call(integration.attach, { linter = false, adapter = adapter() })
  end)
end

T['attach()']['runs configure on the resolved linter before wrapping its parser'] = function()
  local configured = 0
  local diagnostics = { { lnum = 0, col = 0, message = 'message', source = 'tool' } }
  local definition = {
    parser = function(_, _, _)
      return {}
    end,
  }

  integration.attach({
    linter = definition,
    adapter = adapter(),
    configure = function(linter)
      configured = configured + 1
      linter.args = { '--json' }
      linter.parser = function(_, _, _)
        return diagnostics
      end
    end,
  })

  -- The wrapped parser must be the one configure installed, not the original.
  eq(definition.args, { '--json' })
  eq(definition.parser('', -1, vim.fn.getcwd()), diagnostics)

  integration.attach({
    linter = definition,
    adapter = adapter(),
    configure = function()
      configured = configured + 1
    end,
  })
  eq(configured, 1)
end

T['attach()']['runs configure once for a factory linter'] = function()
  local configured = 0
  local lint = helpers.mock_nvim_lint({
    dynamic = function()
      return {
        parser = function()
          return {}
        end,
      }
    end,
  })

  local function configure(linter)
    configured = configured + 1
    linter.args = { '--json' }
  end

  integration.attach({ linter = 'dynamic', adapter = adapter(), configure = configure })
  integration.attach({ linter = 'dynamic', adapter = adapter(), configure = configure })

  local definition = lint.linters.dynamic()
  eq(definition.args, { '--json' })
  eq(definition._lint_actions_attached, 'tool')
  eq(configured, 1)
end

T['attach()']['refuses a configure step once another source wrapped the linter'] = function()
  local definition = {
    parser = function()
      return {}
    end,
  }
  integration.attach({ linter = definition, adapter = adapter() })

  expect_error('attach the markdownlint integration before attaching this linter through nvim_lint', function()
    integration.attach({
      linter = definition,
      adapter = adapter(),
      source = 'markdownlint',
      configure = function() end,
    })
  end)
end

return T
