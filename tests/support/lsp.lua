local M = vim.tbl_extend('force', {}, require('tests.support.nvim'))

---A missing client, timeout, or protocol error must never look like no actions.
function M.request(bufnr, range, only)
  assert(
    vim.wait(1000, function()
      local client = vim.lsp.get_clients({ bufnr = bufnr, name = 'lint-actions' })[1]
      return client ~= nil and client.initialized == true
    end),
    'lint-actions client did not initialize'
  )

  local responses, err = vim.lsp.buf_request_sync(bufnr, 'textDocument/codeAction', {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    range = range,
    context = { diagnostics = {}, only = only },
  }, 1000)
  assert(responses, err or 'code-action request timed out')
  M.eq(vim.tbl_count(responses), 1)
  local response = select(2, next(responses))
  M.eq(response.err, nil)
  assert(type(response.result) == 'table', 'code-action response must contain an action list')
  return response.result
end

return M
