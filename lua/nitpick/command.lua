-- :Nitpick {sub} 명령. 키맵은 만들지 않고, 사용자가 이 명령에 직접 키를 매핑한다.
local labels = require('nitpick.labels')
local review = require('nitpick.review')

local M = {}

-- 명령의 범위를 리뷰 범위(range) = { start_line, start_col, end_line, end_col }로 바꾼다.
-- visual 글자 단위(v)로 고른 범위면 선택한 글자만, 아니면 줄 전체를 쓴다.
local function command_range(args)
  local line1, line2 = args.line1, args.line2
  if args.range == 0 then
    line1 = vim.api.nvim_win_get_cursor(0)[1]
    line2 = line1
  end
  local start_pos, end_pos = vim.fn.getpos("'<"), vim.fn.getpos("'>")
  if args.range > 0 and vim.fn.visualmode() == 'v' and start_pos[2] == line1 and end_pos[2] == line2 then
    local end_line = vim.fn.getline(line2)
    -- '> 의 열은 마지막 글자의 첫 바이트(1부터)다. 그 글자의 끝까지 포함하도록 늘린다.
    local end_col = math.min(end_pos[3], #end_line)
    if end_col > 0 then
      end_col = end_col + vim.str_utf_end(end_line, end_col)
    end
    return { line1, start_pos[3] - 1, line2, end_col }
  end
  return { line1, 0, line2, #vim.fn.getline(line2) }
end

-- 코멘트 내용을 인자에서 읽고, 없으면 여러 줄 입력창(nitpick.textarea)으로 받는다.
-- 입력창은 비동기이므로 버퍼를 먼저 잡아 두고 그 버퍼에서 on_text를 실행한다.
local function with_text(text, input_opts, on_text)
  if text ~= '' then
    on_text(text)
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  require('nitpick.textarea').open(input_opts, function(input)
    if input == nil or input == '' or not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    vim.api.nvim_buf_call(bufnr, function()
      on_text(input)
    end)
  end)
end

-- 후보가 하나면 바로, 여럿이면 고르는 창(vim.ui.select)에서 고른 어노테이션으로 on_choice를 실행한다.
-- 어노테이션은 자기 버퍼를 알고 있으므로 nvim_buf_call로 감싸지 않는다. 감싸면 on_choice에서 연
-- 입력창의 포커스를 nvim_buf_call이 원래 창으로 되돌려 버린다.
local function choose(candidates, prompt, on_choice)
  if #candidates == 1 then
    on_choice(candidates[1])
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  vim.ui.select(candidates, { prompt = prompt, format_item = review.describe }, function(ann)
    if ann ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
      on_choice(ann)
    end
  end)
end

local function open_message_buffer()
  vim.cmd('tabnew')
  local bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].bufhidden = 'hide'
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = 'markdown'
  review.mark_message_buffer(bufnr)
end

local subcommands = {
  comment = function(args, text)
    local range = command_range(args)
    with_text(text, { prompt = 'Nitpick comment: ' }, function(input)
      review.comment(range, input)
    end)
  end,
  delete = function(args)
    review.delete(command_range(args))
  end,
  label = function(args, id)
    local range = command_range(args)
    if id ~= '' then
      local label = labels.find(id)
      if not label then
        local ids = vim.tbl_map(function(l) return l.id end, labels.list())
        vim.notify(('nitpick: 알 수 없는 라벨입니다: %s (%s)'):format(id, table.concat(ids, ', ')), vim.log.levels.ERROR)
        return
      end
      review.label(range, label)
      return
    end
    if #labels.list() == 0 then
      vim.notify('nitpick: 라벨이 없습니다.', vim.log.levels.WARN)
      return
    end
    -- 고르는 창은 비동기일 수 있으므로 버퍼를 먼저 잡아 두고 그 버퍼에서 라벨을 단다.
    local bufnr = vim.api.nvim_get_current_buf()
    vim.ui.select(labels.list(), { prompt = 'Nitpick label: ', format_item = labels.display }, function(label)
      if label == nil or not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      vim.api.nvim_buf_call(bufnr, function()
        review.label(range, label)
      end)
    end)
  end,
  global = function(_, text)
    with_text(text, { prompt = 'Nitpick global comment: ' }, review.global)
  end,
  edit = function(_, text)
    local candidates = review.comments_at_cursor()
    if #candidates == 0 then
      vim.notify('nitpick: 커서 위치에 코멘트가 없습니다.', vim.log.levels.WARN)
      return
    end
    choose(candidates, 'Nitpick edit: ', function(ann)
      with_text(text, { prompt = 'Nitpick edit: ', default = ann.text }, function(input)
        review.edit(ann, input)
      end)
    end)
  end,
  remove = function()
    local candidates = review.annotations_at_cursor()
    if #candidates == 0 then
      vim.notify('nitpick: 커서 위치에 어노테이션이 없습니다.', vim.log.levels.WARN)
      return
    end
    choose(candidates, 'Nitpick remove: ', review.remove)
  end,
  clear = function()
    review.clear()
  end,
  copy = function()
    require('nitpick.copy').copy()
  end,
  paste = function()
    open_message_buffer()
  end,
}

M.names = vim.tbl_keys(subcommands)
table.sort(M.names)

--- :Nitpick 명령을 실행한다(nvim_create_user_command의 args).
function M.run(args)
  local name, text = args.args:match('^(%S*)%s*(.-)%s*$')
  local subcommand = subcommands[name]
  if not subcommand then
    vim.notify(('nitpick: 알 수 없는 명령입니다: %s (%s)'):format(name, table.concat(M.names, ', ')), vim.log.levels.ERROR)
    return
  end
  subcommand(args, text)
end

function M.complete(arg_lead, cmd_line)
  -- 첫 번째 인자(하위 명령)를 완성하고, label 다음 인자는 라벨 id로 완성한다.
  local candidates = M.names
  local name = cmd_line:match('Nitpick%s+(%S+)%s')
  if name == 'label' then
    candidates = vim.tbl_map(function(label) return label.id end, labels.list())
  elseif name then
    return {}
  end
  return vim.tbl_filter(function(candidate)
    return vim.startswith(candidate, arg_lead)
  end, candidates)
end

return M
