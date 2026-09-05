local M = {}

---Treat Lua nil and JSON null as absent, matching Neovim 0.13's vim.isnil().
---@type fun(value: any): boolean
---@diagnostic disable-next-line: undefined-field
M.isnil = vim.isnil or function(value)
  return value == nil or value == vim.NIL
end

return M
