local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:append(vim.fs.joinpath(root, 'deps', 'mini.test'))
vim.opt.shadafile = 'NONE'
vim.lsp.log.set_level('off')

require('mini.test').setup({
  collect = { emulate_busted = false },
  execute = { reporter = require('mini.test').gen_reporter.stdout({ group_depth = 3 }) },
})
