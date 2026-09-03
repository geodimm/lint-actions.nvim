local offsets = require('lint_actions.offsets')

local M = { source = 'markdownlint' }

local function decode(output)
  if type(output) ~= 'string' or output == '' then
    return {}
  end

  local ok, result = pcall(vim.json.decode, output)
  return ok and vim.islist(result) and result or {}
end

local function rule_name(issue)
  for _, name in ipairs(type(issue.ruleNames) == 'table' and issue.ruleNames or {}) do
    if type(name) == 'string' and name:match('^MD%d+$') then
      return name
    end
  end
  local name = type(issue.ruleNames) == 'table' and issue.ruleNames[1] or nil
  return type(name) == 'string' and name or 'markdownlint'
end

local function message(issue)
  local names = {}
  for _, name in ipairs(type(issue.ruleNames) == 'table' and issue.ruleNames or {}) do
    if type(name) == 'string' then
      table.insert(names, name)
    end
  end

  local description = type(issue.ruleDescription) == 'string' and issue.ruleDescription or 'Markdown lint issue'
  if type(issue.errorDetail) == 'string' and issue.errorDetail ~= '' then
    description = ('%s [%s]'):format(description, issue.errorDetail)
  end
  if type(issue.errorContext) == 'string' and issue.errorContext ~= '' then
    description = ('%s [Context: "%s"]'):format(description, issue.errorContext)
  end

  return #names > 0 and table.concat(names, '/') .. ' ' .. description or description
end

local function line(bufnr, line_number)
  return vim.api.nvim_buf_get_lines(bufnr, line_number - 1, line_number, false)[1] or ''
end

local function to_byte(text, utf16_index)
  local ok, byte_index = pcall(vim.str_byteindex, text, 'utf-16', math.max(utf16_index, 0), false)
  return ok and byte_index or #text
end

local function issue_range(issue, bufnr)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local line_number = type(issue.lineNumber) == 'number' and math.floor(issue.lineNumber) or 1
  line_number = math.max(1, math.min(line_number, line_count))
  local text = line(bufnr, line_number)
  local range = type(issue.errorRange) == 'table' and issue.errorRange or nil
  local start_utf16 = range and type(range[1]) == 'number' and math.max(range[1] - 1, 0) or 0
  local length_utf16 = range and type(range[2]) == 'number' and math.max(range[2], 0) or 0

  return {
    start = { line = line_number - 1, character = to_byte(text, start_utf16) },
    ['end'] = { line = line_number - 1, character = to_byte(text, start_utf16 + length_utf16) },
  }
end

local function normalize_fix(issue, bufnr)
  local fix = type(issue.fixInfo) == 'table' and issue.fixInfo or nil
  if not fix then
    return nil
  end

  local line_number = fix.lineNumber or issue.lineNumber
  local edit_column = fix.editColumn or 1
  local delete_count = fix.deleteCount or 0
  local insert_text = fix.insertText or ''
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if
    type(line_number) ~= 'number'
    or line_number ~= math.floor(line_number)
    or line_number < 1
    or line_number > line_count
    or type(edit_column) ~= 'number'
    or edit_column ~= math.floor(edit_column)
    or edit_column < 1
    or type(delete_count) ~= 'number'
    or delete_count ~= math.floor(delete_count)
    or delete_count < -1
    or type(insert_text) ~= 'string'
  then
    return nil
  end

  local line_length = vim.str_utfindex(line(bufnr, line_number), 'utf-16')
  if edit_column > line_length + 1 or (delete_count >= 0 and edit_column - 1 + delete_count > line_length) then
    return nil
  end

  return {
    line_number = line_number,
    edit_column = edit_column,
    delete_count = delete_count,
    insert_text = insert_text,
  }
end

