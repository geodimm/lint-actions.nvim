local MiniTest = require('mini.test')
local adapter = require('lint_actions.adapters.sarif')
local helpers = require('tests.helpers')

local eq = helpers.eq
local T = MiniTest.new_set()

local function region(start_line, start_column, end_line, end_column)
  return {
    startLine = start_line,
    startColumn = start_column,
    endLine = end_line,
    endColumn = end_column,
  }
end

local function replacement(deleted_region, text)
  local value = { deletedRegion = deleted_region }
  if text ~= nil then
    value.insertedContent = { text = text }
  end
  return value
end

local function change(uri, replacements)
  return {
    artifactLocation = type(uri) == 'table' and uri or { uri = uri },
    replacements = replacements,
  }
end

local function fix(description, changes)
  return {
    description = description and { text = description } or nil,
    artifactChanges = changes,
  }
end

local function location(uri, value)
  return {
    physicalLocation = {
      artifactLocation = type(uri) == 'table' and uri or { uri = uri },
      region = value,
    },
  }
end

local function output(run)
  run.tool = run.tool or { driver = { name = 'example' } }
  return vim.json.encode({ version = '2.1.0', runs = { run } })
end

local function parse(bufnr, run)
  return adapter.parse({ output = output(run), bufnr = bufnr, cwd = vim.fn.getcwd() })
end

local function apply(action)
  for uri, edits in pairs(action.edit.changes) do
    vim.lsp.util.apply_text_edits(edits, vim.uri_to_bufnr(uri), 'utf-8')
  end
end

T['parse()'] = MiniTest.new_set()

T['parse()']['creates a quick fix from a described SARIF fix'] = function()
  local name = 'sarif-basic.lua'
  local bufnr = helpers.new_buffer(name, { 'local bad = true' })
  local items = parse(bufnr, {
    columnKind = 'unicodeCodePoints',
    results = {
      {
        ruleId = 'prefer-good',
        message = { text = 'Use a better name.' },
        locations = { location(name, region(1, 7, 1, 10)) },
        fixes = { fix('Rename the variable.', { change(name, { replacement(region(1, 7, 1, 10), 'good') }) }) },
      },
    },
  })

  eq(#items, 1)
  eq(items[1].range, helpers.range(0, 6, 0, 9))
  eq(items[1].action.title, 'Rename the variable. [prefer-good]')
  eq(items[1].action.kind, 'quickfix')
  apply(items[1].action)
  eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { 'local good = true' })
end

T['parse()']['keeps alternative fixes as separate actions'] = function()
  local name = 'sarif-alternatives.lua'
  local bufnr = helpers.new_buffer(name, { 'bad()' })
  local items = parse(bufnr, {
    columnKind = 'utf16CodeUnits',
    results = {
      {
        ruleId = 'call',
        message = { text = 'Choose a replacement.' },
        locations = { location(name, region(1, 1, 1, 4)) },
        fixes = {
          fix('Use good.', { change(name, { replacement(region(1, 1, 1, 4), 'good') }) }),
          fix('Use best.', { change(name, { replacement(region(1, 1, 1, 4), 'best') }) }),
        },
      },
    },
  })

  eq(#items, 2)
  eq(items[1].action.title, 'Use good. [call]')
  eq(items[2].action.title, 'Use best. [call]')
end

T['parse()']['converts both SARIF column units to UTF-8 positions'] = function()
  for _, case in ipairs({
    { kind = 'utf16CodeUnits', start_column = 4, end_column = 7 },
    { kind = 'unicodeCodePoints', start_column = 3, end_column = 6 },
  }) do
    local name = 'sarif-' .. case.kind .. '.lua'
    local bufnr = helpers.new_buffer(name, { '😀 bad' })
    local edit_region = region(1, case.start_column, 1, case.end_column)
    local items = parse(bufnr, {
      columnKind = case.kind,
      results = {
        {
          locations = { location(name, edit_region) },
          fixes = { fix(nil, { change(name, { replacement(edit_region, 'good') }) }) },
        },
      },
    })

    eq(items[1].action.edit.changes[vim.uri_from_bufnr(bufnr)][1].range, helpers.range(0, 5, 0, 8))
    apply(items[1].action)
    eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { '😀 good' })
  end
end

T['parse()']['supports character offsets and DOS newline sequences'] = function()
  local name = 'sarif-character-offset.lua'
  local bufnr = helpers.new_buffer(name, { 'a', '😀bad' })
  vim.bo[bufnr].fileformat = 'dos'
  vim.bo[bufnr].endofline = true
  local items = parse(bufnr, {
    columnKind = 'unicodeCodePoints',
    results = {
      {
        locations = { location(name, region(2, 1, 2, 5)) },
        fixes = {
          fix(nil, {
            change(name, { replacement({ charOffset = 4, charLength = 3 }, 'good') }),
          }),
        },
      },
    },
  })

  eq(items[1].action.edit.changes[vim.uri_from_bufnr(bufnr)][1].range, helpers.range(1, 4, 1, 7))
  apply(items[1].action)
  eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { 'a', '😀good' })
end

