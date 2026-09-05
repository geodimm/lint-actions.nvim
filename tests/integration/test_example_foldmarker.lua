local MiniTest = require('mini.test')
local helpers = require('tests.support.nvim')
local providers = require('lint_actions.providers')

local eq = helpers.eq

local T = helpers.new_set()

---The example ships as documentation, so load it by path rather than by
---package name to keep it honest about being copied into a config.
local function example()
  local chunk = assert(loadfile(vim.fs.joinpath(vim.fn.getcwd(), 'examples', 'foldmarker.lua')))
  return chunk()
end

---@param lines string[]
local function buffer(name, lines)
  local bufnr = helpers.new_buffer(vim.fs.joinpath(vim.fn.getcwd(), 'tests', name), lines)
  vim.bo[bufnr].commentstring = '-- %s'
  return bufnr
end

local function provide(bufnr)
  return example().provide({ bufnr = bufnr, range = helpers.range(0, 0, 0, 0) })
end

T['examples/foldmarker.lua'] = MiniTest.new_set()

T['examples/foldmarker.lua']['offers a modeline for a buffer using fold markers'] = function()
  local bufnr = buffer('example-needs.lua', { 'local a = 1 -- {{{', 'local b = 2', '-- }}}' })

  local items = provide(bufnr)
  eq(#items, 1)
  eq(items[1].range, nil)
  eq(items[1].action.title, 'Add fold marker modeline')
  eq(items[1].action.edit.newText, '-- vim: foldmethod=marker\n')
  eq(items[1].action.edit.range.start.line, 0)
end

T['examples/foldmarker.lua']['stays quiet without fold markers or without a commentstring'] = function()
  eq(provide(buffer('example-plain.lua', { 'local a = 1' })), {})
  eq(provide(buffer('example-open-only.lua', { 'local a = 1 -- {{{' })), {})

  local bufnr = buffer('example-nocomment.lua', { 'a -- {{{', '-- }}}' })
  vim.bo[bufnr].commentstring = ''
  eq(provide(bufnr), {})
end

T['examples/foldmarker.lua']['honours an existing modeline only where Vim would'] = function()
  local within = buffer('example-within.lua', { '-- vim: foldmethod=marker', 'a -- {{{', '-- }}}' })
  eq(provide(within), {})

  -- Vim only scans 'modelines' lines from each end, so one buried in the
  -- middle does not count as already set.
  local filler = { 'a -- {{{' }
  for _ = 1, vim.o.modelines + 2 do
    table.insert(filler, 'filler')
  end
  table.insert(filler, '-- vim: fdm=marker')
  for _ = 1, vim.o.modelines + 2 do
    table.insert(filler, 'filler')
  end
  table.insert(filler, '-- }}}')
  eq(#provide(buffer('example-buried.lua', filler)), 1)
end

T['examples/foldmarker.lua']['inserts after a shebang and encoding line'] = function()
  local bufnr = buffer('example-shebang.lua', { '#!/usr/bin/env lua', '-- coding: utf-8', 'a -- {{{', '-- }}}' })
  eq(provide(bufnr)[1].action.edit.range.start.line, 2)
end

T['examples/foldmarker.lua']['registers a provider that serves the buffer'] = function()
  local bufnr = buffer('example-register.lua', { 'a -- {{{', '-- }}}' })
  example().setup()

  eq(providers.sources(), { 'foldmarker-modeline' })
  local actions = providers.actions(bufnr, helpers.range(0, 0, 0, 0))
  eq(#actions, 1)
  eq(actions[1].title, 'Add fold marker modeline')
end

return T
