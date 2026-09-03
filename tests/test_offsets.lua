local MiniTest = require('mini.test')
local helpers = require('tests.helpers')
local offsets = require('lint_actions.offsets')

local eq = helpers.eq
local T = MiniTest.new_set()

T['to_position()'] = MiniTest.new_set()

T['to_position()']['converts UTF-8, UTF-16, and CRLF offsets'] = function()
  eq(offsets.to_position('éx\r\ny', 3, 'utf-8'), { line = 0, character = 3 })
  eq(offsets.to_position('éx\r\ny', 3, 'utf-16'), { line = 0, character = 2 })
  eq(offsets.to_position('éx\r\ny', 5, 'utf-8'), { line = 1, character = 0 })
end

T['to_position()']['clamps offsets outside the text'] = function()
  eq(offsets.to_position('abc', -10, 'utf-8'), { line = 0, character = 0 })
  eq(offsets.to_position('abc', 10, 'utf-8'), { line = 0, character = 3 })
end

T['to_position()']['places a newline byte at the start of the next line'] = function()
  eq(offsets.to_position('a\nb', 1, 'utf-8'), { line = 0, character = 1 })
  eq(offsets.to_position('a\nb', 2, 'utf-8'), { line = 1, character = 0 })
end

T['buffer_text()'] = MiniTest.new_set()

T['buffer_text()']['preserves Unix end-of-line settings'] = function()
  local bufnr = helpers.new_buffer('offsets-unix.txt', { 'one', 'two' })
  vim.bo[bufnr].fileformat = 'unix'
  vim.bo[bufnr].endofline = true
  eq(offsets.buffer_text(bufnr), 'one\ntwo\n')

  vim.bo[bufnr].endofline = false
  eq(offsets.buffer_text(bufnr), 'one\ntwo')
end

T['buffer_text()']['preserves DOS line endings'] = function()
  local bufnr = helpers.new_buffer('offsets-dos.txt', { 'one', 'two' })
  vim.bo[bufnr].fileformat = 'dos'
  vim.bo[bufnr].endofline = true
  eq(offsets.buffer_text(bufnr), 'one\r\ntwo\r\n')
end

return T
