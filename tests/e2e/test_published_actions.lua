local MiniTest = require('mini.test')
local helpers = require('tests.support.lsp')

local eq = helpers.eq
local T = helpers.new_set()

T['published actions'] = MiniTest.new_set()

for _, form in ipairs({ 'changes', 'documentChanges' }) do
  T['published actions']['applies multi-file ' .. form .. ' with unknown secondary versions'] = function()
    local primary = helpers.new_buffer('multi-primary-' .. form .. '.txt', { 'old' })
    local secondary = helpers.new_buffer('multi-secondary-' .. form .. '.txt', { 'old' })
    local primary_uri, secondary_uri = vim.uri_from_bufnr(primary), vim.uri_from_bufnr(secondary)
    local range = helpers.range(0, 0, 0, 3)
    local edits = { { range = range, newText = 'new' } }
    local edit = form == 'changes' and { changes = { [primary_uri] = edits, [secondary_uri] = edits } }
      or {
        documentChanges = {
          { textDocument = { uri = secondary_uri }, edits = edits },
          { textDocument = { uri = primary_uri }, edits = edits },
        },
      }
    require('lint_actions').publish({
      bufnr = primary,
      source = 'multi-file',
      items = { { action = { title = 'Update both files', edit = edit } } },
    })

    local found = helpers.request(primary, range)
    eq(#found, 1)
    vim.lsp.util.apply_workspace_edit(found[1].edit, 'utf-8')
    eq(vim.api.nvim_buf_get_lines(primary, 0, -1, false), { 'new' })
    eq(vim.api.nvim_buf_get_lines(secondary, 0, -1, false), { 'new' })
  end
end

T['published actions']['filters a selected edit by line and kind before applying it'] = function()
  local bufnr = helpers.new_buffer('published.txt', { 'alpha', 'beta' })
  local range = helpers.range(1, 0, 1, 4)
  require('lint_actions').publish({
    bufnr = bufnr,
    source = 'tool',
    items = {
      {
        range = range,
        action = { title = 'Replace beta', kind = 'quickfix', edit = { range = range, newText = 'gamma' } },
      },
    },
  })

  eq(helpers.request(bufnr, helpers.range(0, 0, 0, 0)), {})
  eq(helpers.request(bufnr, range, { 'refactor' }), {})
  local found = helpers.request(bufnr, range, { 'quickfix' })
  eq(#found, 1)
  vim.lsp.util.apply_workspace_edit(found[1].edit, 'utf-8')
  eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { 'alpha', 'gamma' })
end

T['published actions']['an edit made after opening the menu invalidates both the listing and the selected edit'] = function()
  local bufnr = helpers.new_buffer('stale-selection.txt', { 'old' })
  local range = helpers.range(0, 0, 0, 3)
  require('lint_actions').publish({
    bufnr = bufnr,
    source = 'tool',
    items = { { action = { title = 'Replace', edit = { range = range, newText = 'new' } } } },
  })
  local found = helpers.request(bufnr, range)
  eq(#found, 1)

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'changed after request' })
  eq(helpers.request(bufnr, range), {})
  -- Neovim emits a stale-version message and leaves the buffer untouched.
  vim.lsp.util.apply_workspace_edit(found[1].edit, 'utf-8')
  eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { 'changed after request' })
end

T['published actions']['replacing and clearing a source preserves the other sources'] = function()
  local actions = require('lint_actions')
  local bufnr = helpers.new_buffer('sources.txt', { 'text' })
  local range = helpers.range(0, 0, 0, 0)
  local function publish(source, title)
    actions.publish({ bufnr = bufnr, source = source, items = { { action = { title = title } } } })
  end
  publish('first', 'Old')
  publish('second', 'Other')
  publish('first', 'New')
  local found = helpers.request(bufnr, range)
  eq(
    vim.tbl_map(function(action)
      return action.title
    end, found),
    { 'New', 'Other' }
  )

  actions.publish({ bufnr = bufnr, source = 'first', items = {} })
  found = helpers.request(bufnr, range)
  eq(#found, 1)
  eq(found[1].title, 'Other')
  actions.clear({ bufnr = bufnr })
  eq(helpers.request(bufnr, range), {})
end

T['published actions']['returns command-carrying actions unchanged'] = function()
  local actions = require('lint_actions')
  local bufnr = helpers.new_buffer(vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'command.txt'), { 'alpha' })
  local range = helpers.range(0, 0, 0, 5)
  local command = { title = 'Run it', command = 'my-tool.run', arguments = { 'alpha' } }

  actions.publish({
    bufnr = bufnr,
    source = 'tool',
    items = { { range = range, action = { title = 'Run it', kind = 'quickfix', command = command } } },
  })

  -- Neovim routes this to `vim.lsp.commands`, so the whole command has to
  -- survive publication rather than being reduced to its edit.
  local found = helpers.request(bufnr, range)
  eq(#found, 1)
  eq(found[1].command, command)
end

T['published actions']['requires fresh publication after a buffer rename'] = function()
  local actions = require('lint_actions')
  local bufnr = helpers.new_buffer('server-before-rename.txt', { 'old' })
  local range = helpers.range(0, 0, 0, 3)
  local publication = {
    bufnr = bufnr,
    source = 'tool',
    items = { { action = { title = 'Replace text', edit = { range = range, newText = 'new' } } } },
  }
  actions.publish(publication)
  eq(#helpers.request(bufnr, range), 1)

  vim.api.nvim_buf_set_name(bufnr, 'server-after-rename.txt')
  eq(helpers.request(bufnr, range), {})

  actions.publish(publication)
  local found = helpers.request(bufnr, range)
  eq(#found, 1)
  eq(found[1].edit.documentChanges[1].textDocument.uri, vim.uri_from_bufnr(bufnr))
  vim.lsp.util.apply_workspace_edit(found[1].edit, 'utf-8')
  eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { 'new' })
end

return T
