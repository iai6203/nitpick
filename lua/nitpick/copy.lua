-- 리뷰 피드백을 클립보드에 복사한다.
local review = require('nitpick.review')

local M = {}

-- 알림에 쓸 개수. 0개인 종류는 뺀다. 예: '파일 2개, 피드백 3개', '메시지 1개, 피드백 2개'
local function counts()
  local summary = review.summary()
  local parts = {}
  if summary.files > 0 then
    table.insert(parts, ('파일 %d개'):format(summary.files))
  end
  if summary.messages > 0 then
    table.insert(parts, ('메시지 %d개'):format(summary.messages))
  end
  table.insert(parts, ('피드백 %d개'):format(summary.annotations))
  return table.concat(parts, ', ')
end

--- 리뷰 피드백을 클립보드(+)에 복사한다. 클립보드를 쓸 수 없으면 unnamed 레지스터(")에 넣는다.
---@return boolean copied 어노테이션이 없어서 복사하지 않았으면 false
function M.copy()
  local text = review.feedback()
  if not text then
    vim.notify('nitpick: 리뷰 내용이 없습니다.', vim.log.levels.INFO)
    return false
  end

  -- 피드백을 받는 쪽은 디스크의 파일을 읽으므로 줄 번호가 어긋날 수 있다.
  local unsaved = review.unsaved_paths()
  if #unsaved > 0 then
    vim.notify(
      'nitpick: 저장하지 않은 변경이 있어 줄 번호가 디스크의 파일과 다를 수 있습니다: ' .. table.concat(unsaved, ', '),
      vim.log.levels.WARN
    )
  end

  if vim.fn.has('clipboard') == 1 then
    vim.fn.setreg('+', text)
    vim.notify(('nitpick: %s를 클립보드에 복사했습니다.'):format(counts()), vim.log.levels.INFO)
  else
    vim.fn.setreg('"', text)
    vim.notify(
      ('nitpick: 클립보드를 쓸 수 없어 %s를 unnamed 레지스터(")에 넣었습니다. :help clipboard 를 참고해 설정하세요.'):format(
        counts()
      ),
      vim.log.levels.WARN
    )
  end
  return true
end

return M
