local MiniTest = require('mini.test')
local helpers = require('tests.support.lsp')
local lint_actions = require('lint_actions')
local eq = helpers.eq
local T = helpers.new_set()

---@param title string
---@param range? table
local function item(title, range)
  return { range = range, action = { title = title, kind = 'quickfix' } }
end

local function titles(actions)
  return vim.tbl_map(function(action)
    return action.title
  end, actions)
end

T['providers'] = MiniTest.new_set()

T['providers']['answers requests from current buffer state without republishing'] = function()
  local bufnr = helpers.new_buffer(vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'provider.txt'), { 'alpha' })

  lint_actions.register({
    source = 'line-counter',
    provide = function(context)
      return { item(('Lines: %d'):format(vim.api.nvim_buf_line_count(context.bufnr))) }
    end,
  })

  eq(titles(helpers.request(bufnr, helpers.range(0, 0, 0, 0))), { 'Lines: 1' })

  -- The published path would go stale here; a provider recomputes instead.
  vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { 'beta', 'gamma' })
  eq(titles(helpers.request(bufnr, helpers.range(0, 0, 0, 0))), { 'Lines: 3' })
end

T['providers']['merges and sorts healthy sources even when one provider fails'] = function()
  local bufnr = helpers.new_buffer(vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'provider-merge.txt'), { 'alpha' })

  lint_actions.publish({
    bufnr = bufnr,
    source = 'published',
    items = { item('B published', helpers.range(0, 0, 0, 5)) },
  })
  lint_actions.register({
    source = 'provided',
    provide = function()
      return { item('A provided'), item('C provided') }
    end,
  })

  lint_actions.register({
    source = 'broken',
    provide = function()
      error('expected provider failure')
    end,
  })

  eq(titles(helpers.request(bufnr, helpers.range(0, 0, 0, 0))), { 'A provided', 'B published', 'C provided' })
end

T['providers']['attaches to files opened after registration'] = function()
  local path = vim.fs.joinpath(vim.fn.tempname() .. '-provider.txt')
  vim.fn.writefile({ 'alpha' }, path)
  MiniTest.finally(function()
    vim.fn.delete(path)
  end)

  lint_actions.register({
    source = 'on-read',
    provide = function()
      return { item('Opened action') }
    end,
  })

  vim.cmd.edit(path)
  local bufnr = vim.api.nvim_get_current_buf()
  MiniTest.finally(function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  eq(titles(helpers.request(bufnr, helpers.range(0, 0, 0, 0))), { 'Opened action' })
end

T['providers']['stops a provider from answering'] = function()
  local bufnr = helpers.new_buffer(vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'provider-unregister.txt'), { 'alpha' })

  lint_actions.register({
    source = 'temporary',
    provide = function()
      return { item('Temporary action') }
    end,
  })
  eq(#helpers.request(bufnr, helpers.range(0, 0, 0, 0)), 1)

  lint_actions.unregister('temporary')
  eq(helpers.request(bufnr, helpers.range(0, 0, 0, 0)), {})
end

return T
