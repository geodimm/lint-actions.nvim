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

function M.range(start_line, start_character, end_line, end_character)
  return {
    start = { line = start_line, character = start_character },
    ['end'] = { line = end_line, character = end_character },
  }
end

return M
