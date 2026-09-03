local failures = 0
local tests = {}

local function test(name, callback)
  table.insert(tests, { name = name, callback = callback })
end

local function eq(expected, actual)
  if not vim.deep_equal(expected, actual) then
    error(('expected %s, got %s'):format(vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

local function new_buffer(name, lines)
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, name)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modified = false
  return bufnr
end

local function request(bufnr, range, only)
  local responses = vim.lsp.buf_request_sync(bufnr, 'textDocument/codeAction', {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    range = range,
    context = { diagnostics = {}, only = only },
  }, 1000)

  local actions = {}
  for _, response in pairs(responses or {}) do
    vim.list_extend(actions, response.result or {})
  end
  return actions
end

test('converts byte offsets for UTF-8, UTF-16, and CRLF', function()
  local offsets = require('lint_actions.offsets')
  eq({ line = 0, character = 3 }, offsets.to_position('éx\r\ny', 3, 'utf-8'))
  eq({ line = 0, character = 2 }, offsets.to_position('éx\r\ny', 3, 'utf-16'))
  eq({ line = 1, character = 0 }, offsets.to_position('éx\r\ny', 5, 'utf-8'))
end)

test('parses golangci fixes and decodes replacement text', function()
  local path = vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'example.go')
  local lines = { 'package example', '', 'var status = 404' }
  local bufnr = new_buffer(path, lines)
  local text = table.concat(lines, '\n') .. '\n'
  local start = assert(text:find('404', 1, true)) - 1
  local output = vim.json.encode({
    Issues = {
      {
        FromLinter = 'mnd',
        Text = 'magic number: 404',
        Pos = { Filename = 'tests/example.go', Line = 3, Column = 14 },
        SuggestedFixes = {
          {
            Message = 'Use the HTTP status constant',
            TextEdits = {
              { Pos = start, End = start + 3, NewText = vim.base64.encode('http.StatusNotFound') },
            },
          },
        },
      },
    },
  })

  local items = require('lint_actions.adapters.golangci').parse({
    output = output,
    bufnr = bufnr,
    cwd = vim.fn.getcwd(),
    diagnostics = {},
  })

  eq(1, #items)
  eq('Use the HTTP status constant [mnd]', items[1].action.title)
  eq('http.StatusNotFound', items[1].action.edit.documentChanges[1].edits[1].newText)
  eq({ line = 2, character = 13 }, items[1].action.edit.documentChanges[1].edits[1].range.start)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

test('ignores malformed golangci output', function()
  local bufnr = new_buffer(vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'malformed.go'), { 'package malformed' })
  local adapter = require('lint_actions.adapters.golangci')
  eq({}, adapter.parse({ output = '{', bufnr = bufnr, cwd = vim.fn.getcwd() }))
  eq(
    {},
    adapter.parse({
      output = vim.json.encode({ Issues = { 1, { Pos = 2, SuggestedFixes = 'invalid' } } }),
      bufnr = bufnr,
      cwd = vim.fn.getcwd(),
    })
  )
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

test('parses representative golangci-lint v2 output', function()
  local directory = vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'fixtures', 'golangci')
  local path = vim.fs.joinpath(directory, 'playground.go')
  local bufnr = vim.fn.bufadd(path)
  vim.fn.bufload(bufnr)
  local output = table.concat(vim.fn.readfile(vim.fs.joinpath(directory, 'output.json')), '\n')
  local items = require('lint_actions.adapters.golangci').parse({
    output = output,
    bufnr = bufnr,
    cwd = directory,
    diagnostics = {},
  })

  eq(3, #items)
  local by_title = {}
  for _, item in ipairs(items) do
    by_title[item.action.title] = item.action.edit.documentChanges[1].edits
  end
  local error_edits = by_title['Use `%w` to format errors [errorlint]']
  eq('w', error_edits[1].newText)
  vim.lsp.util.apply_text_edits(error_edits, bufnr, 'utf-8')
  eq('\t\treturn fmt.Errorf("fetch failed: %w", err)', vim.api.nvim_buf_get_lines(bufnr, 22, 23, false)[1])
  eq(4, #by_title['Simplify strings.Index call using strings.Cut [modernize]'])
  eq('http.StatusNotFound', by_title['"404" can be replaced by http.StatusNotFound [usestdlibvars]'][1].newText)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

test('publishes native actions, filters them, and rejects stale batches', function()
  local actions = require('lint_actions')
  local path = vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'core.txt')
  local bufnr = new_buffer(path, { 'alpha', 'beta' })
  local uri = vim.uri_from_bufnr(bufnr)
  local range = {
    start = { line = 1, character = 0 },
    ['end'] = { line = 1, character = 4 },
  }

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

  assert(
    vim.wait(1000, function()
      local clients = vim.lsp.get_clients({ bufnr = bufnr, name = 'lint-actions' })
      return clients[1] ~= nil and clients[1].initialized == true
    end),
    'LSP client did not initialize'
  )

  eq(0, #request(bufnr, {
    start = { line = 0, character = 0 },
    ['end'] = { line = 0, character = 1 },
  }))

  local found = request(bufnr, range, { 'source' })
  eq(1, #found)
  eq(1, #request(bufnr, {
    start = { line = 1, character = 4 },
    ['end'] = { line = 1, character = 4 },
  }))
  eq(nil, found[1].edit.changes)
  eq(vim.api.nvim_buf_get_changedtick(bufnr), found[1].edit.documentChanges[1].textDocument.version)
  eq(0, #request(bufnr, range, { 'refactor' }))

  vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { 'changed' })
  eq(0, #request(bufnr, range))
  vim.lsp.util.apply_workspace_edit(found[1].edit, 'utf-8')
  eq('changed', vim.api.nvim_buf_get_lines(bufnr, 1, 2, false)[1])
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

test('keeps sources independent and replaces a source batch', function()
  local store = require('lint_actions.store')
  store._reset()
  local bufnr = new_buffer(vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'store.txt'), { 'text' })
  local range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 4 } }
  local function batch(source, title)
    return {
      bufnr = bufnr,
      uri = vim.uri_from_bufnr(bufnr),
      source = source,
      changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
      version = vim.lsp.util.buf_versions[bufnr],
      items = { { range = range, action = { title = title, kind = 'quickfix' } } },
    }
  end

  store.publish(batch('one', 'old'))
  store.publish(batch('two', 'other'))
  store.publish(batch('one', 'new'))
  eq(
    { 'new', 'other' },
    vim.tbl_map(function(action)
      return action.title
    end, store.actions(bufnr, range))
  )
  store.clear(bufnr, 'one')
  eq('other', store.actions(bufnr, range)[1].title)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

