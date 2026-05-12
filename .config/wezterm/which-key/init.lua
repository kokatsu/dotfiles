-- Inspired by folke/which-key.nvim (Apache-2.0); reimplemented from scratch for WezTerm.
---@diagnostic disable-next-line: assign-type-mismatch
local wezterm = require('wezterm') ---@type Wezterm
local act = wezterm.action

local walker = require('which-key.walker')
local popup = require('which-key.popup')
local status = require('which-key.status')

local M = {}

local EXIT_KEYS = { 'Escape', 'q' }

local state = {
  hint = { key = '?', mods = 'SHIFT' },
  leader = { key = 'a', mods = 'CTRL', timeout_milliseconds = 1500 },
  walked = nil,
  status_enabled = false,
}

---@param ... string
---@return string
local function join_mods(...)
  local parts = {}
  for _, m in ipairs({ ... }) do
    if m ~= nil and m ~= '' then
      table.insert(parts, m)
    end
  end
  if #parts == 0 then
    return 'NONE'
  end
  return table.concat(parts, '|')
end

---@param opts { hint?: {key:string, mods:string}, leader?: table, status?: boolean }?
function M.setup(opts)
  opts = opts or {}
  if opts.hint ~= nil then
    state.hint = opts.hint
  end
  if opts.leader ~= nil then
    state.leader = opts.leader
  end
  if opts.status ~= nil then
    state.status_enabled = opts.status
  end
end

---@param spec table[]
function M.register(spec)
  state.walked = walker.walk(spec)
end

---@param config table
function M.apply(config)
  assert(state.walked, 'which-key.apply: register() を先に呼んでください')

  local show = popup.make_show(state.walked)
  config.leader = state.leader

  config.keys = config.keys or {}
  for _, k in ipairs(state.walked.keys) do
    table.insert(config.keys, k)
  end

  table.insert(config.keys, {
    key = state.hint.key,
    mods = join_mods('LEADER', state.hint.mods),
    action = wezterm.action_callback(function(win, p)
      show(win, p, walker.ROOT)
    end),
  })

  config.key_tables = config.key_tables or {}
  for name, entries in pairs(state.walked.key_tables) do
    -- WezTerm の key_table 内では shifted 記号 (`?` = Shift+/) の SHIFT 扱いが不安定。
    -- 指定 mods と SHIFT 抜きの両方をバインドして取りこぼしを防ぐ。
    local function add_hint(mods)
      table.insert(entries, {
        key = state.hint.key,
        mods = mods,
        action = wezterm.action_callback(function(win, p)
          show(win, p, name)
        end),
      })
    end
    local hint_mods = state.hint.mods or 'NONE'
    add_hint(hint_mods)
    if hint_mods ~= 'NONE' then
      add_hint('NONE')
    end
    for _, k in ipairs(EXIT_KEYS) do
      table.insert(entries, { key = k, mods = 'NONE', action = act.ClearKeyTableStack })
    end

    if config.key_tables[name] then
      wezterm.log_warn('which-key: key_table "' .. name .. '" を上書きします')
    end
    config.key_tables[name] = entries
  end

  if state.status_enabled then
    status.install()
  end
end

return M
