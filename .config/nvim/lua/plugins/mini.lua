-- https://github.com/nvim-mini/mini.nvim

return {
  'nvim-mini/mini.nvim',
  version = '*',
  config = function()
    require('mini.move').setup()
    require('mini.surround').setup()

    -- mini.ai: テキストオブジェクト拡張
    local ai = require('mini.ai')
    ai.setup({
      n_lines = 500,
      custom_textobjects = {
        -- Treesitterベースのテキストオブジェクト
        f = ai.gen_spec.treesitter({ a = '@function.outer', i = '@function.inner' }),
        c = ai.gen_spec.treesitter({ a = '@class.outer', i = '@class.inner' }),
        a = ai.gen_spec.treesitter({ a = '@parameter.outer', i = '@parameter.inner' }),
        o = ai.gen_spec.treesitter({
          a = { '@conditional.outer', '@loop.outer' },
          i = { '@conditional.inner', '@loop.inner' },
        }),
      },
    })

    local gen_loader = require('mini.snippets').gen_loader
    local snippets = {
      gen_loader.from_lang(),
    }
    if vim.g.extra_snippets ~= nil then
      snippets = vim.tbl_deep_extend('force', snippets, vim.g.extra_snippets(gen_loader))
    end
    require('mini.snippets').setup({
      snippets = snippets,
    })

    require('mini.sessions').setup({
      -- 自動的に読み込むかどうか（最後に使用したセッションを自動読み込み）
      autoread = false,
      -- Neovim終了時に自動保存するかどうか
      autowrite = true,
      -- セッションの保存先ディレクトリ
      directory = vim.fn.stdpath('data') .. '/sessions',
      -- セッションファイル名の形式
      file = '',
    })

    -- カレントディレクトリベースの自動セッション保存
    local function get_session_name()
      -- カレントディレクトリのパスをセッション名として使用（スラッシュをアンダースコアに変換）
      local cwd = vim.fn.getcwd()
      return cwd:gsub('/', '_'):gsub('^_', '')
    end

    -- 自動セッション保存（VimLeavePre時）
    vim.api.nvim_create_autocmd('VimLeavePre', {
      group = vim.api.nvim_create_augroup('AutoSaveSession', { clear = true }),
      callback = function()
        -- バッファが開かれている場合のみ保存
        local bufs = vim.fn.getbufinfo({ buflisted = 1 })
        if #bufs > 0 then
          local session_name = get_session_name()
          require('mini.sessions').write(session_name, { force = true })
        end
      end,
    })
  end,
}
