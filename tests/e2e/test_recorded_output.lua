local MiniTest = require('mini.test')
local helpers = require('tests.support.lsp')
local lint_actions = require('lint_actions')
local eq = helpers.eq
local T = helpers.new_set()

T['recorded tool output'] = MiniTest.new_set()
for _, tool in ipairs({ 'shellcheck', 'markdownlint' }) do
  T['recorded tool output'][tool .. ' fixes the buffer exactly as the tool does'] = function()
    local extension = tool == 'shellcheck' and 'sh' or 'md'
    local bufnr = helpers.fixture_buffer(tool, 'playground.' .. extension)
    lint_actions.ingest({
      adapter = require('lint_actions.adapters.' .. tool),
      output = helpers.fixture_text(tool, 'output.json'),
      bufnr = bufnr,
      cwd = vim.fs.dirname(helpers.fixture_path(tool, 'playground.' .. extension)),
    })

    local actions = helpers.request(bufnr, helpers.range(0, 0, 100, 0), { 'source.fixAll' })
    eq(#actions, 1)
    eq(actions[1].kind, 'source.fixAll.' .. tool)
    vim.lsp.util.apply_workspace_edit(actions[1].edit, 'utf-8')
    eq(helpers.written_text(bufnr), helpers.fixture_text(tool, 'fixed.' .. extension))
    eq(helpers.request(bufnr, helpers.range(0, 0, 0, 0)), {})
  end
end

-- golangci-lint offers independent suggestions rather than a whole-file fix.
T['recorded tool output']['golangci-lint exposes and applies a selected suggestion'] = function()
  local bufnr = helpers.fixture_buffer('golangci', 'playground.go')
  lint_actions.ingest({
    adapter = require('lint_actions.adapters.golangci'),
    output = helpers.fixture_text('golangci', 'output.json'),
    bufnr = bufnr,
    cwd = vim.fs.dirname(helpers.fixture_path('golangci', 'playground.go')),
  })
  local actions = helpers.request(bufnr, helpers.range(0, 0, 100, 0), { 'quickfix' })
  eq(#actions, 3)
  local by_title = {}
  for _, action in ipairs(actions) do
    by_title[action.title] = action
  end
  local selected = by_title['Use `%w` to format errors [errorlint]']
  assert(selected, 'missing errorlint suggestion')
  eq(#by_title['Simplify strings.Index call using strings.Cut [modernize]'].edit.documentChanges[1].edits, 4)
  eq(
    by_title['"404" can be replaced by http.StatusNotFound [usestdlibvars]'].edit.documentChanges[1].edits[1].newText,
    'http.StatusNotFound'
  )
  vim.lsp.util.apply_workspace_edit(selected.edit, 'utf-8')
  eq(vim.api.nvim_buf_get_lines(bufnr, 22, 23, false)[1], '\t\treturn fmt.Errorf("fetch failed: %w", err)')
end

return T
