-- nitpick.nvim: Neovim에서 plannotator처럼 리뷰하고 피드백을 클립보드로 복사한다.
local M = {}

--- 설정. 키맵은 만들지 않는다(:Nitpick 명령에 직접 매핑한다).
---@param opts { labels: table[]?, sign: string|false|nil }? labels를 지정하면 기본 라벨 대신 그 목록만 쓴다. sign은 사인 컬럼 막대 문자(기본 '▎', false면 끔)
function M.setup(opts)
  M.options = opts or {}
  require('nitpick.labels').configure(M.options.labels)
  require('nitpick.render').configure(M.options.sign)
end

return M
