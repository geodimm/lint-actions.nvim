local MiniTest = require('mini.test')
local helpers = require('tests.support.nvim')
local offsets = require('lint_actions.offsets')

local eq = helpers.eq
local T = helpers.new_set()

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
