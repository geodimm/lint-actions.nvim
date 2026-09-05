local MiniTest = require('mini.test')

local M = vim.tbl_extend('force', {}, require('tests.helpers'))

function M.mock_nvim_lint(linters)
  local previous = package.loaded.lint
  package.loaded.lint = {
    linters = linters,
    lint = function(definition)
      return { linter = definition, cancelled = false }
    end,
  }
  MiniTest.finally(function()
    package.loaded.lint = previous
  end)
  return package.loaded.lint
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

---Path of a file under `tests/fixtures/<name>/`.
---@param name string
---@param file string
---@return string
function M.fixture_path(name, file)
  return vim.fs.joinpath(vim.fn.getcwd(), 'tests', 'fixtures', name, file)
end

---Read a fixture file byte for byte. Binary mode keeps a final newline as a
---trailing empty entry, so the result is the file's exact content.
---@param name string
---@param file string
---@return string
function M.fixture_text(name, file)
  return table.concat(vim.fn.readfile(M.fixture_path(name, file), 'b'), '\n')
end

---Render a buffer the way writing it out would, so comparing it against a
---fixture does not depend on how Neovim represents the final newline.
---@param bufnr integer
---@return string
function M.written_text(bufnr)
  local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  return vim.bo[bufnr].endofline and text .. '\n' or text
end

---Load a fixture file into a real buffer so its positions match the file the
---tool was run against.
---@param name string
---@param file string
---@return integer bufnr
function M.fixture_buffer(name, file)
  local bufnr = vim.fn.bufadd(M.fixture_path(name, file))
  vim.fn.bufload(bufnr)

  MiniTest.finally(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  return bufnr
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

---Each stateful case owns its store, providers, buffers, and LSP clients.
function M.reset()
  require('lint_actions.store')._reset()
  require('lint_actions.providers')._reset()
  require('lint_actions.integrations.nvim_lint')._reset()
  local clients = vim.lsp.get_clients({ name = 'lint-actions' })
  for _, client in ipairs(clients) do
    client:stop(true)
  end
  assert(
    vim.wait(1000, function()
      return #vim.lsp.get_clients({ name = 'lint-actions' }) == 0
    end),
    'lint-actions client did not stop'
  )
end

function M.new_set()
  return MiniTest.new_set({ hooks = { pre_case = M.reset, post_case = M.reset } })
end

return M
