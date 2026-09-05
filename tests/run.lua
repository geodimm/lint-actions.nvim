local suite = arg[1] or 'all'
local roots = { unit = 'tests/unit', integration = 'tests/integration', e2e = 'tests/e2e', all = 'tests' }
assert(roots[suite], 'unknown test suite: ' .. suite)
local files = vim.fn.globpath(roots[suite], '**/test_*.lua', true, true)
table.sort(files)
assert(#files > 0, 'no test files found for ' .. suite)
require('mini.test').run({ collect = {
  find_files = function()
    return files
  end,
} })
