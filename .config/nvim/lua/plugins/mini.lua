-- https://github.com/nvim-mini/mini.nvim

return {
  'nvim-mini/mini.nvim',
  version = '*',
  config = function()
    require('mini.move').setup()
    require('mini.surround').setup()

    -- mini.pick: ファジーファインダー
    require('mini.pick').setup({
      mappings = {
        choose = '<CR>',
        choose_in_split = '<C-x>',
        choose_in_vsplit = '<C-v>',
        choose_marked = '<C-q>',
        delete_char = '<BS>',
        delete_char_right = '<Del>',
        delete_word = '<C-w>',
        move_down = '<C-j>',
        move_up = '<C-k>',
        scroll_down = '<C-d>',
        scroll_up = '<C-u>',
        stop = '<Esc>',
      },
    })

    -- mini.align: テキスト揃え（ga でトリガー）
    require('mini.align').setup()

    -- mini.splitjoin: 1行 ↔ 複数行の切り替え（gS でトリガー）
    require('mini.splitjoin').setup()

    -- mini.trailspace: 末尾スペースの可視化・削除
    local trailspace = require('mini.trailspace')
    trailspace.setup({
      only_in_normal_buffers = true,
    })
    -- 保存時に末尾スペースを自動削除
    vim.api.nvim_create_autocmd('BufWritePre', {
      callback = function()
        -- 特定のファイルタイプは除外
        local exclude_ft = { 'diff', 'gitcommit', 'markdown' }
        if not vim.tbl_contains(exclude_ft, vim.bo.filetype) then
          trailspace.trim()
        end
      end,
    })

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
