-- 여러 줄 입력창: 플로팅 창에 빈 버퍼를 열고, 평소처럼 편집한 내용을 코멘트로 받는다.
-- vim.ui.input과 같은 모양(opts, on_confirm)으로 부르고, 취소하면 on_confirm(nil)을 부른다.
--   확정: <C-s>(insert/normal), <CR>(normal)
--   취소: <Esc> 또는 q(normal), 창을 떠나거나 닫기
local M = {}

local WIDTH = 80
local MIN_HEIGHT = 5

-- 창 크기를 화면에 맞춘다. 내용이 길면 높이를 늘리되 화면의 절반을 넘지 않는다.
local function layout(line_count)
  local columns, rows = vim.o.columns, vim.o.lines - vim.o.cmdheight
  local width = math.max(math.min(WIDTH, columns - 4), 1)
  local height = math.max(math.min(math.max(line_count, MIN_HEIGHT), math.floor(rows / 2)), 1)
  return {
    relative = 'editor',
    width = width,
    height = height,
    row = math.max(math.floor((rows - height) / 2) - 1, 0),
    col = math.max(math.floor((columns - width) / 2), 0),
  }
end

--- 여러 줄 입력창을 연다.
---@param opts { prompt: string?, default: string? }
---@param on_confirm fun(input: string?)
function M.open(opts, on_confirm)
  opts = opts or {}
  local lines = vim.split(opts.default or '', '\n', { plain = true })
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].bufhidden = 'wipe'
  vim.bo[bufnr].filetype = 'markdown'
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  local title = vim.trim((opts.prompt or ''):gsub(':%s*$', ''))
  local config = vim.tbl_extend('force', layout(#lines), {
    style = 'minimal',
    border = 'rounded',
    title = title ~= '' and (' %s '):format(title) or nil,
    title_pos = title ~= '' and 'center' or nil,
    footer = ' <C-s> 확정 · <Esc> 취소 ',
    footer_pos = 'right',
  })
  local win = vim.api.nvim_open_win(bufnr, true, config)
  vim.wo[win].wrap = true

  local done = false
  local function finish(input)
    if done then
      return
    end
    done = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    vim.cmd('stopinsert')
    on_confirm(input)
  end
  local function confirm()
    local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
    finish(vim.trim(text))
  end
  local function cancel()
    finish(nil)
  end

  local map = function(modes, lhs, rhs)
    vim.keymap.set(modes, lhs, rhs, { buffer = bufnr, nowait = true })
  end
  map({ 'n', 'i' }, '<C-s>', confirm)
  map('n', '<CR>', confirm)
  map('n', '<Esc>', cancel)
  map('n', 'q', cancel)

  -- 다른 창으로 옮기거나 :q로 닫으면 취소한다. 확정 콜백이 다른 창을 열 수 있으므로 한 번만 처리한다.
  vim.api.nvim_create_autocmd({ 'WinLeave', 'BufWipeout' }, {
    buffer = bufnr,
    once = true,
    callback = function()
      vim.schedule(cancel)
    end,
  })

  -- 고칠 때는 내용 끝에, 새로 쓸 때는 빈 줄에서 바로 입력을 시작한다.
  vim.api.nvim_win_set_cursor(win, { #lines, #lines[#lines] })
  vim.cmd('startinsert!')
end

return M