test('treats an empty publish as a source clear', function()
  local actions = require('lint_actions')
  local store = require('lint_actions.store')
  store._reset()
  local bufnr = new_buffer(vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'empty.txt'), { 'text' })
  local range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 4 } }
  local version = vim.lsp.util.buf_versions[bufnr]
  store.publish({
    bufnr = bufnr,
    uri = vim.uri_from_bufnr(bufnr),
    source = 'tool',
    changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
    version = version,
    items = { { range = range, action = { title = 'old' } } },
  })
  actions.publish({ bufnr = bufnr, source = 'tool', items = {} })
  eq(0, #store.actions(bufnr, range))
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

test('nvim-lint integration preserves parser results and wraps once', function()
  local diagnostics = { { lnum = 0, col = 0, message = 'message', source = 'tool' } }
  local calls = 0
  local linter = {
    parser = function(_output, _bufnr, _cwd)
      calls = calls + 1
      return diagnostics
    end,
  }
  local adapter = {
    source = 'tool',
    parse = function()
      return {}
    end,
  }
  local integration = require('lint_actions.integrations.nvim_lint')
  integration.attach({ linter = linter, adapter = adapter })
  local wrapped = linter.parser
  integration.attach({ linter = linter, adapter = adapter })
  eq(wrapped, linter.parser)

  local bufnr = new_buffer(vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'lint.txt'), { 'text' })
  eq(diagnostics, linter.parser('', bufnr, vim.fn.getcwd()))
  eq(1, calls)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

for _, case in ipairs(tests) do
  local ok, err = xpcall(case.callback, debug.traceback)
  if ok then
    print('ok - ' .. case.name)
  else
    failures = failures + 1
    print('not ok - ' .. case.name)
    print(err)
  end
end

if failures > 0 then
  vim.cmd('cquit ' .. failures)
end

vim.cmd('quitall!')
