-- Busted loads this once inside Neovim before collecting any specs.
local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
-- `tests/` is not on the runtimepath, so `require('tests.helpers')` resolves
-- through package.path instead.
package.path = table.concat({ root .. '/?.lua', root .. '/?/init.lua', package.path }, ';')
vim.opt.shadafile = 'NONE'
vim.lsp.log.set_level('off')
