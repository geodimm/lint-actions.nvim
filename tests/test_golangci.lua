local MiniTest = require('mini.test')
local adapter = require('lint_actions.adapters.golangci')
local helpers = require('tests.helpers')
local integration = require('lint_actions.integrations.golangci')

local eq = helpers.eq
local expect_error = helpers.expect_error
local T = MiniTest.new_set()

local function linter()
  return {
    parser = function(_, _, _)
      return {}
    end,
  }
end

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

T['parse()']['handles representative golangci-lint v2 output'] = function()
  local bufnr = helpers.fixture_buffer('golangci', 'playground.go')
  local items = adapter.parse({
    output = helpers.fixture_text('golangci', 'output.json'),
    bufnr = bufnr,
    cwd = vim.fs.dirname(helpers.fixture_path('golangci', 'playground.go')),
    diagnostics = {},
  })

  eq(#items, 3)
  local by_title = {}
  for _, item in ipairs(items) do
    by_title[item.action.title] = item.action.edit
  end
  local error_edits = by_title['Use `%w` to format errors [errorlint]']
  eq(error_edits[1].newText, 'w')
  vim.lsp.util.apply_text_edits(error_edits, bufnr, 'utf-8')
  eq(vim.api.nvim_buf_get_lines(bufnr, 22, 23, false)[1], '\t\treturn fmt.Errorf("fetch failed: %w", err)')
  eq(#by_title['Simplify strings.Index call using strings.Cut [modernize]'], 4)
  eq(by_title['"404" can be replaced by http.StatusNotFound [usestdlibvars]'][1].newText, 'http.StatusNotFound')
end

T['integration.attach()'] = MiniTest.new_set()

T['integration.attach()']['uses the default nvim-lint linter and bundled adapter'] = function()
  local definition = linter()
  helpers.mock_nvim_lint({ golangcilint = definition })

  integration.attach()
  local wrapped = definition.parser
  integration.attach()

  eq(definition._lint_actions_attached, 'golangci-lint')
  eq(definition.parser, wrapped)
end

T['integration.attach()']['accepts a concrete linter and source override'] = function()
  helpers.mock_nvim_lint({})
  local definition = linter()
  integration.attach({ linter = definition, source = 'custom-golangci' })
  eq(definition._lint_actions_attached, 'custom-golangci')
end

T['integration.attach()']['rejects invalid options'] = function()
  expect_error('options', function()
    helpers.call(integration.attach, false)
  end)
  expect_error('options.linter must be a linter name or table', function()
    helpers.call(integration.attach, { linter = false })
  end)
  expect_error('source', function()
    helpers.call(integration.attach, { linter = linter(), source = false })
  end)
end

return T
