local MiniTest = require('mini.test')
local adapter = require('lint_actions.adapters.shellcheck')
local helpers = require('tests.helpers')
local integration = require('lint_actions.integrations.shellcheck')
local store = require('lint_actions.store')

local eq = helpers.eq
local expect_error = helpers.expect_error
local T = MiniTest.new_set()

---@param options table
local function replacement(options)
  return {
    line = options.line or 1,
    endLine = options.end_line or options.line or 1,
    column = options.column,
    endColumn = options.end_column or options.column,
    precedence = options.precedence or 1,
    insertionPoint = options.before and 'beforeStart' or 'afterEnd',
    replacement = options.text or '',
  }
end

---@param options table
local function comment(options)
  options = options or {}
  return {
    file = options.file or '-',
    line = options.line or 1,
    endLine = options.end_line or options.line or 1,
    column = options.column or 1,
    endColumn = options.end_column or options.column or 1,
    level = 'warning',
    code = options.code or 2086,
    message = options.message or 'Double quote to prevent globbing and word splitting.',
    fix = options.replacements and { replacements = options.replacements } or vim.NIL,
  }
end

local function output(comments)
  return vim.json.encode({ comments = comments })
end

local function apply(action, bufnr)
  local edits = action.edit.range and { action.edit } or action.edit
  vim.lsp.util.apply_text_edits(edits, bufnr, 'utf-8')
end

local function linter()
  return {
    args = { '--format', 'json1', '-' },
    parser = function(_, _, _)
      return {}
    end,
  }
end

T['parse()'] = MiniTest.new_set()

T['parse()']['quotes an expansion with both halves of one fix'] = function()
  local bufnr = helpers.new_buffer('shellcheck-quickfix.sh', { 'cd $1' })
  local items = adapter.parse({
    output = output({
      comment({
        column = 4,
        end_column = 6,
        replacements = {
          replacement({ column = 4, text = '"', before = false }),
          replacement({ column = 6, text = '"', before = true }),
        },
      }),
    }),
    bufnr = bufnr,
    cwd = vim.fn.getcwd(),
  })

  eq(#items, 2)
  eq(items[1].range, helpers.range(0, 3, 0, 5))
  eq(items[1].action.title, 'Fix SC2086: Double quote to prevent globbing and word splitting.')
  eq(items[1].action.kind, 'quickfix')
  eq(items[1].action.isPreferred, true)
  eq(items[1].action.edit.range, helpers.range(0, 3, 0, 5))
  apply(items[1].action, bufnr)
  eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { 'cd "$1"' })
end

T['parse()']['orders replacements at one point by precedence'] = function()
  local bufnr = helpers.new_buffer('shellcheck-precedence.sh', { '`x`' })
  local items = adapter.parse({
    output = output({
      comment({
        code = 2006,
        message = 'Use $(...) notation instead of legacy backticks.',
        end_column = 4,
        replacements = {
          replacement({ column = 1, end_column = 2, text = '$(', precedence = 2 }),
          replacement({ column = 3, end_column = 4, text = ')', precedence = 2, before = true }),
          replacement({ column = 1, text = '"', precedence = 1 }),
          replacement({ column = 4, text = '"', precedence = 1, before = true }),
        },
      }),
    }),
    bufnr = bufnr,
    cwd = vim.fn.getcwd(),
  })

  eq(items[1].action.title, 'Fix SC2006: Use $(...) notation instead of legacy backticks.')
  apply(items[1].action, bufnr)
  eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { '"$(x)"' })
end

T['parse()']['rewrites a fix that spans several lines'] = function()
  local bufnr = helpers.new_buffer('shellcheck-multiline.sh', { 'if [ a', 'b ]; then', 'true', 'fi' })
  local items = adapter.parse({
    output = output({
      comment({
        code = 2166,
        message = 'Prefer [ p ] && [ q ].',
        end_line = 2,
        end_column = 4,
        replacements = { replacement({ line = 1, column = 4, end_line = 2, end_column = 4, text = '[[ a b ]]' }) },
      }),
    }),
    bufnr = bufnr,
    cwd = vim.fn.getcwd(),
  })

  eq(items[1].action.edit.range, helpers.range(0, 3, 1, 3))
  apply(items[1].action, bufnr)
  eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { 'if [[ a b ]]; then', 'true', 'fi' })
end

T['parse()']['converts character columns into byte positions'] = function()
  local bufnr = helpers.new_buffer('shellcheck-unicode.sh', { 'echo 😀 $x' })
  local items = adapter.parse({
    output = output({
      comment({
        column = 8,
        end_column = 10,
        replacements = {
          replacement({ column = 8, text = '"' }),
          replacement({ column = 10, text = '"', before = true }),
        },
      }),
    }),
    bufnr = bufnr,
    cwd = vim.fn.getcwd(),
  })

  eq(items[1].action.edit.range, helpers.range(0, 10, 0, 12))
  apply(items[1].action, bufnr)
  eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { 'echo 😀 "$x"' })
end

