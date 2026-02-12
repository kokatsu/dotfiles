-- copilot-language-server configuration
-- Inline completion via vim.lsp.inline_completion (Neovim 0.12+)
-- https://zenn.dev/vim_jp/articles/a6839f7204a611

---@param bufnr integer,
---@param client vim.lsp.Client
local function sign_in(bufnr, client)
  client:request('signIn', vim.empty_dict(), function(err, result)
    if err then
      vim.notify(err.message, vim.log.levels.ERROR)
      return
    end
    if result.command then
      local code = result.userCode
      local command = result.command
      vim.fn.setreg('+', code)
      vim.fn.setreg('*', code)
      local continue = vim.fn.confirm(
        'Copied your one-time code to clipboard.\n' .. 'Open the browser to complete the sign-in process?',
        '&Yes\n&No'
      )
      if continue == 1 then
        client:exec_cmd(command, { bufnr = bufnr }, function(cmd_err, cmd_result)
          if cmd_err then
            vim.notify(cmd_err.message, vim.log.levels.ERROR)
            return
          end
          if cmd_result.status == 'OK' then
            vim.notify('Signed in as ' .. cmd_result.user .. '.')
          end
        end)
      end
    end

    if result.status == 'PromptUserDeviceFlow' then
      vim.notify('Enter your one-time code ' .. result.userCode .. ' in ' .. result.verificationUri)
    elseif result.status == 'AlreadySignedIn' then
      vim.notify('Already signed in as ' .. result.user .. '.')
    end
  end)
end

---@param client vim.lsp.Client
local function sign_out(_, client)
  client:request('signOut', vim.empty_dict(), function(err, result)
    if err then
      vim.notify(err.message, vim.log.levels.ERROR)
      return
    end
    if result.status == 'NotSignedIn' then
      vim.notify('Not signed in.')
    end
  end)
end

---@type vim.lsp.Config
return {
  cmd = { 'copilot-language-server', '--stdio' },
  root_markers = { '.git' },
  root_dir = function(bufnr, callback)
    -- Disable for sensitive files
    local fname = vim.fs.basename(vim.api.nvim_buf_get_name(bufnr))
    local disable_patterns = { 'env', 'conf', 'local', 'private' }
    local is_disabled = vim.iter(disable_patterns):any(function(pattern)
      return string.match(fname, pattern)
    end)
    if is_disabled then
      return
    end

    -- Only start in git repos
    local root_dir = vim.fs.root(bufnr, { '.git' })
    if root_dir then
      return callback(root_dir)
    end
  end,
  init_options = {
    editorInfo = {
      name = 'Neovim',
      version = tostring(vim.version()),
    },
    editorPluginInfo = {
      name = 'Neovim',
      version = tostring(vim.version()),
    },
  },
  settings = {
    telemetry = {
      telemetryLevel = 'off',
    },
  },
  on_init = function()
    -- Highlights for inline completion suggestions
    local hlc = vim.api.nvim_get_hl(0, { name = 'Comment' })
    vim.api.nvim_set_hl(0, 'ComplHint', vim.tbl_extend('force', hlc, { underline = true }))
    local hlm = vim.api.nvim_get_hl(0, { name = 'MoreMsg' })
    vim.api.nvim_set_hl(0, 'ComplHintMore', vim.tbl_extend('force', hlm, { underline = true }))

    -- Use LspAttach autocmd instead of on_attach to avoid overwriting
    -- nvim-lspconfig's authentication command definitions
    vim.api.nvim_create_autocmd('LspAttach', {
      callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if not client or client.name ~= 'copilot' then
          return
        end

        local bufnr = args.buf

        -- Sign-in / Sign-out commands
        vim.api.nvim_buf_create_user_command(bufnr, 'LspCopilotSignIn', function()
          sign_in(bufnr, client)
        end, { desc = 'Sign in Copilot with GitHub' })
        vim.api.nvim_buf_create_user_command(bufnr, 'LspCopilotSignOut', function()
          sign_out(bufnr, client)
        end, { desc = 'Sign out Copilot with GitHub' })

        -- Enable inline completion for this buffer
        -- Accept is handled by <Tab> in blink.cmp keymap (lua/plugins/blink.lua)
        vim.lsp.inline_completion.enable(true, { bufnr = bufnr })

        -- Next suggestion
        vim.keymap.set('i', '<M-]>', function()
          vim.lsp.inline_completion.select()
        end, { silent = true, buffer = bufnr, desc = 'Next inline completion' })

        -- Previous suggestion
        vim.keymap.set('i', '<M-[>', function()
          vim.lsp.inline_completion.select({ count = -1 * vim.v.count1 })
        end, { silent = true, buffer = bufnr, desc = 'Prev inline completion' })
      end,
    })
  end,
}
