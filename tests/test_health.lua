local MiniTest = require('mini.test')
local helpers = require('tests.helpers')
local nvim_lint = require('lint_actions.integrations.nvim_lint')
local providers = require('lint_actions.providers')

local eq = helpers.eq

local function reset()
  nvim_lint._reset()
  providers._reset()
end

local T = MiniTest.new_set({
  hooks = { pre_case = reset, post_case = reset },
})

---Capture what `:checkhealth` would report.
---@return table[]
local function run_check()
  local reported = {}
  local original = vim.health
  MiniTest.finally(function()
    vim.health = original
  end)

  vim.health = setmetatable({}, {
    __index = function(_, level)
      return function(message, advice)
        table.insert(reported, { level = level, message = message, advice = advice })
      end
    end,
  })

  require('lint_actions.health').check()
  return reported
end

---@param reported table[]
---@param pattern string
---@return table
local function find(reported, pattern)
  for _, entry in ipairs(reported) do
    if entry.message:find(pattern, 1, true) then
      return entry
    end
  end
  error(('no health report matching %q'):format(pattern))
end

local function mock_nvim_lint(linters, linters_by_ft)
  helpers.mock_nvim_lint(linters).linters_by_ft = linters_by_ft
end

local function adapter()
  return {
    source = 'tool',
    parse = function()
      return {}
    end,
  }
end

local function linter(cmd)
  return {
    cmd = cmd,
    parser = function(_, _, _)
      return {}
    end,
  }
end

T['check()'] = MiniTest.new_set()

T['check()']['reports the Neovim requirement'] = function()
  eq(find(run_check(), 'Neovim 0.11 or newer').level, 'ok')
end

T['check()']['says so when nothing is attached or registered'] = function()
  local reported = run_check()
  eq(find(reported, 'No nvim-lint integration is attached').level, 'info')
  eq(find(reported, 'No provider is registered').level, 'info')
end

T['check()']['reports the filetypes an attached linter runs on'] = function()
  mock_nvim_lint({ mylint = linter('true') }, { markdown = { 'mylint' }, text = { 'mylint' } })
  nvim_lint.attach({ linter = 'mylint', adapter = adapter() })

  local entry = find(run_check(), 'mylint publishes as tool')
  eq(entry.level, 'ok')
  eq(entry.message, 'mylint publishes as tool, on markdown, text')
end

T['check()']['warns about a linter no filetype runs'] = function()
  mock_nvim_lint({ mylint = linter('true') }, { markdown = { 'other' } })
  nvim_lint.attach({ linter = 'mylint', adapter = adapter() })

  local entry = find(run_check(), 'mylint publishes as tool')
  eq(entry.level, 'warn')
  eq(entry.advice:find('linters_by_ft', 1, true) ~= nil, true)
end

T['check()']['warns about a linter nvim-lint does not know'] = function()
  mock_nvim_lint({}, {})
  nvim_lint.attach({ linter = linter('true'), adapter = adapter() })
  -- A definition passed directly has no name to look up.
  eq(find(run_check(), 'a linter definition publishes as tool').level, 'ok')

  nvim_lint._reset()
  mock_nvim_lint({ mylint = linter('true') }, {})
  nvim_lint.attach({ linter = 'mylint', adapter = adapter() })
  package.loaded.lint.linters = {}
  eq(find(run_check(), 'mylint publishes as tool').advice, 'nvim-lint has no linter named mylint')
end

T['check()']['warns about a missing executable'] = function()
  mock_nvim_lint({ mylint = linter('definitely-not-on-path') }, { markdown = { 'mylint' } })
  nvim_lint.attach({ linter = 'mylint', adapter = adapter() })

  eq(find(run_check(), 'definitely-not-on-path is not executable').level, 'warn')
end

T['check()']['lists registered providers'] = function()
  require('lint_actions').register({
    source = 'my-provider',
    provide = function()
      return {}
    end,
  })

  eq(find(run_check(), 'my-provider is registered').level, 'ok')
end

return T
