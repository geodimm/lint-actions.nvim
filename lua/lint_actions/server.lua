local store = require('lint_actions.store')

local M = {}

local client_id

---@param dispatchers vim.lsp.rpc.Dispatchers
---@return vim.lsp.rpc.PublicClient
local function cmd(dispatchers)
  local closing = false
  local exited = false
  local request_id = 0
  local rpc = {}

  local function exit(signal)
    if exited then
      return
    end
    closing = true
    exited = true
    dispatchers.on_exit(0, signal)
  end

  function rpc.request(method, params, callback)
    request_id = request_id + 1

    if method == 'initialize' then
      callback(nil, {
        capabilities = {
          codeActionProvider = true,
          positionEncoding = 'utf-8',
        },
        serverInfo = { name = 'lint-actions.nvim' },
      })
    elseif method == 'textDocument/codeAction' then
      local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
      local only = params.context and params.context.only or nil
      local actions = vim.api.nvim_buf_is_valid(bufnr) and store.actions(bufnr, params.range, only) or {}
      callback(nil, actions)
    elseif method == 'shutdown' then
      callback(nil, nil)
    else
      callback({ code = -32601, message = 'Method not found: ' .. method })
    end

    return true, request_id
  end

  function rpc.notify(method)
    if method == 'exit' then
      exit(0)
    end
    return true
  end

  function rpc.is_closing()
    return closing
  end

  function rpc.terminate()
    exit(15)
  end

  return rpc
end

---Start or reuse the in-process client and attach it to a buffer.
---@param bufnr integer
---@return integer client_id
function M.attach(bufnr)
  local client = client_id and vim.lsp.get_client_by_id(client_id) or nil
  if client and not client:is_stopped() then
    if not vim.lsp.buf_is_attached(bufnr, client_id) then
      assert(vim.lsp.buf_attach_client(bufnr, client_id), 'failed to attach lint-actions LSP client')
    end
    return client_id
  end

  client_id = assert(
    vim.lsp.start({
      name = 'lint-actions',
      cmd = cmd,
      root_dir = nil,
    }, {
      bufnr = bufnr,
      attach = true,
    }),
    'failed to start lint-actions LSP client'
  )
  return client_id
end

---@param dispatchers vim.lsp.rpc.Dispatchers
---@return vim.lsp.rpc.PublicClient
function M._cmd(dispatchers)
  return cmd(dispatchers)
end

return M