local function full_range(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if vim.bo[bufnr].endofline then
    return { start = { line = 0, character = 0 }, ['end'] = { line = #lines, character = 0 } }
  end
  local last = lines[#lines] or ''
  return {
    start = { line = 0, character = 0 },
    ['end'] = { line = math.max(#lines - 1, 0), character = #last },
  }
end

local function fix_edit(fix, bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local row = fix.line_number - 1
  local text = lines[fix.line_number] or ''

  if fix.delete_count == -1 then
    if #lines == 1 then
      return { range = full_range(bufnr), newText = '' }
    elseif fix.line_number < #lines then
      return {
        range = { start = { line = row, character = 0 }, ['end'] = { line = row + 1, character = 0 } },
        newText = '',
      }
    end
    return {
      range = {
        start = { line = row - 1, character = #(lines[fix.line_number - 1] or '') },
        ['end'] = { line = row, character = #text },
      },
      newText = '',
    }
  end

  local start_utf16 = fix.edit_column - 1
  return {
    range = {
      start = { line = row, character = to_byte(text, start_utf16) },
      ['end'] = { line = row, character = to_byte(text, start_utf16 + fix.delete_count) },
    },
    newText = fix.insert_text,
  }
end

local function apply_fixes(bufnr, fixes)
  fixes = vim.deepcopy(fixes)
  table.sort(fixes, function(left, right)
    if left.line_number ~= right.line_number then
      return left.line_number > right.line_number
    end
    local left_deletes_line = left.delete_count == -1
    local right_deletes_line = right.delete_count == -1
    if left_deletes_line ~= right_deletes_line then
      return not left_deletes_line
    end
    if left.edit_column ~= right.edit_column then
      return left.edit_column > right.edit_column
    end
    return vim.str_utfindex(left.insert_text, 'utf-16') > vim.str_utfindex(right.insert_text, 'utf-16')
  end)

  local unique = {}
  for _, fix in ipairs(fixes) do
    local previous = unique[#unique]
    if
      not previous
      or fix.line_number ~= previous.line_number
      or fix.edit_column ~= previous.edit_column
      or fix.delete_count ~= previous.delete_count
      or fix.insert_text ~= previous.insert_text
    then
      table.insert(unique, fix)
    end
  end

  local collapsed = {}
  for _, fix in ipairs(unique) do
    local previous = collapsed[#collapsed]
    if
      previous
      and fix.line_number == previous.line_number
      and fix.edit_column == previous.edit_column
      and fix.insert_text == ''
      and fix.delete_count > 0
      and previous.insert_text ~= ''
      and previous.delete_count == 0
    then
      fix.insert_text = previous.insert_text
      table.remove(collapsed)
    end
    table.insert(collapsed, fix)
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local deleted = {}
  local last_line = -1
  local last_column = -1
  for _, fix in ipairs(collapsed) do
    local line_number = fix.line_number
    local column = fix.edit_column - 1
    local does_not_overlap = line_number ~= last_line
      or fix.delete_count == -1
      or column + fix.delete_count <= last_column - (fix.delete_count > 0 and 0 or 1)
    if does_not_overlap then
      if fix.delete_count == -1 then
        deleted[line_number] = true
      else
        local text = lines[line_number] or ''
        local start_byte = to_byte(text, column)
        local end_byte = to_byte(text, column + fix.delete_count)
        local insert_text = fix.insert_text:gsub('\r\n', '\n'):gsub('\r', '\n')
        lines[line_number] = text:sub(1, start_byte) .. insert_text .. text:sub(end_byte + 1)
      end
    end
    last_line = line_number
    last_column = column
  end

  local kept = {}
  for index, text in ipairs(lines) do
    if not deleted[index] then
      table.insert(kept, text)
    end
  end

  local fixed = table.concat(kept, '\n')
  if #kept > 0 and vim.bo[bufnr].endofline then
    fixed = fixed .. '\n'
  end
  return fixed
end

---Parse markdownlint-cli JSON output into nvim-lint diagnostics.
---@param output string
---@param bufnr integer
---@return vim.Diagnostic[]
function M.diagnostics(output, bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end

  local diagnostics = {}
  for _, issue in ipairs(decode(output)) do
    if type(issue) == 'table' then
      local range = issue_range(issue, bufnr)
      table.insert(diagnostics, {
        lnum = range.start.line,
        col = range.start.character,
        end_lnum = range['end'].line,
        end_col = range['end'].character,
        severity = vim.diagnostic.severity.WARN,
        source = M.source,
        code = rule_name(issue),
        message = message(issue),
      })
    end
  end
  return diagnostics
end

---Translate markdownlint-cli JSON fixInfo entries into native code actions.
---@param context LintActions.AdapterContext
---@return LintActions.Item[]
function M.parse(context)
  if not vim.api.nvim_buf_is_valid(context.bufnr) then
    return {}
  end

  local items = {}
  local fixes = {}
  for _, issue in ipairs(decode(context.output)) do
    if type(issue) == 'table' then
      local fix = normalize_fix(issue, context.bufnr)
      if fix then
        table.insert(fixes, fix)
        table.insert(items, {
          range = issue_range(issue, context.bufnr),
          action = {
            title = ('Fix %s: %s'):format(
              rule_name(issue),
              type(issue.ruleDescription) == 'string' and issue.ruleDescription or 'Markdown lint issue'
            ),
            kind = 'quickfix',
            isPreferred = true,
            edit = fix_edit(fix, context.bufnr),
          },
        })
      end
    end
  end

  if #fixes > 0 then
    local original = offsets.buffer_text(context.bufnr):gsub('\r\n', '\n'):gsub('\r', '\n')
    local fixed = apply_fixes(context.bufnr, fixes)
    if fixed ~= original then
      table.insert(items, {
        range = full_range(context.bufnr),
        action = {
          title = 'Fix all markdownlint issues',
          kind = 'source.fixAll.markdownlint',
          edit = { range = full_range(context.bufnr), newText = fixed },
        },
      })
    end
  end

  return items
end

return M