T['parse()']['builds a whole-file fix that drops colliding fixes'] = function()
  local bufnr = helpers.new_buffer('shellcheck-fix-all.sh', { 'cd $1', 'rm $2' })
  local items = adapter.parse({
    output = output({
      comment({
        column = 4,
        end_column = 6,
        replacements = { replacement({ column = 4, end_column = 6, text = '"$1"' }) },
      }),
      comment({
        code = 2248,
        message = 'Prefer explicit quoting.',
        column = 4,
        end_column = 6,
        replacements = { replacement({ column = 4, end_column = 6, text = '${1}' }) },
      }),
      comment({
        line = 2,
        column = 4,
        end_column = 6,
        replacements = {
          replacement({ line = 2, column = 4, text = '"' }),
          replacement({ line = 2, column = 6, text = '"', before = true }),
        },
      }),
    }),
    bufnr = bufnr,
    cwd = vim.fn.getcwd(),
  })

  eq(#items, 4)
  local fix_all = items[4].action
  eq(fix_all.title, 'Fix all shellcheck issues')
  eq(fix_all.kind, 'source.fixAll.shellcheck')
  apply(fix_all, bufnr)
  eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { 'cd "$1"', 'rm "$2"' })
end

T['parse()']['ignores comments about other files'] = function()
  local bufnr = helpers.new_buffer('shellcheck-sourced.sh', { 'cd $1' })
  local items = adapter.parse({
    output = output({
      comment({
        file = vim.fs.joinpath(vim.fn.getcwd(), 'lib.sh'),
        column = 4,
        end_column = 6,
        replacements = { replacement({ column = 4, end_column = 6, text = '"$1"' }) },
      }),
    }),
    bufnr = bufnr,
    cwd = vim.fn.getcwd(),
  })

  eq(items, {})
end

T['parse()']['skips a fix whose replacements cannot all be resolved'] = function()
  local bufnr = helpers.new_buffer('shellcheck-partial.sh', { 'cd $1' })
  local items = adapter.parse({
    output = output({
      comment({
        column = 4,
        end_column = 6,
        replacements = {
          replacement({ column = 4, text = '"' }),
          replacement({ line = 9, column = 1, text = '"' }),
        },
      }),
    }),
    bufnr = bufnr,
    cwd = vim.fn.getcwd(),
  })

  eq(items, {})
end

T['parse()']['ignores empty, invalid, and fixless output'] = function()
  local bufnr = helpers.new_buffer('shellcheck-invalid.sh', { 'cd $1' })
  local context = { bufnr = bufnr, cwd = vim.fn.getcwd() }

  eq(adapter.parse(vim.tbl_extend('force', context, { output = '' })), {})
  eq(adapter.parse(vim.tbl_extend('force', context, { output = '{' })), {})
  eq(adapter.parse(vim.tbl_extend('force', context, { output = '[]' })), {})
  eq(adapter.parse(vim.tbl_extend('force', context, { output = output({ comment({}) }) })), {})
  eq(adapter.parse({ output = output({ comment({}) }), bufnr = -1, cwd = vim.fn.getcwd() }), {})
end

T['parse()']['handles representative shellcheck json1 output'] = function()
  local bufnr = helpers.fixture_buffer('shellcheck', 'playground.sh')
  local items = adapter.parse({
    output = helpers.fixture_text('shellcheck', 'output.json'),
    bufnr = bufnr,
    cwd = vim.fs.dirname(helpers.fixture_path('shellcheck', 'playground.sh')),
  })

  -- Four of the five findings carry a fix; SC2166 has none.
  eq(#items, 5)
  eq(items[1].action.title, "Fix SC2164: Use 'cd ... || exit' or 'cd ... || return' in case cd fails.")

  local fix_all = items[#items].action
  eq(fix_all.kind, 'source.fixAll.shellcheck')
  apply(fix_all, bufnr)
  eq(helpers.written_text(bufnr), helpers.fixture_text('shellcheck', 'fixed.sh'))
end

T['integration.attach()'] = MiniTest.new_set({
  hooks = { pre_case = store._reset, post_case = store._reset },
})

T['integration.attach()']['publishes actions from a concrete linter'] = function()
  helpers.mock_nvim_lint({})
  local definition = linter()
  integration.attach({ linter = definition })
  local wrapped = definition.parser
  integration.attach({ linter = definition })

  eq(definition.args, { '--format', 'json1', '-' })
  eq(definition.parser, wrapped)
  local bufnr = helpers.new_buffer('shellcheck-integration.sh', { 'cd $1' })
  local diagnostics = definition.parser(
    output({
      comment({
        column = 4,
        end_column = 6,
        replacements = { replacement({ column = 4, end_column = 6, text = '"$1"' }) },
      }),
    }),
    bufnr,
    vim.fn.getcwd()
  )

  eq(diagnostics, {})
  eq(#store.actions(bufnr, helpers.range(0, 0, 0, 0)), 2)
end

T['integration.attach()']['resolves factory linters by name once'] = function()
  local lint = helpers.mock_nvim_lint({
    shellcheck = function()
      return linter()
    end,
  })
  integration.attach()
  local factory = lint.linters.shellcheck
  integration.attach()

  eq(lint.linters.shellcheck, factory)
  eq(factory()._lint_actions_attached, 'shellcheck')
end

T['integration.attach()']['rejects invalid options and linter definitions'] = function()
  expect_error('options', function()
    helpers.call(integration.attach, false)
  end)
  expect_error('options.linter must be a linter name or table', function()
    helpers.call(integration.attach, { linter = false })
  end)
  expect_error('source', function()
    helpers.call(integration.attach, { linter = linter(), source = false })
  end)
  helpers.mock_nvim_lint({})
  expect_error('unknown nvim-lint linter: missing', function()
    helpers.call(integration.attach, { linter = 'missing' })
  end)
end

return T
