local MiniTest = require('mini.test')

local M = {}

M.eq = MiniTest.expect.equality

---@param callback function
---@param ... any
---@return any
function M.call(callback, ...)
  return callback(...)
end

function M.expect_error(message, callback)
  MiniTest.expect.error(callback, vim.pesc(message))
end

function M.new_buffer(name, lines)
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, name)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines or {})
  vim.bo[bufnr].modified = false

  MiniTest.finally(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  return bufnr
end

function M.range(start_line, start_character, end_line, end_character)
  return {
    start = { line = start_line, character = start_character },
    ['end'] = { line = end_line, character = end_character },
  }
end

function M.batch(bufnr, source, title, range, kind)
  return {
    bufnr = bufnr,
    uri = vim.uri_from_bufnr(bufnr),
    source = source,
    changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
    version = vim.lsp.util.buf_versions[bufnr],
    items = { { range = range, action = { title = title, kind = kind or 'quickfix' } } },
  }
end

function M.request(bufnr, range, only)
  local responses = vim.lsp.buf_request_sync(bufnr, 'textDocument/codeAction', {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    range = range,
    context = { diagnostics = {}, only = only },
  }, 1000)

  local actions = {}
  for _, response in pairs(responses or {}) do
    vim.list_extend(actions, response.result or {})
  end
  return actions
end

return M
