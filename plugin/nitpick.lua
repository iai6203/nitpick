if vim.g.loaded_nitpick then
  return
end
vim.g.loaded_nitpick = true

vim.api.nvim_create_user_command('Nitpick', function(args)
  require('nitpick.command').run(args)
end, {
  nargs = '+',
  range = true,
  desc = 'Nitpick review',
  complete = function(arg_lead, cmd_line)
    return require('nitpick.command').complete(arg_lead, cmd_line)
  end,
})
