local helpers = require('tests.support.nvim')
local store = require('lint_actions.store')

local eq = helpers.eq

describe('Action store', function()
  before_each(helpers.reset)
  after_each(helpers.reset)

  describe('publish()', function()
    it('keeps sources independent and replaces one source batch', function()
      local bufnr = helpers.new_buffer('store-publish.txt', { 'text' })
      local range = helpers.range(0, 0, 0, 4)
      local other = helpers.new_buffer('other-buffer.txt', { 'text' })
      store.publish(helpers.batch(other, 'one', 'Separate buffer', range))

      store.publish(helpers.batch(bufnr, 'one', 'old', range))
      store.publish(helpers.batch(bufnr, 'two', 'other', range))
      store.publish(helpers.batch(bufnr, 'one', 'new', range))

      local titles = vim.tbl_map(function(action)
        return action.title
      end, store.actions(bufnr, range))
      table.sort(titles)
      eq(titles, { 'new', 'other' })
      eq(store.actions(other, range)[1].title, 'Separate buffer')
    end)
  end)

  describe('actions()', function()
    it('filters ranges and hierarchical action kinds', function()
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
    end)

    it('returns copies that callers can mutate', function()
      local bufnr = helpers.new_buffer('store-copy.txt', { 'text' })
      local range = helpers.range(0, 0, 0, 4)
      store.publish(helpers.batch(bufnr, 'tool', 'Original', range))

      local action = store.actions(bufnr, range)[1]
      action.title = 'Mutated'
      eq(store.actions(bufnr, range)[1].title, 'Original')
    end)
  end)

  describe('batch freshness', function()
    for _, field in ipairs({ 'uri', 'changedtick', 'version' }) do
      it('permanently discards a batch with a different ' .. field, function()
        local bufnr = helpers.new_buffer('freshness.txt', { 'text' })
        local range = helpers.range(0, 0, 0, 4)
        local stale = helpers.batch(bufnr, 'stale', 'Stale', range)
        local original = stale[field]
        stale[field] = field == 'uri' and 'file:///different.txt' or -1
        store.publish(stale)
        store.publish(helpers.batch(bufnr, 'fresh', 'Fresh', range))

        eq(store.actions(bufnr, range), { { title = 'Fresh', kind = 'quickfix' } })
        -- Once observed as stale, restoring a stamp cannot resurrect the batch.
        stale[field] = original
        eq(store.actions(bufnr, range), { { title = 'Fresh', kind = 'quickfix' } })
      end)
    end
  end)

  describe('clear()', function()
    it('clears one source or the whole buffer and tolerates missing state', function()
      local bufnr = helpers.new_buffer('store-clear.txt', { 'text' })
      local range = helpers.range(0, 0, 0, 4)
      store.publish(helpers.batch(bufnr, 'one', 'One', range))
      store.publish(helpers.batch(bufnr, 'two', 'Two', range))

      store.clear(bufnr, 'one')
      eq(store.actions(bufnr, range)[1].title, 'Two')
      store.clear(bufnr)
      eq(store.actions(bufnr, range), {})
      assert.has_no.error(function()
        store.clear(bufnr, 'missing')
      end)
    end)
  end)
end)
