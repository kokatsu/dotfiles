--# selene: allow(undefined_variable) -- Linemode と ui は Yazi が注入するグローバル
require('git'):setup()
require('githead'):setup()
require('full-border'):setup()

function Linemode:size_mtime()
  return ui.Line({ self:size(), ' ', self:mtime() })
end
