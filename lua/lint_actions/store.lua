local M = {}

local batches = {}

local function ranges_overlap(left, right)
  return left.start.line <= right['end'].line and right.start.line <= left['end'].line
end

local function kind_matches(kind, only)
  if not only or #only == 0 then
    return true
  end
  if not kind then
    return false
  end

  for _, requested in ipairs(only) do
    if kind == requested or vim.startswith(kind, requested .. '.') then
      return true
    end
  end
  return false
end

---Replace a source's current batch.
---@param batch LintActions.Batch
function M.publish(batch)
  batches[batch.bufnr] = batches[batch.bufnr] or {}
  batches[batch.bufnr][batch.source] = batch
end

---Clear one source, or all sources for a buffer.
---@param bufnr integer
---@param source? string
function M.clear(bufnr, source)
  if not source then
    batches[bufnr] = nil
    return
  end

  local buffer_batches = batches[bufnr]
  if not buffer_batches then
    return
  end
  buffer_batches[source] = nil
  if not next(buffer_batches) then
    batches[bufnr] = nil
  end
end

---Return fresh actions matching an LSP range and optional kind filter.
---@param bufnr integer
---@param range lsp.Range
---@param only? lsp.CodeActionKind[]
---@return lsp.CodeAction[]
function M.actions(bufnr, range, only)
  local actions = {}
  local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  local version = vim.lsp.util.buf_versions[bufnr]
  local stale = {}

  for source, batch in pairs(batches[bufnr] or {}) do
    if batch.changedtick == changedtick and batch.version == version then
      for _, item in ipairs(batch.items) do
        if ranges_overlap(item.range, range) and kind_matches(item.action.kind, only) then
          table.insert(actions, vim.deepcopy(item.action))
        end
      end
    else
      table.insert(stale, source)
    end
  end

  for _, source in ipairs(stale) do
    M.clear(bufnr, source)
  end

  table.sort(actions, function(left, right)
    return left.title < right.title
  end)
  return actions
end

---Reset all state. Intended for tests.
function M._reset()
  batches = {}
end

return M
