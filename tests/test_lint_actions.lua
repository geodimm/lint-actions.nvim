local MiniTest = require('mini.test')
local helpers = require('tests.helpers')
local lint_actions = require('lint_actions')
local store = require('lint_actions.store')

local eq = helpers.eq
local expect_error = helpers.expect_error
local T = MiniTest.new_set({
  hooks = { pre_case = store._reset, post_case = store._reset },
})

T['setup()'] = MiniTest.new_set()

local function mock_integration(name, attach)
  local module = 'lint_actions.integrations.' .. name
  local previous = package.loaded[module]
  package.loaded[module] = { attach = attach }
  MiniTest.finally(function()
    package.loaded[module] = previous
  end)
end

T['setup()']['enables integrations with defaults or options'] = function()
  local calls = {}
  mock_integration('golangci', function(options)
    calls.golangci = options
  end)
  mock_integration('markdownlint', function(options)
    calls.markdownlint = options
  end)

  lint_actions.setup({
    integrations = {
      nvim_lint = {
        golangci = true,
        markdownlint = { source = 'custom-markdownlint' },
      },
    },
  })

  eq(calls.golangci, {})
  eq(calls.markdownlint, { source = 'custom-markdownlint' })
end

T['setup()']['can attach integrations on a later call'] = function()
  local calls = 0
  mock_integration('golangci', function()
    calls = calls + 1
  end)

  lint_actions.setup()
  lint_actions.setup({ integrations = { nvim_lint = { golangci = true } } })

  eq(calls, 1)
end

T['setup()']['ignores explicitly disabled integrations'] = function()
  local calls = 0
  mock_integration('golangci', function()
    calls = calls + 1
  end)

  lint_actions.setup({ integrations = { nvim_lint = { golangci = false } } })
  lint_actions.setup({ integrations = { nvim_lint = false } })

  eq(calls, 0)
end

T['setup()']['rejects invalid options and integrations'] = function()
  local calls = 0
  mock_integration('golangci', function()
    calls = calls + 1
  end)

  expect_error('options must be table, got boolean', function()
    helpers.call(lint_actions.setup, false)
  end)
  expect_error('options.integrations must be table, got boolean', function()
    helpers.call(lint_actions.setup, { integrations = true })
  end)
  expect_error('unknown setup option: integration', function()
    lint_actions.setup({ integration = {} })
  end)
  expect_error('unknown integration: missing', function()
    lint_actions.setup({ integrations = { missing = true } })
  end)
  expect_error('options.integrations.nvim_lint must be table, got boolean', function()
    helpers.call(lint_actions.setup, { integrations = { nvim_lint = true } })
  end)
  expect_error('unknown nvim_lint integration: missing', function()
    lint_actions.setup({ integrations = { nvim_lint = { golangci = true, missing = true } } })
  end)
  eq(calls, 0)
  expect_error('options.integrations.nvim_lint.golangci must be boolean or table, got string', function()
    helpers.call(lint_actions.setup, { integrations = { nvim_lint = { golangci = 'yes' } } })
  end)
end

T['publish()'] = MiniTest.new_set()

T['publish()']['treats an empty publication as a source clear'] = function()
  local bufnr = helpers.new_buffer('publish-empty.txt', { 'text' })
  local range = helpers.range(0, 0, 0, 4)
  store.publish(helpers.batch(bufnr, 'tool', 'Old action', range))

  lint_actions.publish({ bufnr = bufnr, source = 'tool', items = {} })
  eq(store.actions(bufnr, range), {})
end

T['publish()']['versions current-buffer edits without mutating input'] = function()
  local bufnr = helpers.new_buffer('publish-version.txt', { 'text' })
  local range = helpers.range(0, 0, 0, 4)
  local uri = vim.uri_from_bufnr(bufnr)
  local action = {
    title = 'Replace text',
    edit = { changes = { [uri] = { { range = range, newText = 'new' } } } },
  }

  lint_actions.publish({
    bufnr = bufnr,
    source = 'tool',
    items = { { range = range, action = action } },
  })

  local published = store.actions(bufnr, range)[1]
  eq(action.edit.changes[uri][1].newText, 'new')
  eq(action.edit.documentChanges, nil)
  eq(published.edit.changes, nil)
  eq(published.edit.documentChanges[1].textDocument.version, vim.api.nvim_buf_get_changedtick(bufnr))
end

T['publish()']['wraps a text edit for the published buffer'] = function()
  local bufnr = helpers.new_buffer('publish-text-edit.txt', { 'old text' })
  local range = helpers.range(0, 0, 0, 3)
  local action = {
    title = 'Replace text',
    edit = { range = range, newText = 'new' },
  }

  lint_actions.publish({
    bufnr = bufnr,
    source = 'tool',
    items = { { range = range, action = action } },
  })

  local published = store.actions(bufnr, range)[1]
  local document_edit = published.edit.documentChanges[1]
  eq(action.edit, { range = range, newText = 'new' })
  eq(document_edit.textDocument.uri, vim.uri_from_bufnr(bufnr))
  eq(document_edit.textDocument.version, vim.api.nvim_buf_get_changedtick(bufnr))
  eq(document_edit.edits, { { range = range, newText = 'new' } })
