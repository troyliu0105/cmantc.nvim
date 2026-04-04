local root = vim.fn.fnamemodify(vim.loop.cwd(), ':p')

vim.opt.rtp:prepend(root)
vim.opt.rtp:prepend(root .. '/.deps/plenary.nvim')
vim.opt.rtp:prepend(root)

vim.cmd('runtime plugin/plenary.vim')
vim.cmd('runtime plugin/cmantic.lua')

require('cmantic').setup()
