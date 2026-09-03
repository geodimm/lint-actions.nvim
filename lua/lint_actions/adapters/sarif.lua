local offsets = require('lint_actions.offsets')
local paths = require('lint_actions.paths')

local M = { source = 'sarif' }

---@class LintActions.SarifReplacement
---@field start integer Zero-based byte offset in the unmodified artifact.
---@field finish integer Zero-based exclusive byte offset in the unmodified artifact.
---@field text string Replacement text.
---@field order integer Order within the SARIF replacements array.

---@param value any
---@return boolean
local function is_list(value)
  return type(value) == 'table' and vim.islist(value)
end

---@param output any
---@return table[]
local function decode_runs(output)
  if type(output) ~= 'string' or output == '' then
    return {}
  end

  local ok, decoded = pcall(vim.json.decode, output)
  if not ok or type(decoded) ~= 'table' or not is_list(decoded.runs) then
    return {}
  end
  return decoded.runs
end

---@param uri string
---@return string
local function decode_uri_path(uri)
  return (uri:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

---@param run table
---@param id string
---@param seen? table<string, boolean>
---@return string?
local function base_uri(run, id, seen)
  local bases = type(run.originalUriBaseIds) == 'table' and run.originalUriBaseIds or {}
  local location = bases[id]
  if type(location) ~= 'table' then
    return nil
  end

  seen = seen or {}
  if seen[id] then
    return nil
  end
  seen[id] = true

  local uri = type(location.uri) == 'string' and location.uri or ''
  if uri:match('^[%a][%w+.-]*:') then
    return uri
  end
  if type(location.uriBaseId) ~= 'string' then
    return nil
  end

  local parent = base_uri(run, location.uriBaseId, seen)
  return parent and (parent .. uri) or nil
end

---Fill omitted URI fields from an artifact cached in `run.artifacts`.
---@param run table
---@param location table
---@return string? uri
---@return string? uri_base_id
local function location_fields(run, location)
  local cached
  if type(location.index) == 'number' and location.index >= 0 and is_list(run.artifacts) then
    local artifact = run.artifacts[math.floor(location.index) + 1]
    cached = type(artifact) == 'table' and type(artifact.location) == 'table' and artifact.location or nil
  end

  local uri = type(location.uri) == 'string' and location.uri
    or cached and type(cached.uri) == 'string' and cached.uri
    or nil
  local uri_base_id = type(location.uriBaseId) == 'string' and location.uriBaseId
    or cached and type(cached.uriBaseId) == 'string' and cached.uriBaseId
    or nil
  return uri, uri_base_id
end

---Resolve a local artifact location. Non-file URI schemes cannot be edited.
---@param run table
---@param location any
---@param cwd? string
---@return string?
local function artifact_path(run, location, cwd)
  if type(location) ~= 'table' then
    return nil
  end

  local uri, uri_base_id = location_fields(run, location)
  if not uri then
    return nil
  end

  local resolved = uri
  if uri_base_id then
    local base = base_uri(run, uri_base_id)
    if base then
      resolved = base .. uri
    end
  end

  local is_windows_path = resolved:match('^%a:[/\\]')
  local scheme = not is_windows_path and resolved:match('^([%a][%w+.-]*):') or nil
  if scheme then
    if scheme:lower() ~= 'file' then
      return nil
    end
    local ok, filename = pcall(vim.uri_to_fname, resolved)
    return ok and paths.absolute(filename, cwd) or nil
  end

  return paths.absolute(decode_uri_path(resolved), cwd)
end

---@param text string
---@return { start: integer, content: string, full: string }[]
local function text_lines(text)
  local lines = {}
  local start = 1
  while true do
    local newline = text:find('\n', start, true)
    if not newline then
      table.insert(lines, { start = start - 1, content = text:sub(start), full = text:sub(start) })
      return lines
    end

    local content_end = newline - 1
    if content_end >= start and text:sub(content_end, content_end) == '\r' then
      content_end = content_end - 1
    end
    table.insert(lines, {
      start = start - 1,
      content = text:sub(start, content_end),
      full = text:sub(start, newline),
    })
    start = newline + 1
    if start > #text then
      return lines
    end
  end
end

---@param content string
---@param units integer
---@param column_kind any
---@return integer?
local function byte_index(content, units, column_kind)
  local encoding
  if column_kind == 'utf16CodeUnits' then
    encoding = 'utf-16'
  elseif column_kind == 'unicodeCodePoints' then
    encoding = 'utf-32'
  elseif not content:find('[\128-\255]') then
    -- columnKind is required for text runs, but either permitted unit has the
    -- same result for ASCII. Accepting that subset is safe for loose producers.
    encoding = 'utf-32'
  else
    return nil
  end

  local ok, byte = pcall(vim.str_byteindex, content, encoding, units, false)
  return ok and byte or nil
end

---@param text string
---@param lines { start: integer, content: string, full: string }[]
---@param line integer
---@param column integer
---@param column_kind any
---@return integer?
local function line_column_offset(text, lines, line, column, column_kind)
  local record = lines[line]
  if not record or column < 1 then
    return nil
  end
  local byte = byte_index(record.full, column - 1, column_kind)
  if not byte then
    return nil
  end
  return math.min(record.start + byte, #text)
end

---@param text string
---@param character integer
---@return integer?
local function character_offset(text, character)
  local ok, byte = pcall(vim.str_byteindex, text, 'utf-32', character, false)
  return ok and byte or nil
end

---Convert either representation of a SARIF text region to byte offsets.
---@param region any
---@param text string
---@param lines { start: integer, content: string, full: string }[]
---@param column_kind any
---@return integer? start
---@return integer? finish
local function region_offsets(region, text, lines, column_kind)
  if type(region) ~= 'table' then
    return nil
  end

  if type(region.startLine) == 'number' and region.startLine >= 1 then
    local start_line = math.floor(region.startLine)
    local end_line = type(region.endLine) == 'number' and math.floor(region.endLine) or start_line
    local start_column = type(region.startColumn) == 'number' and math.floor(region.startColumn) or 1
    local end_column
    if type(region.endColumn) == 'number' then
      end_column = math.floor(region.endColumn)
    else
      local record = lines[end_line]
      if not record then
        return nil
      end
      end_column = vim.str_utfindex(record.content, column_kind == 'utf16CodeUnits' and 'utf-16' or 'utf-32') + 1
    end

    local start = line_column_offset(text, lines, start_line, start_column, column_kind)
    local finish = line_column_offset(text, lines, end_line, end_column, column_kind)
    if not start or not finish or finish < start then
      return nil
    end
    return start, finish
  end

  if type(region.charOffset) == 'number' and region.charOffset >= 0 then
    local start_character = math.floor(region.charOffset)
    local length = type(region.charLength) == 'number' and math.floor(region.charLength) or 0
    if length < 0 then
      return nil
    end
    local start = character_offset(text, start_character)
    local finish = character_offset(text, start_character + length)
    if not start or not finish then
      return nil
    end
    return start, finish
  end

  return nil
end

---@param path string
---@param current_path string
---@param current_bufnr integer
---@return string?
local function artifact_text(path, current_path, current_bufnr)
  if path == current_path then
    return offsets.buffer_text(current_bufnr)
  end

  local bufnr = vim.fn.bufnr(path)
  if bufnr >= 0 and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
    if vim.bo[bufnr].modified then
      return nil
    end
    return offsets.buffer_text(bufnr)
  end

  local file = io.open(path, 'rb')
  if not file then
    return nil
  end
  local text = file:read('*a')
  file:close()
  if text:sub(1, 3) == '\239\187\191' then
    text = text:sub(4)
  end
  if not pcall(vim.str_utfindex, text, 'utf-32') then
    return nil
  end
  return text
end

---@param replacements LintActions.SarifReplacement[]
---@return boolean
local function replacements_overlap(replacements)
  for index, left in ipairs(replacements) do
    for right_index = index + 1, #replacements do
      local right = replacements[right_index]
      local overlaps = left.finish > right.start and right.finish > left.start
      local left_inside = left.start == left.finish and left.start > right.start and left.start < right.finish
      local right_inside = right.start == right.finish and right.start > left.start and right.start < left.finish
      if overlaps or left_inside or right_inside then
        return true
      end
    end
  end
  return false
end

---Compile ordered SARIF replacements into one LSP edit. This preserves the
---standard's sequential semantics and avoids ambiguous same-position edits.
---@param text string
---@param replacements LintActions.SarifReplacement[]
---@return lsp.TextEdit?
local function compile_edit(text, replacements)
  if #replacements == 0 or replacements_overlap(replacements) then
    return nil
  end

  local first, last = replacements[1].start, replacements[1].finish
  for _, replacement in ipairs(replacements) do
    first = math.min(first, replacement.start)
    last = math.max(last, replacement.finish)
  end

  local result = text:sub(first + 1, last)
  local shifts = {}
  for _, replacement in ipairs(replacements) do
    local start = replacement.start - first
    local finish = replacement.finish - first
    for _, shift in ipairs(shifts) do
      if shift.at <= replacement.start then
        start = start + shift.by
      end
      if shift.at <= replacement.finish then
        finish = finish + shift.by
      end
    end
    result = result:sub(1, start) .. replacement.text .. result:sub(finish + 1)
    table.insert(shifts, {
      at = replacement.finish,
      by = #replacement.text - (replacement.finish - replacement.start),
    })
  end

  return {
    range = {
      start = offsets.to_position(text, first, 'utf-8'),
      ['end'] = offsets.to_position(text, last, 'utf-8'),
    },
    newText = result,
  }
end

---@param change any
---@param run table
---@param cwd string?
---@param current_path string
---@param current_bufnr integer
---@param cache table<string, string>
---@return string? uri
---@return lsp.TextEdit? edit
local function artifact_edit(change, run, cwd, current_path, current_bufnr, cache)
  if type(change) ~= 'table' or not is_list(change.replacements) or #change.replacements == 0 then
    return nil
  end
  local path = artifact_path(run, change.artifactLocation, cwd)
  if not path then
    return nil
  end

  local text = cache[path]
  if not text then
    local loaded = artifact_text(path, current_path, current_bufnr)
    if not loaded then
      return nil
    end
    text = loaded
    cache[path] = text
  end
  local lines = text_lines(text)
  local replacements = {}
  for order, replacement in ipairs(change.replacements) do
    local inserted = type(replacement) == 'table' and replacement.insertedContent or nil
    if inserted ~= nil and type(inserted) ~= 'table' then
      return nil
    end
    local replacement_text = ''
    if inserted then
      if inserted.binary ~= nil then
        return nil
      end
      if inserted.text ~= nil and type(inserted.text) ~= 'string' then
        return nil
      end
      replacement_text = inserted.text or ''
    end
    local start, finish = region_offsets(replacement.deletedRegion, text, lines, run.columnKind)
    if not start then
      return nil
    end
    table.insert(replacements, {
      start = start,
      finish = finish,
      text = replacement_text,
      order = order,
    })
  end

  return vim.uri_from_fname(path), compile_edit(text, replacements)
end

---@param fix any
---@param run table
---@param cwd string?
---@param current_path string
---@param current_bufnr integer
---@param cache table<string, string>
---@return lsp.WorkspaceEdit?
local function workspace_edit(fix, run, cwd, current_path, current_bufnr, cache)
  if type(fix) ~= 'table' or not is_list(fix.artifactChanges) or #fix.artifactChanges == 0 then
    return nil
  end

  local changes = {}
  for _, change in ipairs(fix.artifactChanges) do
    local uri, edit = artifact_edit(change, run, cwd, current_path, current_bufnr, cache)
    if not uri or not edit or changes[uri] then
      return nil
    end
    changes[uri] = { edit }
  end
  return { changes = changes }
end

---@param message any
---@return string?
local function message_text(message)
  return type(message) == 'table' and type(message.text) == 'string' and message.text ~= '' and message.text or nil
end

---@param result table
---@param fix table
---@return string
local function action_title(result, fix)
  local rule = type(result.ruleId) == 'string' and result.ruleId ~= '' and result.ruleId or nil
  local description = message_text(fix.description)
  if description then
    return rule and not description:find(rule, 1, true) and ('%s [%s]'):format(description, rule) or description
  end

  local message = message_text(result.message)
  if message then
    return rule and ('Fix: %s [%s]'):format(message, rule) or ('Fix: %s'):format(message)
  end
  return rule and ('Fix %s'):format(rule) or 'Apply SARIF fix'
end

---@param result table
---@param run table
---@param current_path string
---@param cwd string?
---@param current_text string
---@return boolean matches
---@return LintActions.Range? range
local function result_location(result, run, current_path, cwd, current_text)
  if not is_list(result.locations) or #result.locations == 0 then
    return false
  end

  local lines = text_lines(current_text)
  for _, location in ipairs(result.locations) do
    local physical = type(location) == 'table' and location.physicalLocation or nil
    if type(physical) == 'table' and artifact_path(run, physical.artifactLocation, cwd) == current_path then
      local start, finish = region_offsets(physical.region, current_text, lines, run.columnKind)
      if start and finish then
        return true,
          {
            start = offsets.to_position(current_text, start, 'utf-8'),
            ['end'] = offsets.to_position(current_text, finish, 'utf-8'),
          }
      end
      return true
    end
  end
  return false
end

---@param fix table
---@param run table
---@param current_path string
---@param cwd string?
---@return boolean
local function fix_changes_current(fix, run, current_path, cwd)
  for _, change in ipairs(is_list(fix.artifactChanges) and fix.artifactChanges or {}) do
    if artifact_path(run, change.artifactLocation, cwd) == current_path then
      return true
    end
  end
  return false
end

---Translate SARIF 2.1.0 `result.fixes` into native code actions. Text fixes
---may change one or several local artifacts; binary and remote fixes are skipped.
---@param context LintActions.AdapterContext
---@return LintActions.Item[]
function M.parse(context)
  if not vim.api.nvim_buf_is_valid(context.bufnr) then
    return {}
  end

  local runs = decode_runs(context.output)
  local current_path = paths.absolute(vim.api.nvim_buf_get_name(context.bufnr), context.cwd)
  if #runs == 0 or not current_path then
    return {}
  end

  local current_text = offsets.buffer_text(context.bufnr)
  local cache = { [current_path] = current_text }
  local items = {}

  for _, run in ipairs(runs) do
    if type(run) == 'table' and is_list(run.results) then
      for _, result in ipairs(run.results) do
        if type(result) == 'table' and is_list(result.fixes) then
          local matches, range = result_location(result, run, current_path, context.cwd, current_text)
          for _, fix in ipairs(result.fixes) do
            if
              matches
              or (not is_list(result.locations) or #result.locations == 0)
                and fix_changes_current(fix, run, current_path, context.cwd)
            then
              local edit = workspace_edit(fix, run, context.cwd, current_path, context.bufnr, cache)
              if edit then
                table.insert(items, {
                  range = range,
                  action = {
                    title = action_title(result, fix),
                    kind = 'quickfix',
                    edit = edit,
                  },
                })
              end
            end
          end
        end
      end
    end
  end

  return items
end

return M
