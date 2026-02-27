-- https://github.com/f-person/git-blame.nvim

return {
  'f-person/git-blame.nvim',
  event = 'VeryLazy',
  opts = {
    message_template = ' <summary> • <date> • <author> • <<sha>>',
    date_format = '%m-%d-%Y %H:%M:%S',
    virtual_text_column = 1,
  },
}
