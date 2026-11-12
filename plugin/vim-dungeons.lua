if vim.g.loaded_vimdungeons then
  return
end
vim.g.loaded_vimdungeons = 1

local classes = { 'wanderer', 'fighter', 'thief', 'sage' }

local function class_arg(cmd)
  local c = cmd.fargs[1]
  if c and not vim.tbl_contains(classes, c) then
    vim.notify('VimDungeons: unknown class ' .. c .. ' (' .. table.concat(classes, ', ') .. ')', vim.log.levels.ERROR)
    return false
  end
  return c
end

local function complete_class()
  return classes
end

vim.api.nvim_create_user_command('VimDungeons', function(cmd)
  local class = class_arg(cmd)
  if class == false then
    return
  end
  require('vimdungeons').start({ new = cmd.bang or class ~= nil, class = class, choose = true })
end, {
  bang = true,
  nargs = '?',
  complete = complete_class,
  desc = 'Start the roguelike (resumes a suspend save; ! or a class starts fresh)',
})

vim.api.nvim_create_user_command('VimDungeonsDaily', function(cmd)
  local class = class_arg(cmd)
  if class == false then
    return
  end
  require('vimdungeons').start({ daily = true, class = class, choose = true })
end, { nargs = '?', complete = complete_class, desc = 'Play the daily challenge (dungeon seeded by the date)' })

vim.api.nvim_create_user_command('VimDungeonsHard', function(cmd)
  local class = class_arg(cmd)
  if class == false then
    return
  end
  require('vimdungeons').start({ hard = true, class = class, choose = true })
end, { nargs = '?', complete = complete_class, desc = 'Enter the Abyss (25 floors, no starting supplies)' })

vim.api.nvim_create_user_command('VimDungeonsScores', function()
  require('vimdungeons').scores()
end, { desc = 'Show VimDungeons high scores' })

vim.api.nvim_create_user_command('VimDungeonsDex', function()
  require('vimdungeons').dex()
end, { desc = 'Show the VimDungeons monster codex' })

vim.api.nvim_create_user_command('VimDungeonsAchievements', function()
  require('vimdungeons').achievements()
end, { desc = 'Show VimDungeons achievements' })

vim.api.nvim_create_user_command('VimDungeonsReplay', function(cmd)
  require('vimdungeons').replay_command(cmd.fargs)
end, {
  nargs = '+',
  complete = function(arg_lead, line)
    if #vim.split(line, '%s+', { trimempty = true }) <= 2 and not line:match('%s%S+%s') then
      return vim.tbl_filter(function(s)
        return s:find(arg_lead, 1, true) == 1
      end, { 'export', 'play', 'verify', 'import' })
    end
    return vim.fn.getcompletion(arg_lead, 'file')
  end,
  desc = 'Export, play, verify, or import a VimDungeons replay',
})

vim.api.nvim_create_user_command('VimDungeonsRanking', function(cmd)
  require('vimdungeons').ranking(cmd.fargs[1])
end, { nargs = '?', desc = 'Show the local daily-challenge ranking (default: today)' })