T['parse()']['applies ordered replacements as one edit'] = function()
  local name = 'sarif-ordered.lua'
  local bufnr = helpers.new_buffer(name, { 'value' })
  local items = parse(bufnr, {
    columnKind = 'unicodeCodePoints',
    results = {
      {
        locations = { location(name, region(1, 1, 1, 6)) },
        fixes = {
          fix('Wrap and rename.', {
            change(name, {
              replacement(region(1, 1, 1, 6), 'item'),
              replacement(region(1, 1, 1, 1), '['),
              replacement(region(1, 6, 1, 6), ']'),
            }),
          }),
        },
      },
    },
  })

  -- The insertion points touch the replacement boundaries but do not overlap it.
  eq(#items, 1)
  eq(#items[1].action.edit.changes[vim.uri_from_bufnr(bufnr)], 1)
  apply(items[1].action)
  eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { '[item]' })
end

T['parse()']['resolves URI bases, escaped paths, and artifact indices'] = function()
  local name = 'sarif-fixtures/sarif escaped.lua'
  local bufnr = helpers.new_buffer(name, { 'bad' })
  local base = vim.uri_from_fname(vim.fn.getcwd()) .. '/'
  local indexed = { index = 0 }
  local items = parse(bufnr, {
    columnKind = 'unicodeCodePoints',
    originalUriBaseIds = {
      ROOT = { uri = base },
      SOURCE = { uri = 'sarif-fixtures/', uriBaseId = 'ROOT' },
    },
    artifacts = { { location = { uri = 'sarif%20escaped.lua', uriBaseId = 'SOURCE' } } },
    results = {
      {
        locations = { location(indexed, region(1, 1, 1, 4)) },
        fixes = { fix('Resolve it.', { change(indexed, { replacement(region(1, 1, 1, 4), 'good') }) }) },
      },
    },
  })

  eq(#items, 1)
  apply(items[1].action)
  eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { 'good' })
end

T['parse()']['creates one workspace edit for a multi-artifact fix'] = function()
  local first_name = 'sarif-first.lua'
  local second_name = 'sarif-second.lua'
  local first = helpers.new_buffer(first_name, { 'one' })
  local second = helpers.new_buffer(second_name, { 'two' })
  local items = parse(first, {
    columnKind = 'unicodeCodePoints',
    results = {
      {
        locations = { location(first_name, region(1, 1, 1, 4)) },
        fixes = {
          fix('Update both files.', {
            change(first_name, { replacement(region(1, 1, 1, 4), 'ONE') }),
            change(second_name, { replacement(region(1, 1, 1, 4), 'TWO') }),
          }),
        },
      },
    },
  })

  eq(vim.tbl_count(items[1].action.edit.changes), 2)
  apply(items[1].action)
  eq(vim.api.nvim_buf_get_lines(first, 0, -1, false), { 'ONE' })
  eq(vim.api.nvim_buf_get_lines(second, 0, -1, false), { 'TWO' })
end

T['parse()']['offers a locationless result only to a buffer changed by the fix'] = function()
  local name = 'sarif-locationless.lua'
  local bufnr = helpers.new_buffer(name, { 'bad' })
  local items = parse(bufnr, {
    columnKind = 'unicodeCodePoints',
    results = {
      {
        message = { text = 'No physical result location.' },
        fixes = { fix(nil, { change(name, { replacement(region(1, 1, 1, 4), 'good') }) }) },
      },
    },
  })

  eq(#items, 1)
  eq(items[1].range, nil)
  eq(items[1].action.title, 'Fix: No physical result location.')
end

T['parse()']['drops a multi-artifact fix when another loaded buffer is modified'] = function()
  local first_name = 'sarif-stale-first.lua'
  local second_name = 'sarif-stale-second.lua'
  local first = helpers.new_buffer(first_name, { 'one' })
  local second = helpers.new_buffer(second_name, { 'two' })
  vim.bo[second].modified = true

  local items = parse(first, {
    columnKind = 'unicodeCodePoints',
    results = {
      {
        locations = { location(first_name, region(1, 1, 1, 4)) },
        fixes = {
          fix('Update both files.', {
            change(first_name, { replacement(region(1, 1, 1, 4), 'ONE') }),
            change(second_name, { replacement(region(1, 1, 1, 4), 'TWO') }),
          }),
        },
      },
    },
  })

  eq(items, {})
end

T['parse()']['drops incomplete, binary, overlapping, remote, and unrelated fixes'] = function()
  local name = 'sarif-invalid.lua'
  local bufnr = helpers.new_buffer(name, { 'bad' })
  local other = 'sarif-other.lua'
  local valid_region = region(1, 1, 1, 4)
  local binary = replacement(valid_region, 'ignored')
  binary.insertedContent = { binary = 'aWdub3JlZA==' }
  local items = parse(bufnr, {
    columnKind = 'unicodeCodePoints',
    results = {
      {
        locations = { location(name, valid_region) },
        fixes = {
          fix(nil, { change(name, { { insertedContent = { text = 'missing region' } } }) }),
          fix(nil, { change(name, { binary }) }),
          fix(nil, {
            change(name, {
              replacement(region(1, 1, 1, 3), 'x'),
              replacement(region(1, 2, 1, 4), 'y'),
            }),
          }),
          fix(nil, { change('https://example.test/file.lua', { replacement(valid_region, 'remote') }) }),
        },
      },
      {
        locations = { location(other, valid_region) },
        fixes = { fix(nil, { change(other, { replacement(valid_region, 'other') }) }) },
      },
    },
  })

  eq(items, {})
end

T['parse()']['ignores empty, malformed, and fixless output'] = function()
  local bufnr = helpers.new_buffer('sarif-empty.lua', { 'text' })
  local context = { bufnr = bufnr, cwd = vim.fn.getcwd() }

  eq(adapter.parse(vim.tbl_extend('force', context, { output = '' })), {})
  eq(adapter.parse(vim.tbl_extend('force', context, { output = '{' })), {})
  eq(adapter.parse(vim.tbl_extend('force', context, { output = '{}' })), {})
  eq(adapter.parse(vim.tbl_extend('force', context, { output = output({ results = {} }) })), {})
  eq(adapter.parse({ output = output({ results = {} }), bufnr = -1, cwd = vim.fn.getcwd() }), {})
end

return T
