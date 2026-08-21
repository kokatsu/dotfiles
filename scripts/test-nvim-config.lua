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

-- Test clipboard provider: verifies + / * registers without any OS clipboard tool
local clipboard_store = { ["+"] = { { "" }, "v" }, ["*"] = { { "" }, "v" } }
vim.g.clipboard = {
  name = "test",
  copy = {
    ["+"] = function(lines, regtype)
      clipboard_store["+"] = { lines, regtype }
    end,
    ["*"] = function(lines, regtype)
      clipboard_store["*"] = { lines, regtype }
    end,
  },
  paste = {
    ["+"] = function()
      return clipboard_store["+"][1], clipboard_store["+"][2]
    end,
    ["*"] = function()
      return clipboard_store["*"][1], clipboard_store["*"][2]
    end,
  },
}

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
  -- matchadd is deferred via vim.schedule; flush the event loop
  vim.wait(10, function()
    return false
  end)
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

print("")

-- SQL helpers
local codeblock = dofile(vim.fn.getcwd() .. "/.config/nvim/lua/utils/codeblock.lua")
package.loaded["utils.codeblock"] = codeblock
local sql = dofile(vim.fn.getcwd() .. "/.config/nvim/lua/utils/sql.lua")

local function with_buffer(filetype, lines, cursor_line, fn)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.bo.filetype = filetype
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { cursor_line, 0 })
  fn()
  vim.api.nvim_buf_delete(buf, { force = true })
end

test("SQL helper finds enclosing Markdown fenced block", function()
  with_buffer("markdown", { "text", "```sql", "SELECT *", "FROM users;", "```", "text" }, 4, function()
    local line1, line2 = sql.current_query_range()
    assert_true(line1 == 3, "expected block to start at line 3")
    assert_true(line2 == 4, "expected block to end at line 4")
  end)
end)

test("SQL helper finds current paragraph in SQL buffer", function()
  with_buffer("sql", { "SELECT 1;", "", "SELECT *", "FROM users;", "", "SELECT 2;" }, 4, function()
    local line1, line2 = sql.current_query_range()
    assert_true(line1 == 3, "expected paragraph to start at line 3")
    assert_true(line2 == 4, "expected paragraph to end at line 4")
  end)
end)

test("SQL helper ignores unmatched fences outside Markdown", function()
  with_buffer("sql", { "```sql", "example", "", "SELECT 1;" }, 4, function()
    local line1, line2 = sql.current_query_range()
    assert_true(line1 == 4 and line2 == 4, "expected SQL paragraph fallback")
  end)
end)

test("SQL helper rejects Markdown prose", function()
  with_buffer("markdown", { "text", "", "more text" }, 1, function()
    local line1, line2 = sql.current_query_range()
    assert_true(line1 == nil and line2 == nil, "expected no query range")
  end)
end)

test("code block helper yanks contents without fences or language restriction", function()
  with_buffer("markdown", { "~~~lua", "local value = 1", "print(value)", "~~~" }, 2, function()
    codeblock.yank_current()
    assert_true(vim.fn.getreg("+") == "local value = 1\nprint(value)", "unexpected clipboard contents")
  end)
end)

test("code block helper rejects backticks in backtick fence info string", function()
  with_buffer("markdown", { "```foo``` bar", "not a block" }, 2, function()
    local line1, line2, error_kind = codeblock.current_range()
    assert_true(line1 == nil and line2 == nil, "expected no code block range")
    assert_true(error_kind == "not_found", "expected not_found")
  end)
end)

test("code block helper includes the closing fence line as a cursor position", function()
  with_buffer("markdown", { "```json", "{", "}", "```" }, 4, function()
    local line1, line2 = codeblock.current_range()
    assert_true(line1 == 2 and line2 == 3, "expected contents inside closing fence")
  end)
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
