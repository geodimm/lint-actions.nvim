local MiniTest = require('mini.test')
local adapter = require('lint_actions.adapters.golangci')
local helpers = require('tests.support.nvim')

local eq = helpers.eq
local T = helpers.new_set()

T['parse()'] = MiniTest.new_set()

T['parse()']['decodes fixes into text edits'] = function()
  local path = vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'golangci-decode.go')
  local lines = { 'package example', '', 'var status = 404' }
  local bufnr = helpers.new_buffer(path, lines)
  local text = table.concat(lines, '\n') .. '\n'
  local start = assert(text:find('404', 1, true)) - 1
  local output = vim.json.encode({
    Issues = {
      {
        FromLinter = 'mnd',
        Text = 'magic number: 404',
        Pos = { Filename = 'tests/golangci-decode.go', Line = 3, Column = 14 },
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

  local items = adapter.parse({
    output = output,
    bufnr = bufnr,
    cwd = vim.fn.getcwd(),
    diagnostics = {},
  })

  eq(#items, 1)
  eq(items[1].action.title, 'Use the HTTP status constant [mnd]')
  eq(items[1].action.edit[1].newText, 'http.StatusNotFound')
  eq(items[1].action.edit[1].range.start, { line = 2, character = 13 })
end

T['parse()']['uses matching diagnostic ranges'] = function()
  local path = vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'golangci-diagnostic.go')
  local bufnr = helpers.new_buffer(path, { 'package example' })
  local diagnostic = {
    lnum = 0,
    col = 0,
    end_lnum = 0,
    end_col = 7,
    source = 'tool',
    message = 'message',
  }
  local output = vim.json.encode({
    Issues = {
      {
        FromLinter = 'tool',
        Text = 'message',
        Pos = { Filename = 'tests/golangci-diagnostic.go', Line = 1, Column = 1 },
        SuggestedFixes = {
          { TextEdits = { { Pos = 0, End = 7, NewText = vim.base64.encode('module') } } },
        },
      },
    },
  })

  local items = adapter.parse({ output = output, bufnr = bufnr, cwd = vim.fn.getcwd(), diagnostics = { diagnostic } })
  eq(items[1].range, helpers.range(0, 0, 0, 7))
  eq(items[1].action.title, 'message [tool]')
end

T['parse()']['ignores non-JSON and structurally invalid output'] = function()
  eq(helpers.call(adapter.parse, { output = nil, bufnr = -1 }), {})
  eq(helpers.call(adapter.parse, { output = '', bufnr = -1 }), {})
  eq(helpers.call(adapter.parse, { output = '{', bufnr = -1 }), {})
  eq(helpers.call(adapter.parse, { output = vim.json.encode({}), bufnr = -1 }), {})
  eq(helpers.call(adapter.parse, { output = vim.json.encode({ Issues = 'invalid' }), bufnr = -1 }), {})

  local bufnr = helpers.new_buffer('golangci-malformed.go', { 'package malformed' })
  eq(
    adapter.parse({
      output = vim.json.encode({ Issues = { 1, { Pos = 2, SuggestedFixes = 'invalid' } } }),
      bufnr = bufnr,
      cwd = vim.fn.getcwd(),
    }),
    {}
  )
end

T['parse()']['ignores other files and malformed text edits'] = function()
  local bufnr =
    helpers.new_buffer(vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'golangci-filter.go'), { 'package example' })
  local output = vim.json.encode({
    Issues = {
      {
        Pos = { Filename = 'tests/other.go' },
        SuggestedFixes = { { TextEdits = { { Pos = 0, End = 1, NewText = '' } } } },
      },
      {
        Pos = { Filename = 'tests/golangci-filter.go' },
        SuggestedFixes = {
          { TextEdits = 'invalid' },
          { TextEdits = { false, { Pos = 'zero', End = 1 }, { Pos = 0 } } },
        },
      },
    },
  })

  eq(adapter.parse({ output = output, bufnr = bufnr, cwd = vim.fn.getcwd() }), {})
end

local malformed_edits = {
  { name = 'invalid Base64', edit = { Pos = 0, End = 1, NewText = '!!!' } },
  { name = 'non-string replacement', edit = { Pos = 0, End = 1, NewText = 42 } },
  { name = 'non-table edit', edit = false },
  { name = 'missing start', edit = { End = 1, NewText = '' } },
  { name = 'negative start', edit = { Pos = -1, End = 1, NewText = '' } },
  { name = 'fractional start', edit = { Pos = 0.5, End = 1, NewText = '' } },
  { name = 'fractional end', edit = { Pos = 0, End = 1.5, NewText = '' } },
  { name = 'reversed range', edit = { Pos = 2, End = 1, NewText = '' } },
  { name = 'end outside the buffer', edit = { Pos = 0, End = 99, NewText = '' } },
}

for _, case in ipairs(malformed_edits) do
  T['parse()']['rejects an entire suggestion containing ' .. case.name] = function()
    local bufnr = helpers.new_buffer('golangci-invalid-fix.go', { 'abc' })
    local output = vim.json.encode({
      Issues = {
        {
          Pos = { Filename = vim.api.nvim_buf_get_name(bufnr) },
          SuggestedFixes = {
            {
              Message = 'Broken suggestion',
              TextEdits = {
                { Pos = 3, End = 3, NewText = vim.base64.encode('!') },
                case.edit,
              },
            },
            {
              Message = 'Valid alternative',
              TextEdits = {
                { Pos = 0, End = 3, NewText = vim.base64.encode('xyz') },
              },
            },
          },
        },
      },
    })
    local parsed = adapter.parse({ bufnr = bufnr, output = output, cwd = vim.fn.getcwd() })
    eq(#parsed, 1)
    eq(parsed[1].action.title, 'Valid alternative')
    vim.lsp.util.apply_text_edits(parsed[1].action.edit, bufnr, 'utf-8')
    eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { 'xyz' })
  end
end

T['parse()']['preserves empty and null deletions and insertions at EOF'] = function()
  local bufnr = helpers.new_buffer('golangci-valid-boundaries.go', { 'abc' })
  vim.bo[bufnr].endofline = false
  local output = vim.json.encode({
    Issues = {
      {
        Pos = { Filename = vim.api.nvim_buf_get_name(bufnr) },
        SuggestedFixes = {
          {
            TextEdits = {
              { Pos = 0, End = 1, NewText = '' },
              { Pos = 1, End = 2, NewText = vim.NIL },
              { Pos = 3, End = 3, NewText = vim.base64.encode('!') },
            },
          },
        },
      },
    },
  })
  local parsed = adapter.parse({ bufnr = bufnr, output = output, cwd = vim.fn.getcwd() })
  eq(#parsed, 1)
  eq(#parsed[1].action.edit, 3)
  vim.lsp.util.apply_text_edits(parsed[1].action.edit, bufnr, 'utf-8')
  eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { 'c!' })
end

return T
