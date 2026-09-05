local MiniTest = require('mini.test')
local helpers = require('tests.helpers')
local items = require('lint_actions.items')
local eq, range = helpers.eq, helpers.range
local T = MiniTest.new_set()

T['matching by line'] = MiniTest.new_set()

-- Matching is inclusive at both ends and ignores columns, including cursors.
for _, case in ipairs({
  { name = 'before', request = range(0, 0, 1, 0), matches = false },
  { name = 'touching the start', request = range(0, 0, 2, 0), matches = true },
  { name = 'inside', request = range(3, 99, 3, 99), matches = true },
  { name = 'touching the end', request = range(4, 99, 6, 0), matches = true },
  { name = 'containing the item', request = range(0, 0, 6, 0), matches = true },
  { name = 'after', request = range(5, 0, 6, 0), matches = false },
}) do
  T['matching by line'][case.name] = function()
    local candidate = { range = range(2, 10, 4, 20), action = { title = 'Fix' } }
    local original = vim.deepcopy({ candidate, case.request })
    eq(items.matches(candidate, case.request), case.matches)
    eq(items.matches({ range = case.request, action = candidate.action }, candidate.range), case.matches)
    eq({ candidate, case.request }, original)
  end
end

T['matching by kind'] = MiniTest.new_set()
for _, case in ipairs({
  { name = 'no filter accepts a kindless action', matches = true },
  { name = 'empty filter accepts a kindless action', only = {}, matches = true },
  { name = 'a filter excludes a kindless action', only = { 'quickfix' }, matches = false },
  { name = 'exact kind', kind = 'quickfix', only = { 'quickfix' }, matches = true },
  { name = 'descendant kind', kind = 'source.fixAll.tool', only = { 'source' }, matches = true },
  { name = 'any requested kind', kind = 'source.fixAll', only = { 'quickfix', 'source' }, matches = true },
  { name = 'ancestor is not a descendant', kind = 'source', only = { 'source.fixAll' }, matches = false },
  { name = 'prefix needs a dot boundary', kind = 'source.fixAllExtra', only = { 'source.fixAll' }, matches = false },
  { name = 'unrelated kinds', kind = 'refactor', only = { 'quickfix' }, matches = false },
}) do
  T['matching by kind'][case.name] = function()
    local candidate = { range = range(0, 0, 0, 0), action = { title = 'Fix', kind = case.kind } }
    eq(items.matches(candidate, candidate.range, case.only), case.matches)
    eq(items.matches(candidate, range(1, 0, 1, 0), case.only), false)
  end
end

T['validation'] = MiniTest.new_set()
T['validation']['accepts optional ranges, columns, and action payloads without mutation'] = function()
  local candidates = {
    { action = { title = 'Command', command = { command = 'tool.run', title = 'Run' } } },
    { range = { start = { line = 0 }, ['end'] = { line = 1 } }, action = { title = 'Fix' } },
  }
  local original = vim.deepcopy(candidates)
  items.validate({})
  items.validate(candidates)
  eq(candidates, original)
end

for _, case in ipairs({
  { name = 'item list', value = false, message = 'items must be table' },
  { name = 'item', value = { 1 }, message = 'items[1] must be table' },
  { name = 'action', value = { {} }, message = 'items[1].action must be table' },
  { name = 'title', value = { { action = { title = 42 } } }, message = 'items[1].action.title must be string' },
  { name = 'range', value = { { range = false } }, message = 'items[1].range must be table' },
  { name = 'start', value = { { range = {} } }, message = 'items[1].range.start must be table' },
  { name = 'line', value = { { range = { start = {} } } }, message = 'items[1].range.start.line must be number' },
  {
    name = 'character',
    value = { { range = { start = { line = 0, character = false } } } },
    message = 'items[1].range.start.character must be number',
  },
  {
    name = 'end',
    value = { { range = { start = { line = 0 } } } },
    message = 'items[1].range.end must be table',
  },
}) do
  T['validation']['requires a valid ' .. case.name] = function()
    helpers.expect_error(case.message, function()
      helpers.call(items.validate, case.value)
    end)
  end
end

T['sorting'] = MiniTest.new_set()
T['sorting']['orders titles in place, preserves every payload, and is idempotent'] = function()
  local a, b, c = { title = 'A', data = 1 }, { title = 'B', data = 2 }, { title = 'A', data = 3 }
  local actions = { b, c, a }
  eq(rawequal(items.sort(actions), actions), true)
  eq(
    vim.tbl_map(function(action)
      return action.title
    end, actions),
    { 'A', 'A', 'B' }
  )
  local payloads = vim.tbl_map(function(action)
    return action.data
  end, actions)
  table.sort(payloads)
  eq(payloads, { 1, 2, 3 })
  eq(a, { title = 'A', data = 1 })
  eq(b, { title = 'B', data = 2 })
  eq(c, { title = 'A', data = 3 })
  eq(
    vim.tbl_map(function(action)
      return action.title
    end, items.sort(actions)),
    { 'A', 'A', 'B' }
  )
  eq(items.sort({}), {})
end

return T
