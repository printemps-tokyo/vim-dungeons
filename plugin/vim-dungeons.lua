if vim.g.loaded_vimdungeons then
  return
end
vim.g.loaded_vimdungeons = 1

vim.api.nvim_create_user_command('VimDungeons', function(cmd)
  require('vimdungeons').start({ new = cmd.bang })
end, { bang = true, desc = 'Start the roguelike (resumes a suspend save; ! starts fresh)' })

vim.api.nvim_create_user_command('VimDungeonsDaily', function()
  require('vimdungeons').start({ daily = true })
end, { desc = 'Play the daily challenge (dungeon seeded by the date)' })

vim.api.nvim_create_user_command('VimDungeonsHard', function()
  require('vimdungeons').start({ hard = true })
end, { desc = 'Enter the Abyss (25 floors, no starting supplies)' })

vim.api.nvim_create_user_command('VimDungeonsScores', function()
  require('vimdungeons').scores()
end, { desc = 'Show VimDungeons high scores' })

vim.api.nvim_create_user_command('VimDungeonsDex', function()
  require('vimdungeons').dex()
end, { desc = 'Show the VimDungeons monster codex' })

vim.api.nvim_create_user_command('VimDungeonsAchievements', function()
  require('vimdungeons').achievements()
end, { desc = 'Show VimDungeons achievements' })
