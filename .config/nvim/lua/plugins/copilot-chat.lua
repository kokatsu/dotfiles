-- https://github.com/CopilotC-Nvim/CopilotChat.nvim

-- https://techblog.sunl.jp/neovim-github-copilot-chat/

return {
  {
    'CopilotC-Nvim/CopilotChat.nvim',
    dependencies = {
      { 'zbirenbaum/copilot.lua' },
      { 'nvim-lua/plenary.nvim' },
    },
    build = 'make tiktoken',
    opts = {},

    config = function()
      require('CopilotChat').setup({
        prompts = {
          Explain = {
            prompt = '選択したコードの説明を日本語で書いてください',
            mapping = '<leader>ce',
          },
          Review = {
            prompt = 'コードを日本語でレビューしてください',
            mapping = '<leader>cr',
          },
          Fix = {
            prompt = 'このコードには問題があります。バグを修正したコードを表示してください。説明は日本語でお願いします',
            mapping = '<leader>cf',
          },
          Optimize = {
            prompt = '選択したコードを最適化し、パフォーマンスと可読性を向上させてください。説明は日本語でお願いします',
            mapping = '<leader>co',
          },
          Docs = {
            prompt = '選択したコードに関するドキュメントコメントを日本語で生成してください',
            mapping = '<leader>cd',
          },
          Tests = {
            prompt = '選択したコードの詳細なユニットテストを書いてください。説明は日本語でお願いします',
            mapping = '<leader>ct',
          },
          Commit = {
            prompt = require('CopilotChat.config.prompts').Commit.prompt,
            mapping = '<leader>cco',
            selection = require('CopilotChat.select').gitdiff,
          },
        },
      })
    end,

    keys = {
      {
        '<leader>cc',
        function()
          require('CopilotChat').toggle()
        end,
        desc = 'CopilotChat - Toggle',
      },
      {
        '<leader>cp',
        function()
          require('CopilotChat').select_prompt()
        end,
        desc = 'CopilotChat - Prompt actions',
      },
    },
  },
}
