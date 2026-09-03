local M = {}

function M.check()
  vim.health.start('lint-actions.nvim')

  if vim.fn.has('nvim-0.11') == 1 then
    vim.health.ok('Neovim 0.11 or newer')
  else
    vim.health.error('Neovim 0.11 or newer is required')
  end
end

return M
