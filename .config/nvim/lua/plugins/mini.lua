-- https://github.com/nvim-mini/mini.nvim

return {
  'nvim-mini/mini.nvim',
  version = '*',
  event = 'VeryLazy',
  config = function()
    require('mini.surround').setup({
      custom_surroundings = {
        c = {
          input = { '```%w*\n().-\n()```' },
          output = function()
            local lang = vim.fn.input('Language: ')
            return { left = '```' .. lang .. '\n', right = '\n```' }
          end,
        },
      },
    })

    -- mini.align: テキスト揃え（ga でトリガー）
    require('mini.align').setup()

    -- mini.splitjoin: 1行 ↔ 複数行の切り替え（gS でトリガー）
    require('mini.splitjoin').setup()

    -- mini.ai: テキストオブジェクト拡張
    local ai = require('mini.ai')
    local gen_spec = ai.gen_spec
    ai.setup({
      n_lines = 500,
      custom_textobjects = {
        -- Treesitterベースのテキストオブジェクト
        f = gen_spec.treesitter({ a = '@function.outer', i = '@function.inner' }),
        c = gen_spec.treesitter({ a = '@class.outer', i = '@class.inner' }),
        -- 'a' は built-in の argument textobject と競合するため 'p' (parameter) を使用
        p = gen_spec.treesitter({ a = '@parameter.outer', i = '@parameter.inner' }),
        o = gen_spec.treesitter({
          a = { '@conditional.outer', '@loop.outer' },
          i = { '@conditional.inner', '@loop.inner' },
        }),
      },
      -- Neovim 0.12 のビルトイン `an`/`in` (treesitter 範囲拡大・縮小) と競合するため無効化
      mappings = {
        around_next = '',
        inside_next = '',
        around_last = '',
        inside_last = '',
      },
      -- 無効なテキストオブジェクトのエラーメッセージを抑制
      silent = true,
    })

    local gen_loader = require('mini.snippets').gen_loader
    local snippets = {
      gen_loader.from_lang(),
    }
    if vim.g.extra_snippets ~= nil then
      vim.list_extend(snippets, vim.g.extra_snippets(gen_loader))
    end
    require('mini.snippets').setup({
      snippets = snippets,
    })

    require('mini.sessions').setup({
      -- 自動的に読み込むかどうか（最後に使用したセッションを自動読み込み）
      autoread = false,
      -- 終了時の保存は下の VimLeavePre で cwd 名のセッションに行う
      -- (mini の autowrite は v:this_session が設定済みのときしか書かない)
      -- セッションの保存先ディレクトリ
      directory = vim.fn.stdpath('data') .. '/sessions',
      -- セッションファイル名の形式
      file = '',
    })

    -- カレントディレクトリベースの自動セッション保存（VimLeavePre時）
    vim.api.nvim_create_autocmd('VimLeavePre', {
      group = vim.api.nvim_create_augroup('AutoSaveSession', { clear = true }),
      callback = function()
        -- バッファが開かれている場合のみ保存
        local bufs = vim.fn.getbufinfo({ buflisted = 1 })
        if #bufs > 0 then
          require('mini.sessions').write(require('utils.session').name(), { force = true })
        end
      end,
    })
  end,
}
