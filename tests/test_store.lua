local MiniTest = require('mini.test')
local helpers = require('tests.helpers')
local store = require('lint_actions.store')

local eq = helpers.eq
local T = MiniTest.new_set({
  hooks = { pre_case = store._reset, post_case = store._reset },
})

T['publish()'] = MiniTest.new_set()

T['publish()']['keeps sources independent and replaces one source batch'] = function()
  local bufnr = helpers.new_buffer('store-publish.txt', { 'text' })
  local range = helpers.range(0, 0, 0, 4)

  store.publish(helpers.batch(bufnr, 'one', 'old', range))
  store.publish(helpers.batch(bufnr, 'two', 'other', range))
  store.publish(helpers.batch(bufnr, 'one', 'new', range))

  eq(
    vim.tbl_map(function(action)
      return action.title
    end, store.actions(bufnr, range)),
    { 'new', 'other' }
  )
end

T['actions()'] = MiniTest.new_set()

T['actions()']['filters ranges and hierarchical action kinds'] = function()
  local bufnr = helpers.new_buffer('store-filter.txt', { 'alpha', 'beta' })
  local first = helpers.range(0, 0, 0, 5)
  local second = helpers.range(1, 0, 1, 4)
  local kindless = helpers.batch(bufnr, 'kindless', 'No kind', second)
  kindless.items[1].action.kind = nil
  store.publish(helpers.batch(bufnr, 'quickfix', 'Quick fix', first, 'quickfix'))
  store.publish(helpers.batch(bufnr, 'source', 'Fix all', second, 'source.fixAll'))
  store.publish(kindless)

  eq(#store.actions(bufnr, first), 1)
  eq(#store.actions(bufnr, second, { 'source' }), 1)
  eq(#store.actions(bufnr, second, { 'source.fixAll' }), 1)
  eq(#store.actions(bufnr, second, { 'refactor' }), 0)
end

T['actions()']['drops stale batches after a buffer change'] = function()
  local bufnr = helpers.new_buffer('store-stale.txt', { 'text' })
  local range = helpers.range(0, 0, 0, 4)
  store.publish(helpers.batch(bufnr, 'tool', 'Old action', range))

  vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { 'changed' })
  eq(store.actions(bufnr, range), {})

  vim.bo[bufnr].modified = false
  store.publish(helpers.batch(bufnr, 'fresh', 'Fresh action', range))
  eq(store.actions(bufnr, range)[1].title, 'Fresh action')
end

T['actions()']['returns copies that callers can mutate'] = function()
  local bufnr = helpers.new_buffer('store-copy.txt', { 'text' })
  local range = helpers.range(0, 0, 0, 4)
  store.publish(helpers.batch(bufnr, 'tool', 'Original', range))

  local action = store.actions(bufnr, range)[1]
  action.title = 'Mutated'
  eq(store.actions(bufnr, range)[1].title, 'Original')
end

T['clear()'] = MiniTest.new_set()

T['clear()']['clears one source or the whole buffer and tolerates missing state'] = function()
  local bufnr = helpers.new_buffer('store-clear.txt', { 'text' })
  local range = helpers.range(0, 0, 0, 4)
  store.publish(helpers.batch(bufnr, 'one', 'One', range))
  store.publish(helpers.batch(bufnr, 'two', 'Two', range))

  store.clear(bufnr, 'one')
  eq(store.actions(bufnr, range)[1].title, 'Two')
  store.clear(bufnr)
  eq(store.actions(bufnr, range), {})
  MiniTest.expect.no_error(function()
    store.clear(bufnr, 'missing')
  end)
end

return T
