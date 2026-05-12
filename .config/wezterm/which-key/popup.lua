---@diagnostic disable-next-line: assign-type-mismatch
local wezterm = require('wezterm') ---@type Wezterm
local act = wezterm.action
local walker = require('which-key.walker')

local M = {}

local function format_label(c)
  return string.format('[%s]  %s', c.key, c.label)
end

---@param walked WkWalked
---@return fun(window: any, pane: any, group: string)
function M.make_show(walked)
  local show

  show = function(window, pane, group)
    local src = walked.choices[group] or {}
    local choices = {}
    for _, c in ipairs(src) do
      table.insert(choices, { label = format_label(c), id = c.id })
    end

    local title = (group == walker.ROOT) and 'Leader' or ('Leader  ' .. group)

    window:perform_action(
      ---@diagnostic disable-next-line: missing-fields
      act.InputSelector({
        title = title,
        choices = choices,
        -- 起動時から fuzzy 検索モードに入るため alphabet hotkey は表示しない
        fuzzy = true,
        action = wezterm.action_callback(function(win, p, id, _)
          if not id then
            return
          end
          local action = walked.registry[id]
          if action then
            -- popup から leaf 実行時は key_table を完全に抜ける
            win:perform_action(act.Multiple({ action, act.ClearKeyTableStack }), p)
          elseif walked.choices[id] then
            show(win, p, id)
          end
        end),
      }),
      pane
    )
  end

  return show
end

return M
