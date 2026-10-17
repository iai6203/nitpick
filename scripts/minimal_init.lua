-- 테스트 전용 최소 설정: 사용자 설정 없이 이 플러그인과 mini.test만 불러온다.
vim.opt.runtimepath:append(vim.fn.getcwd())
vim.opt.runtimepath:append(vim.fn.getcwd() .. '/deps/mini.nvim')
require('mini.test').setup()
