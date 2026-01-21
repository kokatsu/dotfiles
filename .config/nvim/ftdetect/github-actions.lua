-- https://github.com/lttb/gh-actions-language-server

vim.filetype.add({
  pattern = {
    ['.*/%.github[%w/]+workflows[%w/]+.*%.ya?ml'] = 'gha',
  },
})
