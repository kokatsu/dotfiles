-- https://github.com/mfussenegger/nvim-lint

return {
  'mfussenegger/nvim-lint',
  ft = 'markdown',
  config = function()
    local lint = require('lint')

    lint.linters.textlint = {
      cmd = 'textlint',
      args = {
        '--format',
        'json',
        '--rule',
        'preset-ja-technical-writing',
        '--stdin',
        '--stdin-filename',
        function()
          return vim.api.nvim_buf_get_name(0)
        end,
      },
      stdin = true,
      stream = 'stdout',
      ignore_exitcode = true,
      parser = function(output, bufnr)
        if output == '' then
          return {}
        end
        local ok, results = pcall(vim.json.decode, output)
        if not ok or not results or not results[1] then
          return {}
        end

        -- textlintの文字カラムをNeovimのバイトオフセットに変換
        local function char_col_to_byte(lnum, char_col)
          local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
          if not line or char_col <= 1 then
            return 0
          end
          local byte_idx = vim.str_byteindex(line, char_col - 1)
          return byte_idx
        end

        local diagnostics = {}
        for _, msg in ipairs(results[1].messages or {}) do
          local lnum = (msg.line or 1) - 1
          local end_line = msg.loc and msg.loc['end'] and msg.loc['end'].line or msg.line or 1
          local end_lnum = end_line - 1
          table.insert(diagnostics, {
            lnum = lnum,
            end_lnum = end_lnum,
            col = char_col_to_byte(lnum, msg.column or 1),
            end_col = char_col_to_byte(
              end_lnum,
              msg.loc and msg.loc['end'] and msg.loc['end'].column or msg.column or 1
            ),
            severity = msg.severity == 2 and vim.diagnostic.severity.ERROR or vim.diagnostic.severity.WARN,
            message = msg.message,
            source = 'textlint',
            code = msg.ruleId,
          })
        end
        return diagnostics
      end,
    }

    lint.linters_by_ft = {
      markdown = { 'textlint' },
    }

    vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost', 'InsertLeave' }, {
      group = vim.api.nvim_create_augroup('NvimLint', { clear = true }),
      pattern = '*.md',
      callback = function()
        lint.try_lint()
      end,
    })
  end,
}
