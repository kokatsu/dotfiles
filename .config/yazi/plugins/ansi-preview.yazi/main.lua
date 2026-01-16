--- ANSI escape codes previewer for Yazi
--- Renders files containing ANSI escape sequences with colors

local M = {}

function M:peek(job)
  local child = Command('cat'):arg({ tostring(job.file.url) }):stdout(Command.PIPED):spawn()

  if not child then
    return
  end

  local limit = job.area.h
  local i, lines = 0, ''

  repeat
    local next, event = child:read_line()
    if event == 1 then
      break
    elseif event ~= 0 then
      break
    end

    i = i + 1
    if i > job.skip then
      lines = lines .. next
    end
  until i >= job.skip + limit

  child:start_kill()

  if lines ~= '' then
    ya.preview_widget(job, ui.Text.parse(lines):area(job.area))
  end
end

function M:seek(job)
  local h = cx.active.current.hovered
  if h and h.url == job.file.url then
    ya.emit('peek', {
      math.max(0, cx.active.preview.skip + job.units),
      only_if = job.file.url,
    })
  end
end

return M
