local M = {}

---Convert a zero-based byte offset into an LSP position.
---@param text string
---@param offset integer
---@param encoding 'utf-8'|'utf-16'|'utf-32'
---@return lsp.Position
function M.to_position(text, offset, encoding)
  offset = math.max(0, math.min(offset, #text))
  local row = 0
  local line_start = 1

  while true do
    local newline = text:find('\n', line_start, true)
    if not newline or offset < newline then
      local line_end = newline and newline - 1 or #text
      if line_end >= line_start and text:sub(line_end, line_end) == '\r' then
        line_end = line_end - 1
      end
      local byte_index = math.min(offset - line_start + 1, math.max(line_end - line_start + 1, 0))
      local line = text:sub(line_start, line_end)
      return { line = row, character = vim.str_utfindex(line, encoding, byte_index, false) }
    end
    row = row + 1
    line_start = newline + 1
  end
end

---Return a buffer as text while preserving its configured line endings.
---@param bufnr integer
---@return string
function M.buffer_text(bufnr)
  local separator = vim.bo[bufnr].fileformat == 'dos' and '\r\n' or '\n'
  local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), separator)
  if vim.bo[bufnr].endofline then
    text = text .. separator
  end
  return text
end

return M
