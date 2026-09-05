local MiniTest = require('mini.test')
local helpers = require('tests.support.nvim')
local items = require('lint_actions.items')
local eq = helpers.eq
local T = helpers.new_set()

T['current-document edits'] = MiniTest.new_set()
for _, form in ipairs({ 'single edit', 'edit list', 'changes', 'documentChanges' }) do
  T['current-document edits'][form .. ' becomes a versioned document edit without mutating its input'] = function()
    local bufnr = helpers.new_buffer('normalize.txt', { 'old' })
    local uri = vim.uri_from_bufnr(bufnr)
    local edit = { range = helpers.range(0, 0, 0, 3), newText = 'new' }
    local forms = {
      ['single edit'] = edit,
      ['edit list'] = { edit },
      changes = { changes = { [uri] = { edit } } },
      documentChanges = { documentChanges = { { textDocument = { uri = uri, version = -1 }, edits = { edit } } } },
    }
    local input = { { action = { title = 'Replace', kind = 'quickfix', edit = forms[form] } } }
    local original = vim.deepcopy(input)
    local normalized = items.normalize(input, bufnr)
    eq(normalized[1].action, {
      title = 'Replace',
      kind = 'quickfix',
      edit = {
        documentChanges = {
          { textDocument = { uri = uri, version = vim.api.nvim_buf_get_changedtick(bufnr) }, edits = { edit } },
        },
      },
    })
    eq(input, original)
    eq(items.normalize(normalized, bufnr), normalized)
    normalized[1].action.edit.documentChanges[1].edits[1].newText = 'mutated'
    eq(input, original)
  end
end

T['workspace edits'] = MiniTest.new_set()
T['workspace edits']['preserves explicit secondary versions and resource operations'] = function()
  local bufnr = helpers.new_buffer('normalize-primary.txt', { 'old' })
  local uri = vim.uri_from_fname(vim.fn.getcwd() .. '/secondary.txt')
  local changes = {
    { textDocument = { uri = uri, version = 42 }, edits = {} },
    { kind = 'rename', oldUri = uri, newUri = uri .. '.renamed' },
    { kind = 'create', uri = uri .. '.created' },
    { kind = 'delete', uri = uri .. '.deleted' },
  }
  local input = { { action = { title = 'Update files', edit = { documentChanges = changes } } } }
  local original = vim.deepcopy(input)
  eq(items.normalize(input, bufnr)[1].action.edit.documentChanges, changes)
  eq(input, original)
end

T['workspace edits']['uses the running Neovim representation for unknown secondary versions'] = function()
  local bufnr = helpers.new_buffer('normalize-unknown.txt', { 'old' })
  local uri = vim.uri_from_fname(vim.fn.getcwd() .. '/secondary.txt')
  local changes = {
    { textDocument = { uri = uri }, edits = {} },
    { textDocument = { uri = uri, version = vim.NIL }, edits = {} },
  }
  local input = { { action = { title = 'Update files', edit = { documentChanges = changes } } } }
  local original = vim.deepcopy(input)
  local normalized = assert(assert(items.normalize(input, bufnr)[1].action.edit).documentChanges)
  local unknown = vim.fn.has('nvim-0.12') == 1 and vim.NIL or nil
  eq(normalized[1].textDocument.version, unknown)
  eq(normalized[2].textDocument.version, unknown)
  eq(input, original)
end

T['workspace edits']['combines changes and documentChanges without losing annotations'] = function()
  local bufnr = helpers.new_buffer('normalize-combined.txt', { 'old' })
  local uri = vim.uri_from_bufnr(bufnr)
  local operation = { kind = 'create', uri = uri .. '.new' }
  local annotations = { change = { label = 'Update text' } }
  local input = {
    {
      action = {
        title = 'Update',
        edit = {
          changes = { [uri] = {} },
          documentChanges = { operation },
          changeAnnotations = annotations,
        },
      },
    },
  }
  local normalized = assert(items.normalize(input, bufnr)[1].action.edit)
  assert(normalized.documentChanges)
  eq(#normalized.documentChanges, 2)
  eq(normalized.documentChanges[1], operation)
  eq(normalized.documentChanges[2].textDocument.uri, uri)
  eq(normalized.changeAnnotations, annotations)
  eq(normalized.changes, nil)
end

T['item ranges and payloads'] = MiniTest.new_set()
T['item ranges and payloads']['defaults omitted ranges to the buffer and omitted columns to zero'] = function()
  local bufnr = helpers.new_buffer('normalize-ranges.txt', { 'a', 'b', 'c' })
  local input = {
    { action = { title = 'Whole buffer' } },
    { range = { start = { line = 1 }, ['end'] = { line = 2 } }, action = { title = 'Lines' } },
    { range = helpers.range(1, 2, 2, 3), action = { title = 'Explicit columns' } },
  }
  local normalized = items.normalize(input, bufnr)
  eq(normalized[1].range, helpers.range(0, 0, 2, 0))
  eq(normalized[2].range, helpers.range(1, 0, 2, 0))
  eq(normalized[3].range, helpers.range(1, 2, 2, 3))
end

T['item ranges and payloads']['copies command-only actions without adding an edit'] = function()
  local bufnr = helpers.new_buffer('normalize-command.txt', { 'a' })
  local action =
    { title = 'Run', command = { title = 'Run', command = 'tool.run', arguments = { 'a' } }, data = { id = 1 } }
  local original = vim.deepcopy(action)
  local normalized = items.normalize({ { action = action } }, bufnr)[1].action
  eq(normalized, original)
  normalized.command.arguments[1] = 'changed'
  normalized.data.id = 2
  eq(action, original)
end

return T
