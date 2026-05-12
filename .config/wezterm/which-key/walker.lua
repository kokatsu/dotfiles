---@diagnostic disable-next-line: assign-type-mismatch
local wezterm = require('wezterm') ---@type Wezterm
local act = wezterm.action

local M = {}

local ROOT = '__root__'

---@class WkLeaf
---@field key string
---@field desc string
---@field action table

---@class WkGroup
---@field key string
---@field desc string
---@field group string
---@field children (WkLeaf|WkGroup)[]
---@field sticky? boolean  -- true: leaf 実行後も key_table を維持 (resize 等)

---@class WkWalked
---@field keys table[]
---@field key_tables table<string, table[]>
---@field choices table<string, table[]>
---@field registry table<string, table>

---@param spec (WkLeaf|WkGroup)[]
---@return WkWalked
function M.walk(spec)
  local result = {
    keys = {},
    key_tables = {},
    choices = { [ROOT] = {} },
    registry = {},
  }
  local id_seq = 0
  local function next_id()
    id_seq = id_seq + 1
    return 'wk_' .. id_seq
  end

  ---@param node WkLeaf|WkGroup
  ---@param parent {group: string, sticky?: boolean}?
  local function add_node(node, parent)
    local is_group = node.group ~= nil
    local action, label, id

    if is_group then
      assert(result.key_tables[node.group] == nil, 'which-key: duplicate group name "' .. node.group .. '"')
      result.key_tables[node.group] = {}
      result.choices[node.group] = {}

      action = act.ActivateKeyTable({ name = node.group, one_shot = false })
      label = '+' .. node.desc
      id = node.group
    else
      id = next_id()
      result.registry[id] = node.action
      label = node.desc
      if parent and not parent.sticky then
        action = act.Multiple({ node.action, act.PopKeyTable })
      else
        action = node.action
      end
    end

    if parent then
      table.insert(result.key_tables[parent.group], { key = node.key, mods = 'NONE', action = action })
    else
      table.insert(result.keys, { key = node.key, mods = 'LEADER', action = action })
    end

    local parent_choices = parent and result.choices[parent.group] or result.choices[ROOT]
    table.insert(parent_choices, { key = node.key, label = label, id = id })

    if is_group then
      local ctx = { group = node.group, sticky = node.sticky }
      for _, child in ipairs(node.children) do
        add_node(child, ctx)
      end
    end
  end

  for _, node in ipairs(spec) do
    add_node(node, nil)
  end
  return result
end

M.ROOT = ROOT
return M
