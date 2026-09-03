local offsets = require('lint_actions.offsets')

local M = { source = 'golangci-lint' }

local function absolute(path, cwd)
  if type(path) ~= 'string' or path == '' then
    return nil
  end
  local is_absolute = path:match('^/') or path:match('^%a:[/\\]') or path:match('^[/\\][/\\]')
  if not is_absolute then
    path = vim.fs.joinpath(cwd or vim.uv.cwd(), path)
  end
  return vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
end

local function diagnostic_key(source, line, column, message)
  return table.concat({ source or '', line, column, message or '' }, '\0')
end

local function diagnostic_ranges(diagnostics)
  local ranges = {}
  for _, diagnostic in ipairs(diagnostics or {}) do
    local key = diagnostic_key(diagnostic.source, diagnostic.lnum, diagnostic.col, diagnostic.message)
    ranges[key] = ranges[key] or {}
    table.insert(ranges[key], {
      start = { line = diagnostic.lnum, character = diagnostic.col },
      ['end'] = {
        line = diagnostic.end_lnum or diagnostic.lnum,
        character = diagnostic.end_col or diagnostic.col,
      },
    })
  end
  return ranges
end

local function issue_range(issue, text, ranges)
  local position = type(issue.Pos) == 'table' and issue.Pos or {}
  local line = type(position.Line) == 'number' and math.max(position.Line - 1, 0) or 0
  local column = type(position.Column) == 'number' and math.max(position.Column - 1, 0) or 0
  local source = type(issue.FromLinter) == 'string' and issue.FromLinter or ''
  local message = type(issue.Text) == 'string' and issue.Text or ''
  local matches = ranges[diagnostic_key(source, line, column, message)]
  if matches and #matches > 0 then
    return table.remove(matches, 1)
  end

  local line_start = 0
  for _ = 1, line do
    local newline = text:find('\n', line_start + 1, true)
    if not newline then
      break
    end
    line_start = newline
  end
  local position_at_issue = offsets.to_position(text, line_start + column, 'utf-8')
  return { start = position_at_issue, ['end'] = vim.deepcopy(position_at_issue) }
end

local function decode(value)
  if type(value) ~= 'string' then
    return ''
  end
  local ok, decoded = pcall(vim.base64.decode, value)
  return ok and decoded or ''
end

local function text_edits(fix, text)
  local edits = {}
  if type(fix) ~= 'table' or type(fix.TextEdits) ~= 'table' then
    return edits
  end
  for _, edit in ipairs(fix.TextEdits) do
    if type(edit) == 'table' and type(edit.Pos) == 'number' and type(edit.End) == 'number' then
      table.insert(edits, {
        range = {
          start = offsets.to_position(text, edit.Pos, 'utf-8'),
          ['end'] = offsets.to_position(text, edit.End, 'utf-8'),
        },
        newText = decode(edit.NewText),
      })
    end
  end
  return edits
end

---Translate golangci-lint v2 JSON SuggestedFixes into native code actions.
---@param context LintActions.AdapterContext
---@return LintActions.Item[]
function M.parse(context)
  if type(context.output) ~= 'string' or context.output == '' then
    return {}
  end

  local ok, result = pcall(vim.json.decode, context.output)
  if not ok or type(result) ~= 'table' or type(result.Issues) ~= 'table' then
    return {}
  end

  local filename = absolute(vim.api.nvim_buf_get_name(context.bufnr), context.cwd)
  local uri = vim.uri_from_bufnr(context.bufnr)
  local text = offsets.buffer_text(context.bufnr)
  local ranges = diagnostic_ranges(context.diagnostics)
  local items = {}

  for _, issue in ipairs(result.Issues) do
    local position = type(issue) == 'table' and type(issue.Pos) == 'table' and issue.Pos or nil
    local reported = position and absolute(position.Filename, context.cwd) or nil
    if filename and reported == filename and type(issue.SuggestedFixes) == 'table' then
      local range = issue_range(issue, text, ranges)
      for _, fix in ipairs(issue.SuggestedFixes) do
        local edits = text_edits(fix, text)
        if #edits > 0 then
          local title = type(fix.Message) == 'string' and fix.Message ~= '' and fix.Message
            or type(issue.Text) == 'string' and issue.Text
            or 'Apply suggested fix'
          if issue.FromLinter and issue.FromLinter ~= '' then
            title = ('%s [%s]'):format(title, issue.FromLinter)
          end
          table.insert(items, {
            range = range,
            action = {
              title = title,
              kind = 'quickfix',
              edit = {
                documentChanges = {
                  {
                    textDocument = { uri = uri },
                    edits = edits,
                  },
                },
              },
            },
          })
        end
      end
    end
  end

  return items
end

return M
