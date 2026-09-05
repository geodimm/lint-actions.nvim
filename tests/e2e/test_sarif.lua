local MiniTest = require('mini.test')
local adapter = require('lint_actions.adapters.sarif')
local helpers = require('tests.support.lsp')

local eq = helpers.eq
local T = helpers.new_set()

local sarif = require('tests.support.sarif')
local region, replacement, change = sarif.region, sarif.replacement, sarif.change
local fix, location, output = sarif.fix, sarif.location, sarif.output

local function ingest(bufnr, run)
  require('lint_actions').ingest({
    adapter = adapter,
    output = output(run),
    bufnr = bufnr,
    cwd = vim.fn.getcwd(),
  })
end

T['SARIF fixes'] = MiniTest.new_set()

T['SARIF fixes']['ingests, filters, sorts, and applies Unicode alternatives'] = function()
  local name = 'sarif-pipeline-unicode.lua'
  local bufnr = helpers.new_buffer(name, { '-- example', '😀 bad' })
  local edit_region = region(2, 4, 2, 7)
  ingest(bufnr, {
    columnKind = 'utf16CodeUnits',
    results = {
      {
        locations = { location(name, edit_region) },
        fixes = {
          fix('Use good.', { change(name, { replacement(edit_region, 'good') }) }),
          fix('Use best.', { change(name, { replacement(edit_region, 'best') }) }),
        },
      },
    },
  })
  local range = helpers.range(1, 0, 1, 0)
  eq(helpers.request(bufnr, helpers.range(0, 0, 0, 0)), {})
  eq(helpers.request(bufnr, range, { 'refactor' }), {})
  local found = helpers.request(bufnr, range, { 'quickfix' })
  eq(
    vim.tbl_map(function(action)
      return action.title
    end, found),
    { 'Use best.', 'Use good.' }
  )
  local changes = found[1].edit.documentChanges
  eq(found[1].edit.changes, nil)
  eq(changes[1].textDocument.version, vim.api.nvim_buf_get_changedtick(bufnr))
  vim.lsp.util.apply_workspace_edit(found[1].edit, 'utf-8')
  eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { '-- example', '😀 best' })
  eq(helpers.request(bufnr, range), {})
end

for _, update_primary in ipairs({ false, true }) do
  local target = update_primary and 'both artifacts' or 'only a secondary artifact'
  T['SARIF fixes']['ingests and applies a fix targeting ' .. target] = function()
    local primary_name, secondary_name = 'sarif-pipeline-primary.lua', 'sarif-pipeline-secondary.lua'
    local primary = helpers.new_buffer(primary_name, { 'one' })
    local secondary = helpers.new_buffer(secondary_name, { 'two' })
    local edit_region = region(1, 1, 1, 4)
    local changes = { change(secondary_name, { replacement(edit_region, 'TWO') }) }
    if update_primary then
      table.insert(changes, change(primary_name, { replacement(edit_region, 'ONE') }))
    end
    ingest(primary, {
      columnKind = 'unicodeCodePoints',
      results = {
        {
          locations = { location(primary_name, edit_region) },
          fixes = { fix('Update artifacts.', changes) },
        },
      },
    })
    local found = helpers.request(primary, helpers.range(0, 0, 0, 0))
    eq(#found, 1)
    eq(found[1].edit.changes, nil)
    eq(#found[1].edit.documentChanges, update_primary and 2 or 1)
    vim.lsp.util.apply_workspace_edit(found[1].edit, 'utf-8')
    eq(vim.api.nvim_buf_get_lines(primary, 0, -1, false), { update_primary and 'ONE' or 'one' })
    eq(vim.api.nvim_buf_get_lines(secondary, 0, -1, false), { 'TWO' })
  end
end

return T
