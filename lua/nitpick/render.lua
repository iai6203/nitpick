-- 어노테이션을 화면에 그린다: 범위 하이라이트와 코멘트 가상 줄(virt_lines).
-- 위치 추적용 extmark('nitpick')와 섞이지 않도록 표시는 별도 네임스페이스에 그린다.
local M = {}

local ns = vim.api.nvim_create_namespace('nitpick_render')

-- default = true: 사용자가 colorscheme이나 설정에서 정한 색을 덮어쓰지 않는다.
local function define_highlights()
  vim.api.nvim_set_hl(0, 'NitpickComment', { link = 'DiagnosticUnderlineInfo', default = true })
  vim.api.nvim_set_hl(0, 'NitpickCommentText', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'NitpickDelete', { strikethrough = true, default = true })
end

define_highlights()

-- colorscheme을 바꾸면 :hi clear로 지워지므로 다시 정의한다.
vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('nitpick_render', { clear = true }),
  callback = define_highlights,
})

local function comment_lines(prefix, text)
  local lines = {}
  for _, line in ipairs(vim.split(text, '\n', { plain = true })) do
    table.insert(lines, { { '  ↳ ' .. prefix .. line, 'NitpickCommentText' } })
  end
  return lines
end

-- 첫 줄 위의 가상 줄은 창이 그만큼 위로 스크롤된 상태(topfill)여야 보인다.
-- 이 버퍼를 첫 줄부터 보여 주는 창마다 topfill을 맞춘다.
function M.reveal_top(bufnr, count)
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    vim.api.nvim_win_call(win, function()
      local view = vim.fn.winsaveview()
      if view.topline == 1 and view.topfill < count then
        vim.fn.winrestview({ topline = 1, topfill = count })
      end
    end)
  end
end

--- 버퍼의 표시를 지우고 어노테이션 목록(items)으로 다시 그린다.
---@param bufnr integer
---@param items { kind: string, text: string?, range: integer[]? }[] range는 0부터 센 { start_row, start_col, end_row, end_col }
function M.draw(bufnr, items)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  local top_lines = 0
  for _, item in ipairs(items) do
    if item.kind == 'global' then
      local lines = comment_lines('[전체] ', item.text)
      top_lines = top_lines + #lines
      vim.api.nvim_buf_set_extmark(bufnr, ns, 0, 0, {
        virt_lines = lines,
        virt_lines_above = true,
      })
    else
      local start_row, start_col, end_row, end_col = unpack(item.range)
      vim.api.nvim_buf_set_extmark(bufnr, ns, start_row, start_col, {
        end_row = end_row,
        end_col = end_col,
        hl_group = item.kind == 'deletion' and 'NitpickDelete' or 'NitpickComment',
        strict = false,
      })
      if item.kind == 'comment' then
        -- 가상 줄은 extmark의 시작 줄 아래에 붙으므로 범위의 끝 줄에 따로 단다.
        vim.api.nvim_buf_set_extmark(bufnr, ns, end_row, 0, {
          virt_lines = comment_lines('', item.text),
          strict = false,
        })
      end
    end
  end
  if top_lines > 0 then
    M.reveal_top(bufnr, top_lines)
  end
end

function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

return M
