-- https://github.com/mfussenegger/nvim-lint

return {
  'mfussenegger/nvim-lint',
  event = { 'BufReadPre', 'BufNewFile' },
  config = function()
    local lint = require('lint')

    -- testcase-md linter (*.testcase.md用)
    -- 環境変数 TESTCASE_MD_LINT_PATH でスクリプトパスを指定
    local testcase_lint_path = os.getenv('TESTCASE_MD_LINT_PATH')

    if testcase_lint_path then
      lint.linters.testcase_md = {
        name = 'testcase_md',
        cmd = 'deno',
        stdin = false,
        append_fname = true,
        args = {
          'run',
          '--allow-read',
          testcase_lint_path,
        },
        stream = 'stdout',
        ignore_exitcode = true,
        parser = function(output, _bufnr)
          local diagnostics = {}

          for line in output:gmatch('[^\r\n]+') do
            -- Format: {file}:{line}:{col}: {severity}: {message} [{rule}]
            local _, lnum, col, severity, message, code = line:match('([^:]+):(%d+):(%d+): (%w+): (.+) %[(.+)%]')

            if lnum then
              local sev = vim.diagnostic.severity.INFO
              if severity == 'error' then
                sev = vim.diagnostic.severity.ERROR
              elseif severity == 'warning' then
                sev = vim.diagnostic.severity.WARN
              end

              table.insert(diagnostics, {
                lnum = tonumber(lnum) - 1,
                col = tonumber(col) - 1,
                end_lnum = tonumber(lnum) - 1,
                end_col = tonumber(col) - 1,
                severity = sev,
                message = message,
                source = 'testcase-md',
                code = code,
              })
            end
          end

          return diagnostics
        end,
      }

      -- *.testcase.md パターン用のautocmd
      vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
        pattern = '*.testcase.md',
        callback = function()
          lint.try_lint('testcase_md')
        end,
      })
    end

    -- ファイルタイプごとのlinter設定
    lint.linters_by_ft = {
      -- markdown = {}, -- 必要に応じて追加
    }

    -- 通常のlint (他のfiletypeがあれば)
    vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
      callback = function()
        local ft = vim.bo.filetype
        if lint.linters_by_ft[ft] then
          lint.try_lint()
        end
      end,
    })
  end,
}