end

T['publish()']['wraps a list of text edits for the published buffer'] = function()
  local bufnr = helpers.new_buffer('publish-text-edits.txt', { 'old text' })
  local first = { range = helpers.range(0, 0, 0, 3), newText = 'new' }
  local second = { range = helpers.range(0, 4, 0, 8), newText = 'value' }

  lint_actions.publish({
    bufnr = bufnr,
    source = 'tool',
    items = {
      {
        range = first.range,
        action = { title = 'Replace text', edit = { first, second } },
      },
    },
  })

  local published = store.actions(bufnr, first.range)[1]
  eq(published.edit.documentChanges[1].edits, { first, second })
end

local invalid_publications = {
  {
    'rejects a missing options table',
    'options must be table, got nil',
    function()
      return nil
    end,
  },
  {
    'rejects a non-number buffer',
    'bufnr must be number, got string',
    function()
      return { bufnr = 'current', source = 'tool', items = {} }
    end,
  },
  {
    'rejects a non-string source',
    'source must be string, got number',
    function()
      return { bufnr = 0, source = 1, items = {} }
    end,
  },
  {
    'rejects an empty source',
    'source must not be empty',
    function()
      return { bufnr = 0, source = '', items = {} }
    end,
  },
  {
    'rejects a non-table item list',
    'items must be table, got string',
    function()
      return { bufnr = 0, source = 'tool', items = 'invalid' }
    end,
  },
  {
    'rejects a non-table item',
    'items[1] must be table, got number',
    function()
      return { bufnr = 0, source = 'tool', items = { 1 } }
    end,
  },
  {
    'rejects an incomplete range',
    'items[1].range.start must be table, got nil',
    function()
      return { bufnr = 0, source = 'tool', items = { { range = {}, action = { title = 'Fix' } } } }
    end,
  },
  {
    'rejects an invalid action title',
    'items[1].action.title must be string, got number',
    function()
      local range = helpers.range(0, 0, 0, 0)
      return { bufnr = 0, source = 'tool', items = { { range = range, action = { title = 1 } } } }
    end,
  },
  {
    'rejects an invalid buffer handle',
    'bufnr must refer to a valid buffer',
    function()
      return { bufnr = -1, source = 'tool', items = {} }
    end,
  },
}

for _, case in ipairs(invalid_publications) do
  local name, message, make_options = unpack(case)
  T['publish()'][name] = function()
    expect_error(message, function()
      helpers.call(lint_actions.publish, make_options())
    end)
  end
end

T['clear()'] = MiniTest.new_set()

T['clear()']['validates its options'] = function()
  expect_error('options must be table, got nil', function()
    helpers.call(lint_actions.clear)
  end)
  expect_error('bufnr must be number, got string', function()
    helpers.call(lint_actions.clear, { bufnr = 'current' })
  end)
  expect_error('source must be string, got number', function()
    helpers.call(lint_actions.clear, { bufnr = 0, source = 1 })
  end)
end

T['ingest()'] = MiniTest.new_set()

T['ingest()']['passes adapter context and uses the adapter source'] = function()
  local bufnr = helpers.new_buffer('ingest.txt', { 'text' })
  local observed
  local diagnostics = {
    {
      bufnr = bufnr,
      lnum = 0,
      col = 0,
      end_lnum = 0,
      end_col = 0,
      severity = vim.diagnostic.severity.WARN,
      message = 'diagnostic',
    },
  }
  lint_actions.ingest({
    adapter = {
      source = 'adapter-source',
      parse = function(context)
        observed = context
        return {}
      end,
    },
    output = 'raw output',
    bufnr = bufnr,
    cwd = '/work',
    diagnostics = diagnostics,
  })

  eq(observed.output, 'raw output')
  eq(observed.bufnr, bufnr)
  eq(observed.cwd, '/work')
  eq(observed.diagnostics, diagnostics)
end

T['ingest()']['rejects invalid adapters and invalid parser results'] = function()
  expect_error('adapter must be table, got nil', function()
    helpers.call(lint_actions.ingest, {})
  end)
  expect_error('adapter.parse must be function, got string', function()
    helpers.call(lint_actions.ingest, { adapter = { parse = 'invalid' } })
  end)
  expect_error('items must be table, got string', function()
    helpers.call(lint_actions.ingest, {
      adapter = {
        source = 'tool',
        parse = function()
          return 'invalid'
        end,
      },
      bufnr = 0,
    })
  end)
end

return T
