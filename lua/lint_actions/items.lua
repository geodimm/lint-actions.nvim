local compat = require('lint_actions.compat')

local M = {}

---@return any
local function unknown_document_version()
  -- Neovim 0.11 treats nil as an unknown version. Neovim 0.12's apply helper
  -- distinguishes an explicit vim.NIL from a missing field.
  return vim.fn.has('nvim-0.12') == 1 and vim.NIL or nil
end

---Raise a type error. `level` follows `error()` and defaults to the caller of
---the function doing the validation, which is right when a public entry point
---checks its own arguments. Pass 0 to raise the bare message instead, for a
---caller that re-raises it at its own call site.
---@param value any
---@param expected string
---@param name string
---@param level? integer
function M.expect(value, expected, name, level)
  if type(value) ~= expected then
    error(('%s must be %s, got %s'):format(name, expected, type(value)), level or 3)
  end
end

---@param position LintActions.Position
---@param name string
local function validate_position(position, name)
  M.expect(position, 'table', name, 0)
  M.expect(position.line, 'number', name .. '.line', 0)
  if position.character ~= nil then
    M.expect(position.character, 'number', name .. '.character', 0)
  end
end

---Validate items supplied by a source. Raises the bare message; callers re-raise.
---@param items LintActions.Item[]
function M.validate(items)
  M.expect(items, 'table', 'items', 0)
  for index, item in ipairs(items) do
    local name = ('items[%d]'):format(index)
    M.expect(item, 'table', name, 0)
    if item.range ~= nil then
      M.expect(item.range, 'table', name .. '.range', 0)
      validate_position(item.range.start, name .. '.range.start')
      validate_position(item.range['end'], name .. '.range.end')
    end
    M.expect(item.action, 'table', name .. '.action', 0)
    M.expect(item.action.title, 'string', name .. '.action.title', 0)
  end
end

---@param bufnr integer
---@return lsp.Range
local function buffer_range(bufnr)
  local last_line = math.max(vim.api.nvim_buf_line_count(bufnr) - 1, 0)
  return { start = { line = 0, character = 0 }, ['end'] = { line = last_line, character = 0 } }
end

---@param range? LintActions.Range
---@param bufnr integer
---@return lsp.Range
local function normalize_range(range, bufnr)
  if range == nil then
    return buffer_range(bufnr)
  end
  return {
    start = { line = range.start.line, character = range.start.character or 0 },
    ['end'] = { line = range['end'].line, character = range['end'].character or 0 },
  }
end

---@param action lsp.CodeAction
---@param uri string
---@param version integer
---@return lsp.CodeAction
local function version_edit(action, uri, version)
  action = vim.deepcopy(action)
  local edit = action.edit
  if not edit then
    return action
  end

  -- Text edits do not identify their target document. Accept one edit or a
  -- list as a convenient same-buffer shorthand, then put the protocol-correct
  -- WorkspaceEdit on the CodeAction returned to Neovim.
  local text_edit_range = rawget(edit, 'range')
  if text_edit_range or vim.islist(edit) then
    local edits = text_edit_range and { edit } or edit
    action.edit = {
      documentChanges = {
        {
          textDocument = { uri = uri, version = version },
          edits = edits,
        },
      },
    }
    return action
  end

  if edit.changes then
    edit.documentChanges = edit.documentChanges or {}
    for edit_uri, edits in pairs(edit.changes) do
      table.insert(edit.documentChanges, {
        textDocument = { uri = edit_uri },
        edits = edits,
      })
    end
    edit.changes = nil
  end

  for _, change in ipairs(edit.documentChanges or {}) do
    local document = change.textDocument
    if document then
      if document.uri == uri then
        document.version = version
      elseif compat.isnil(document.version) then
        -- Normalize both representations to the sentinel this Neovim accepts.
        document.version = unknown_document_version()
      end
    end
  end
  return action
end

---Copy validated items, filling in the default range and versioning edits
---against the buffer's current changed tick.
---@param items LintActions.Item[]
---@param bufnr integer
---@return LintActions.NormalizedItem[]
function M.normalize(items, bufnr)
  local uri = vim.uri_from_bufnr(bufnr)
  local version = vim.api.nvim_buf_get_changedtick(bufnr)
  return vim.tbl_map(function(item)
    return {
      range = normalize_range(item.range, bufnr),
      action = version_edit(item.action, uri, version),
    }
  end, items)
end

---@param left lsp.Range
---@param right lsp.Range
local function ranges_overlap(left, right)
  return left.start.line <= right['end'].line and right.start.line <= left['end'].line
end

---@param kind? lsp.CodeActionKind
---@param only? lsp.CodeActionKind[]
local function kind_matches(kind, only)
  if not only or #only == 0 then
    return true
  end
  if not kind then
    return false
  end

  for _, requested in ipairs(only) do
    if kind == requested or vim.startswith(kind, requested .. '.') then
      return true
    end
  end
  return false
end

---Decide whether an item answers a code-action request. Ranges are matched by
---line; `character` is accepted for protocol shape but never narrows a match.
---@param item LintActions.NormalizedItem
---@param range lsp.Range
---@param only? lsp.CodeActionKind[]
---@return boolean
function M.matches(item, range, only)
  return ranges_overlap(item.range, range) and kind_matches(item.action.kind, only)
end

---@param actions lsp.CodeAction[]
---@return lsp.CodeAction[]
function M.sort(actions)
  table.sort(actions, function(left, right)
    return left.title < right.title
  end)
  return actions
end

return M
