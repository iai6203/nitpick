-- nitpick.nvim: Neovim에서 plannotator처럼 리뷰하고 피드백을 클립보드로 복사한다.
local M = {}

--- 설정. 아직 옵션은 없고, 키맵도 만들지 않는다(:Nitpick 명령에 직접 매핑한다).
---@param opts table?
function M.setup(opts)
  M.options = opts or {}
end

return M
