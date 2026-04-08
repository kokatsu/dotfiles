-- Smoke tests for custom Neovim plugin/ files
-- Run: nvim --headless --clean -l scripts/test-nvim-config.lua

local errors = {}
local pass_count = 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    pass_count = pass_count + 1
    print("  PASS " .. name)
  else
    table.insert(errors, name .. ": " .. tostring(err))
    print("  FAIL " .. name .. ": " .. tostring(err))
  end
end

local function assert_true(cond, msg)
  if not cond then
    error(msg or "assertion failed")
  end
end

-- Resolve plugin directory from repo root
local plugin_dir = vim.fn.getcwd() .. "/.config/nvim/plugin"
if vim.fn.isdirectory(plugin_dir) == 0 then
  io.stderr:write("ERROR: Run from the dotfiles repository root\n")
  os.exit(1)
end

local plugin_files = vim.fn.glob(plugin_dir .. "/*.lua", false, true)

print("=== Neovim Config Smoke Tests ===")
print("")

-- All plugin/ files load without error
for _, file in ipairs(plugin_files) do
  local name = vim.fn.fnamemodify(file, ":t")
  test("plugin/" .. name .. " loads without error", function()
    vim.cmd.source(file)
  end)
end

print("")

-- move.lua keymaps
for _, m in ipairs({
  { "n", "<M-j>" },
  { "n", "<M-k>" },
  { "n", "<M-h>" },
  { "n", "<M-l>" },
  { "x", "<M-j>" },
  { "x", "<M-k>" },
  { "x", "<M-h>" },
  { "x", "<M-l>" },
}) do
  test(string.format("keymap %s (%s) exists", m[2], m[1]), function()
    assert_true(vim.fn.maparg(m[2], m[1]) ~= "", "keymap not found")
  end)
end

print("")

-- trailspace.lua
test("Trailspace augroup has autocmds", function()
  local autocmds = vim.api.nvim_get_autocmds({ group = "Trailspace" })
  assert_true(#autocmds > 0, "no autocmds in Trailspace group")
end)

test("Trailspace match is added in normal buffers", function()
  vim.cmd("doautocmd BufWinEnter")
  local found = false
  for _, match in ipairs(vim.fn.getmatches()) do
    if match.group == "Trailspace" then
      found = true
      break
    end
  end
  assert_true(found, "Trailspace match not found in window")
end)

test("BufWritePre autocmd exists for trailing whitespace trim", function()
  local autocmds = vim.api.nvim_get_autocmds({ group = "Trailspace", event = "BufWritePre" })
  assert_true(#autocmds > 0, "BufWritePre not found")
end)

test("trailing whitespace is trimmed on BufWritePre", function()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.bo.buftype = ""
  vim.bo.filetype = "lua"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello   ", "world  ", "clean" })
  vim.api.nvim_exec_autocmds("BufWritePre", { buffer = buf })
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  assert_true(lines[1] == "hello", 'line 1: expected "hello", got "' .. lines[1] .. '"')
  assert_true(lines[2] == "world", 'line 2: expected "world", got "' .. lines[2] .. '"')
  assert_true(lines[3] == "clean", 'line 3: expected "clean", got "' .. lines[3] .. '"')
  vim.api.nvim_buf_delete(buf, { force = true })
end)

test("trailing whitespace is NOT trimmed for markdown", function()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.bo.buftype = ""
  vim.bo.filetype = "markdown"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello   ", "world  " })
  vim.api.nvim_exec_autocmds("BufWritePre", { buffer = buf })
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  assert_true(lines[1] == "hello   ", "line 1: trailing spaces were removed")
  assert_true(lines[2] == "world  ", "line 2: trailing spaces were removed")
  vim.api.nvim_buf_delete(buf, { force = true })
end)

-- Results
print("")
local total = pass_count + #errors
print(string.format("=== Results: %d tests, %d passed, %d failed ===", total, pass_count, #errors))

if #errors > 0 then
  print("")
  for _, e in ipairs(errors) do
    print("  FAIL: " .. e)
  end
  os.exit(1)
end

os.exit(0)
