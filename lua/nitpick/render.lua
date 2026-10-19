-- 어노테이션을 화면에 그린다: 범위 하이라이트, 사인 컬럼 막대, 코멘트·라벨 가상 줄(virt_lines).
-- 위치 추적용 extmark('nitpick')와 섞이지 않도록 표시는 별도 네임스페이스에 그린다.
local M = {}

local ns = vim.api.nvim_create_namespace('nitpick_render')

-- 범위 배경색: 진단 글자색을 Normal 배경에 이 비율만큼 섞는다.
local BLEND = 0.2

-- 두 색(0xRRGGBB)을 채널마다 bg × (1 - BLEND) + fg × BLEND로 섞는다.
local function blend(fg, bg)
  local color = 0
  for shift = 16, 0, -8 do
    local f = bit.band(bit.rshift(fg, shift), 0xff)
    local b = bit.band(bit.rshift(bg, shift), 0xff)
    color = color + bit.lshift(math.floor(b * (1 - BLEND) + f * BLEND + 0.5), shift)
  end
  return color
end

-- 그룹(name)의 글자색을 Normal 배경에 섞은 색. 글자색이 없으면 nil.
-- Normal에 배경색이 없으면(투명 배경) 'background'에 따라 검정이나 흰색을 바탕으로 본다.
local function tint(name)
  local fg = vim.api.nvim_get_hl(0, { name = name, link = false }).fg
  if not fg then
    return nil
  end
  local bg = vim.api.nvim_get_hl(0, { name = 'Normal', link = false }).bg
  if not bg then
    bg = vim.o.background == 'light' and 0xffffff or 0x000000
  end
  return blend(fg, bg)
end

-- default = true: 사용자가 colorscheme이나 설정에서 정한 색을 덮어쓰지 않는다.
local function define_highlights()
  local info = tint('DiagnosticInfo')
  if info then
    vim.api.nvim_set_hl(0, 'NitpickComment', { bg = info, default = true })
  else
    vim.api.nvim_set_hl(0, 'NitpickComment', { link = 'DiagnosticUnderlineInfo', default = true })
  end
  vim.api.nvim_set_hl(0, 'NitpickCommentText', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'NitpickDelete', { strikethrough = true, bg = tint('DiagnosticError'), default = true })
  -- 라벨만 다른 색으로 바꿀 수 있도록 따로 두고, 기본은 코멘트와 같은 모양이다.
  vim.api.nvim_set_hl(0, 'NitpickLabel', { link = 'NitpickComment', default = true })
  vim.api.nvim_set_hl(0, 'NitpickLabelText', { link = 'NitpickCommentText', default = true })
  -- 사인 컬럼 막대는 범위 배경에 섞기 전의 진단 글자색을 쓴다.
  vim.api.nvim_set_hl(0, 'NitpickCommentSign', { link = 'DiagnosticInfo', default = true })
  vim.api.nvim_set_hl(0, 'NitpickDeleteSign', { link = 'DiagnosticError', default = true })
  vim.api.nvim_set_hl(0, 'NitpickLabelSign', { link = 'NitpickCommentSign', default = true })
end

define_highlights()

-- colorscheme을 바꾸면 :hi clear로 지워지므로 다시 정의한다.
vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('nitpick_render', { clear = true }),
  callback = define_highlights,
})

local function comment_lines(prefix, text, hl_group)
  local lines = {}
  for _, line in ipairs(vim.split(text, '\n', { plain = true })) do
    table.insert(lines, { { '  ↳ ' .. prefix .. line, hl_group or 'NitpickCommentText' } })
  end
  return lines
end

local RANGE_HIGHLIGHTS = { comment = 'NitpickComment', deletion = 'NitpickDelete', label = 'NitpickLabel' }
local SIGN_HIGHLIGHTS = { comment = 'NitpickCommentSign', deletion = 'NitpickDeleteSign', label = 'NitpickLabelSign' }

-- 사인 컬럼 막대 문자. false면 막대를 그리지 않는다.
local sign = '▎'

--- 설정(setup의 sign)을 반영한다.
---@param value string|false|nil 막대 문자. nil이면 기본값('▎'), false면 끈다
function M.configure(value)
  if value == nil then
    sign = '▎'
  else
    sign = value
  end
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
        hl_group = RANGE_HIGHLIGHTS[item.kind],
        strict = false,
      })
      if sign then
        -- 끝 열이 0이면 끝 줄의 글자는 범위에 들지 않으므로 막대도 그리지 않는다.
        local last_row = (end_row > start_row and end_col == 0) and end_row - 1 or end_row
        for row = start_row, last_row do
          vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
            sign_text = sign,
            sign_hl_group = SIGN_HIGHLIGHTS[item.kind],
            strict = false,
          })
        end
      end
      -- 가상 줄은 extmark의 시작 줄 아래에 붙으므로 범위의 끝 줄에 따로 단다.
      local lines
      if item.kind == 'comment' then
        lines = comment_lines('', item.text)
      elseif item.kind == 'label' then
        lines = comment_lines('', '[' .. item.text .. ']', 'NitpickLabelText')
      end
      if lines then
        vim.api.nvim_buf_set_extmark(bufnr, ns, end_row, 0, { virt_lines = lines, strict = false })
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
