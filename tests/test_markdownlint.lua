local MiniTest = require('mini.test')
local adapter = require('lint_actions.adapters.markdownlint')
local helpers = require('tests.helpers')

local eq = helpers.eq
local T = MiniTest.new_set()

local function issue(options)
  options = options or {}
  return {
    fileName = 'stdin',
    lineNumber = options.line_number or 1,
    ruleNames = options.rule_names or { 'MD018', 'no-missing-space-atx' },
    ruleDescription = options.description or 'No space after hash on atx style heading',
    ruleInformation = 'https://example.test/rule',
    errorDetail = options.detail,
    errorContext = options.context,
    errorRange = options.range,
    fixInfo = options.fix,
    severity = 'error',
  }
end

local function output(issues)
  return vim.json.encode(issues)
end

local function apply(action, bufnr)
  local edits = action.edit.range and { action.edit } or action.edit
  vim.lsp.util.apply_text_edits(edits, bufnr, 'utf-8')
end

T['diagnostics()'] = MiniTest.new_set()

T['diagnostics()']['parses messages, codes, and UTF-16 ranges'] = function()
  local bufnr = helpers.new_buffer('markdownlint-diagnostics.md', { '😀#Title' })
  local diagnostics = adapter.diagnostics(
    output({
      issue({
        range = { 3, 2 },
        detail = 'Expected: 1; Actual: 0',
        context = '😀#Title',
      }),
    }),
    bufnr
  )

  eq(#diagnostics, 1)
  eq(diagnostics[1].lnum, 0)
  eq(diagnostics[1].col, 4)
  eq(diagnostics[1].end_col, 6)
  eq(diagnostics[1].code, 'MD018')
  eq(
    diagnostics[1].message,
    'MD018/no-missing-space-atx No space after hash on atx style heading '
      .. '[Expected: 1; Actual: 0] [Context: "😀#Title"]'
  )
  eq(diagnostics[1].severity, vim.diagnostic.severity.WARN)
end

T['diagnostics()']['ignores empty, invalid, and non-array output'] = function()
  local bufnr = helpers.new_buffer('markdownlint-invalid.md', { '# Heading' })
  eq(adapter.diagnostics('', bufnr), {})
  eq(adapter.diagnostics('{', bufnr), {})
  eq(adapter.diagnostics('{}', bufnr), {})
  eq(adapter.diagnostics('[]', -1), {})
end

T['parse()'] = MiniTest.new_set()

T['parse()']['creates a quick fix for one diagnostic'] = function()
  local bufnr = helpers.new_buffer('markdownlint-quickfix.md', { '#Title' })
  local items = adapter.parse({
    output = output({ issue({ range = { 1, 2 }, fix = { editColumn = 2, insertText = ' ' } }) }),
    bufnr = bufnr,
    cwd = vim.fn.getcwd(),
  })

  eq(#items, 2)
  eq(items[1].range, helpers.range(0, 0, 0, 2))
  eq(items[1].action.title, 'Fix MD018: No space after hash on atx style heading')
  eq(items[1].action.kind, 'quickfix')
  eq(items[1].action.isPreferred, true)
  apply(items[1].action, bufnr)
  eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { '# Title' })
end

T['parse()']['creates a whole-file fix with markdownlint overlap handling'] = function()
  local bufnr = helpers.new_buffer('markdownlint-fix-all.md', { 'bad', 'remove me' })
  local issues = {
    issue({
      description = 'Insert replacement',
      range = { 1, 3 },
      fix = { editColumn = 1, insertText = 'good' },
    }),
    issue({
      description = 'Delete old text',
      range = { 1, 3 },
      fix = { editColumn = 1, deleteCount = 3 },
    }),
    issue({
      line_number = 2,
      rule_names = { 'MD053', 'link-image-reference-definitions' },
      description = 'Unused link definition',
      fix = { deleteCount = -1 },
    }),
  }
  local items = adapter.parse({ output = output(issues), bufnr = bufnr, cwd = vim.fn.getcwd() })

  eq(#items, 4)
  local fix_all = items[4].action
  eq(fix_all.title, 'Fix all markdownlint issues')
  eq(fix_all.kind, 'source.fixAll.markdownlint')
  apply(fix_all, bufnr)
  eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { 'good' })
end

T['parse()']['targets UTF-16 fix columns with UTF-8 LSP positions'] = function()
  local bufnr = helpers.new_buffer('markdownlint-unicode.md', { '😀bad' })
  local items = adapter.parse({
    output = output({ issue({ fix = { editColumn = 3, deleteCount = 3, insertText = 'good' } }) }),
    bufnr = bufnr,
    cwd = vim.fn.getcwd(),
  })

  eq(items[1].action.edit.range, helpers.range(0, 4, 0, 7))
  apply(items[1].action, bufnr)
  eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { '😀good' })
end

T['parse()']['omits malformed and non-fixable issues'] = function()
  local bufnr = helpers.new_buffer('markdownlint-nonfixable.md', { '# Heading' })
  eq(
    adapter.parse({
      output = output({
        issue(),
        issue({ fix = { editColumn = 'first' } }),
        issue({ fix = { lineNumber = 20, editColumn = 1 } }),
      }),
      bufnr = bufnr,
      cwd = vim.fn.getcwd(),
    }),
    {}
  )
  eq(adapter.parse({ output = '{', bufnr = bufnr, cwd = vim.fn.getcwd() }), {})
  eq(adapter.parse({ output = '[]', bufnr = -1, cwd = vim.fn.getcwd() }), {})
end

T['parse()']['handles representative markdownlint JSON output'] = function()
  local bufnr = helpers.fixture_buffer('markdownlint', 'playground.md')
  local items = adapter.parse({
    output = helpers.fixture_text('markdownlint', 'output.json'),
    bufnr = bufnr,
    cwd = vim.fs.dirname(helpers.fixture_path('markdownlint', 'playground.md')),
  })

  -- Six of the eight findings carry fixInfo; MD041 and MD013 have none.
  eq(#items, 7)
  eq(items[1].action.title, 'Fix MD018: No space after hash on atx style heading')

  local fix_all = items[#items].action
  eq(fix_all.kind, 'source.fixAll.markdownlint')
  apply(fix_all, bufnr)
  eq(helpers.written_text(bufnr), helpers.fixture_text('markdownlint', 'fixed.md'))
end

return T
