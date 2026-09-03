local offsets = require('lint_actions.offsets')
local paths = require('lint_actions.paths')

local M = { source = 'shellcheck' }

---@class LintActions.ShellcheckReplacement
---@field start integer Zero-based byte offset the replacement starts at.
---@field finish integer Zero-based byte offset the replacement ends at, exclusive.
---@field replacement string Text to put in that range.
---@field precedence integer Higher precedence is applied first.
---@field insert_after boolean Whether later replacements at the same point land before this one.

---@param output string
---@return table[]
local function decode(output)
  if type(output) ~= 'string' or output == '' then
    return {}
  end

  local ok, result = pcall(vim.json.decode, output)
  if not ok or type(result) ~= 'table' or type(result.comments) ~= 'table' or not vim.islist(result.comments) then
    return {}
  end
  return result.comments
end

---Zero-based byte offset of the first character of every one-based line.
---@param text string
---@return integer[]
local function line_starts(text)
  local starts = { 0 }
  local index = 1
  while true do
    local newline = text:find('\n', index, true)
    if not newline then
      return starts
    end
    table.insert(starts, newline)
    index = newline + 1
  end
end

---shellcheck counts columns in characters, and json1 has already undone its
---tab-stop expansion, so a column only needs converting to a byte offset.
---@param text string
---@param starts integer[]
---@param line integer One-based line.
---@param column integer One-based character column.
---@return integer? offset Zero-based byte offset.
local function to_offset(text, starts, line, column)
  local start = starts[line]
  if start == nil then
    return nil
  end

  local content = text:sub(start + 1, starts[line + 1] and starts[line + 1] - 1 or #text)
  local ok, byte = pcall(vim.str_byteindex, content, 'utf-32', math.max(column - 1, 0), false)
  if not ok then
    byte = #content
  end
  return start + math.min(byte, #content)
end

---@param replacement table
---@param text string
---@param starts integer[]
---@return LintActions.ShellcheckReplacement?
local function normalize_replacement(replacement, text, starts)
  if type(replacement) ~= 'table' then
    return nil
  end
  for _, field in ipairs({ 'line', 'column', 'endLine', 'endColumn' }) do
    if type(replacement[field]) ~= 'number' then
      return nil
    end
  end
  if type(replacement.replacement) ~= 'string' then
    return nil
  end

  local start = to_offset(text, starts, math.floor(replacement.line), math.floor(replacement.column))
  local finish = to_offset(text, starts, math.floor(replacement.endLine), math.floor(replacement.endColumn))
  if start == nil or finish == nil or finish < start then
    return nil
  end

  return {
    start = start,
    finish = finish,
    replacement = replacement.replacement,
    precedence = type(replacement.precedence) == 'number' and replacement.precedence or 0,
    insert_after = replacement.insertionPoint == 'afterEnd',
  }
end

---A fix is one instruction split across replacements, so half of one would
---leave the buffer worse off than not offering the action at all.
---@param comment table
---@param text string
---@param starts integer[]
---@return LintActions.ShellcheckReplacement[]?
local function normalize_fix(comment, text, starts)
  local fix = type(comment.fix) == 'table' and comment.fix or nil
  if not fix or type(fix.replacements) ~= 'table' or not vim.islist(fix.replacements) then
    return nil
  end

  local replacements = {}
  for _, replacement in ipairs(fix.replacements) do
    local normalized = normalize_replacement(replacement, text, starts)
    if not normalized then
      return nil
    end
    table.insert(replacements, normalized)
  end
  return #replacements > 0 and replacements or nil
end

---Apply replacements the way shellcheck's own fixer does: highest precedence
---first, with every later replacement shifted by the ones already applied.
---Offsets are relative to `region`.
---@param region string
---@param replacements LintActions.ShellcheckReplacement[]
---@return string
local function apply(region, replacements)
  local ordered = {}
  for index, replacement in ipairs(replacements) do
    table.insert(ordered, vim.tbl_extend('force', replacement, { order = index }))
  end
  table.sort(ordered, function(left, right)
    if left.precedence ~= right.precedence then
      return left.precedence > right.precedence
    end
    return left.order > right.order
  end)

  local shifts = {}
  local function shifted(offset)
    local total = offset
    for _, shift in ipairs(shifts) do
      if shift.key <= offset then
        total = total + shift.value
      end
    end
    return total
  end

  local result = region
  for _, replacement in ipairs(ordered) do
    local start = shifted(replacement.start)
    local finish = shifted(replacement.finish)
    -- An insertion point decides which side of an earlier replacement at the
    -- same offset this one ends up on.
    table.insert(shifts, {
      key = replacement.insert_after and replacement.finish + 1 or replacement.start,
      value = #replacement.replacement - (replacement.finish - replacement.start),
    })
    result = result:sub(1, start) .. replacement.replacement .. result:sub(finish + 1)
  end
  return result
end

---Rewrite only the span the replacements actually cover.
---@param text string
---@param replacements LintActions.ShellcheckReplacement[]
---@return lsp.TextEdit? edit
---@return string? original Text the edit replaces, for callers that check it changed.
local function fix_edit(text, replacements)
  if #replacements == 0 then
    return nil
  end

  local first, last = replacements[1].start, replacements[1].finish
  for _, replacement in ipairs(replacements) do
    first = math.min(first, replacement.start)
    last = math.max(last, replacement.finish)
  end

  local rebased = {}
  for _, replacement in ipairs(replacements) do
    table.insert(
      rebased,
      vim.tbl_extend('force', replacement, { start = replacement.start - first, finish = replacement.finish - first })
    )
  end

  local original = text:sub(first + 1, last)
  return {
    range = {
      start = offsets.to_position(text, first, 'utf-8'),
      ['end'] = offsets.to_position(text, last, 'utf-8'),
    },
    newText = apply(original, rebased),
  },
    original
end

---@param left LintActions.ShellcheckReplacement
---@param right LintActions.ShellcheckReplacement
---@return boolean
local function overlaps(left, right)
  return left.finish > right.start and right.finish > left.start
end

---shellcheck drops a whole fix when any of its replacements collides with one
---it has already taken, so the fixes it keeps depend on the order they arrive.
---@param fixes LintActions.ShellcheckReplacement[][]
---@return LintActions.ShellcheckReplacement[]
local function merge(fixes)
  local merged = {}
  for _, fix in ipairs(fixes) do
    local collides = false
    for _, replacement in ipairs(fix) do
      for _, taken in ipairs(merged) do
        if overlaps(replacement, taken) then
          collides = true
          break
        end
      end
      if collides then
        break
      end
    end
    if not collides then
      vim.list_extend(merged, fix)
    end
  end
  return merged
end

---@param comment table
---@param text string
---@param starts integer[]
---@return LintActions.Range
local function comment_range(comment, text, starts)
  local line = type(comment.line) == 'number' and math.floor(comment.line) or 1
  local column = type(comment.column) == 'number' and math.floor(comment.column) or 1
  local end_line = type(comment.endLine) == 'number' and math.floor(comment.endLine) or line
  local end_column = type(comment.endColumn) == 'number' and math.floor(comment.endColumn) or column

  local start = to_offset(text, starts, line, column) or 0
  local finish = math.max(to_offset(text, starts, end_line, end_column) or start, start)
  return {
    start = offsets.to_position(text, start, 'utf-8'),
    ['end'] = offsets.to_position(text, finish, 'utf-8'),
  }
end

---@param comment table
---@return string
local function title(comment)
  local message = type(comment.message) == 'string' and comment.message or ''
  local code = type(comment.code) == 'number' and ('SC%d'):format(math.floor(comment.code)) or nil
  if code and message ~= '' then
    return ('Fix %s: %s'):format(code, message)
  elseif code then
    return ('Fix %s'):format(code)
  elseif message ~= '' then
    return ('Fix shellcheck issue: %s'):format(message)
  end
  return 'Fix shellcheck issue'
end

---shellcheck follows `source` directives, so one run can report on files other
---than the buffer nvim-lint asked about. Only the buffer's own fixes apply.
---@param comment table
---@param filename string?
---@param cwd string?
---@return boolean
local function reports_buffer(comment, filename, cwd)
  local file = comment.file
  if type(file) ~= 'string' or file == '' or file == '-' then
    return true
  end
  return filename ~= nil and paths.absolute(file, cwd) == filename
end

---Translate shellcheck `--format json1` fix replacements into native code actions.
---@param context LintActions.AdapterContext
---@return LintActions.Item[]
function M.parse(context)
  if not vim.api.nvim_buf_is_valid(context.bufnr) then
    return {}
  end

  local comments = decode(context.output)
  if #comments == 0 then
    return {}
  end

  local filename = paths.absolute(vim.api.nvim_buf_get_name(context.bufnr), context.cwd)
  local text = offsets.buffer_text(context.bufnr)
  local starts = line_starts(text)
  local items = {}
  local fixes = {}

  for _, comment in ipairs(comments) do
    if type(comment) == 'table' and reports_buffer(comment, filename, context.cwd) then
      local replacements = normalize_fix(comment, text, starts)
      if replacements then
        table.insert(fixes, replacements)
        table.insert(items, {
          range = comment_range(comment, text, starts),
          action = {
            title = title(comment),
            kind = 'quickfix',
            isPreferred = true,
            edit = fix_edit(text, replacements),
          },
        })
      end
    end
  end

  local fix_all, original = fix_edit(text, merge(fixes))
  if fix_all and fix_all.newText ~= original then
    table.insert(items, {
      range = fix_all.range,
      action = {
        title = 'Fix all shellcheck issues',
        kind = 'source.fixAll.shellcheck',
        edit = fix_all,
      },
    })
  end

  return items
end

return M
