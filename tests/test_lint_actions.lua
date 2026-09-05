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
  mock_integration('shellcheck', function(options)
    calls.shellcheck = options
  end)

  lint_actions.setup({
    integrations = {
      nvim_lint = {
        golangci = true,
        markdownlint = { source = 'custom-markdownlint' },
        shellcheck = true,
      },
    },
  })

  eq(calls.golangci, {})
  eq(calls.markdownlint, { source = 'custom-markdownlint' })
  eq(calls.shellcheck, {})
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

T['publish()']['preserves explicit secondary versions and resource operations'] = function()
  local bufnr = helpers.new_buffer('publish-secondary-versions.txt', { 'text' })
  local secondary = helpers.new_buffer('publish-secondary-target.txt', { 'text' })
  local uri = vim.uri_from_bufnr(secondary)
  local range = helpers.range(0, 0, 0, 4)
  local changes = {
    { textDocument = { uri = uri, version = 42 }, edits = { { range = range, newText = 'new' } } },
    { textDocument = { uri = uri, version = vim.NIL }, edits = {} },
    { kind = 'rename', oldUri = uri, newUri = uri .. '.renamed' },
  }
  lint_actions.publish({
    bufnr = bufnr,
    source = 'tool',
    items = { { action = { title = 'Update secondary document', edit = { documentChanges = changes } } } },
  })
  local published = assert(store.actions(bufnr, range)[1])
  local normalized = assert(published.edit).documentChanges
  assert(normalized)
  eq(normalized[1].textDocument.version, 42)
  eq(normalized[2].textDocument.version, vim.fn.has('nvim-0.12') == 1 and vim.NIL or nil)
  eq(normalized[3].kind, 'rename')
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

for _, modern in ipairs({ false, true }) do
  local release = modern and '0.12+' or '0.11'
  T['publish()']['normalizes missing and explicit null versions for Neovim ' .. release] = function()
    local bufnr = helpers.new_buffer('versions-' .. release .. '.txt', { 'text' })
    local secondary_uri = vim.uri_from_fname(vim.fn.getcwd() .. '/secondary.txt')
    local changes = {
      { textDocument = { uri = secondary_uri }, edits = {} },
      { textDocument = { uri = secondary_uri, version = vim.NIL }, edits = {} },
      { textDocument = { uri = secondary_uri, version = 42 }, edits = {} },
    }
    local original = vim.deepcopy(changes)
    local has = vim.fn.has
    MiniTest.finally(function()
      rawset(vim.fn, 'has', has)
    end)
    rawset(vim.fn, 'has', function(feature)
      if feature == 'nvim-0.12' then
        return modern and 1 or 0
      end
      return has(feature)
    end)
    local normalized = require('lint_actions.items').normalize({
      { action = { title = 'Update secondary document', edit = { documentChanges = changes } } },
    }, bufnr)
    rawset(vim.fn, 'has', has)
    local document_changes = assert(assert(normalized[1].action.edit).documentChanges)
    local expected = modern and vim.NIL or nil
    eq(document_changes[1].textDocument.version, expected)
    eq(document_changes[2].textDocument.version, expected)
    eq(document_changes[3].textDocument.version, 42)
    eq(changes, original)
  end
end

T['publish()']['offers an item without a range on every line of the buffer'] = function()
  local bufnr = helpers.new_buffer('publish-whole-buffer.txt', { 'alpha', 'beta', 'gamma' })

  lint_actions.publish({
    bufnr = bufnr,
    source = 'tool',
    items = { { action = { title = 'Whole buffer' } } },
  })

  eq(#store.actions(bufnr, helpers.range(0, 0, 0, 0)), 1)
  eq(#store.actions(bufnr, helpers.range(2, 0, 2, 0)), 1)
  eq(store.actions(bufnr, helpers.range(9, 0, 9, 0)), {})
end

T['publish()']['accepts positions without a character'] = function()
  local bufnr = helpers.new_buffer('publish-line-only.txt', { 'alpha', 'beta' })

  lint_actions.publish({
    bufnr = bufnr,
    source = 'tool',
    items = { { range = { start = { line = 1 }, ['end'] = { line = 1 } }, action = { title = 'Second line' } } },
  })

  eq(store.actions(bufnr, helpers.range(0, 0, 0, 0)), {})
  eq(#store.actions(bufnr, helpers.range(1, 0, 1, 0)), 1)
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
