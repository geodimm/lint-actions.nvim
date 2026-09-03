local M = {}

---Resolve a path a linter reported against the directory the linter ran in.
---@param path string
---@param cwd? string
---@return string?
function M.absolute(path, cwd)
  if type(path) ~= 'string' or path == '' then
    return nil
  end
  local is_absolute = path:match('^/') or path:match('^%a:[/\\]') or path:match('^[/\\][/\\]')
  if not is_absolute then
    path = vim.fs.joinpath(cwd or vim.uv.cwd(), path)
  end
  return vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
end

return M
