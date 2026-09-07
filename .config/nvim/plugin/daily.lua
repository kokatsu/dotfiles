-- 日記コマンド。実体は bin/daily で、ここは引数を日数オフセットに変換して渡すだけ
-- (utils.daily は呼び出し時に require する。scripts/test-nvim-config.lua が
-- --clean で plugin/ だけを読み込むため、トップレベルで lua/ を参照しない)

local function open(offset)
  require('utils.daily').open(offset)
end

--- 'today' / 'tomorrow' / 'yesterday' / 整数 (例: -2, +3) を日数に変換する
---@param input string
---@return integer|nil
local function parse_offset(input)
  if input == '' or input == 'today' then
    return 0
  elseif input == 'tomorrow' then
    return 1
  elseif input == 'yesterday' then
    return -1
  elseif input:match('^[+-]?%d+$') then
    return tonumber(input)
  end
end

vim.api.nvim_create_user_command('Daily', function(args)
  local offset = parse_offset(args.args)
  if not offset then
    vim.notify(
      'Daily: today / tomorrow / yesterday か整数を指定してください: ' .. args.args,
      vim.log.levels.WARN
    )
    return
  end
  open(offset)
end, { desc = 'Open daily note (today / tomorrow / yesterday / N)', nargs = '?' })

vim.api.nvim_create_user_command('Today', function()
  open(0)
end, { desc = "Open today's daily note" })
vim.api.nvim_create_user_command('Tomorrow', function()
  open(1)
end, { desc = "Open tomorrow's daily note" })
vim.api.nvim_create_user_command('Yesterday', function()
  open(-1)
end, { desc = "Open yesterday's daily note" })
