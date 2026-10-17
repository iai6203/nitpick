-- 여러 파일에 걸친 리뷰 상태. 위치는 extmark가 들고 있어서 편집을 따라간다.
local export = require('nitpick.export')
local render = require('nitpick.render')

local M = {}

local ns = vim.api.nvim_create_namespace('nitpick')

-- 버퍼의 표시를 다시 그린다. 아래에서 정의한다.
local redraw

-- 처음 어노테이션을 단 순서대로 쌓이는 문서 목록.
-- 파일 문서 = { path = 절대 경로, annotations = { { kind, text, original_text, bufnr, mark_id }, ... } }
-- 메시지 문서 = { message_buf = 버퍼 번호, annotations = ... } — :Nitpick paste로 연 버퍼
local documents = {}

local function document_for(key, value)
  for _, doc in ipairs(documents) do
    if doc[key] == value then
      return doc
    end
  end
  local doc = { [key] = value, annotations = {} }
  table.insert(documents, doc)
  return doc
end

--- 버퍼를 메시지 버퍼로 표시한다. 이 버퍼의 어노테이션은 메시지 형식으로 직렬화된다.
function M.mark_message_buffer(bufnr)
  vim.b[bufnr].nitpick_message = true
end

-- 리뷰할 수 있는 파일 버퍼면 절대 경로를, 아니면 nil을 돌려준다.
local function reviewable_path(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' or vim.bo[bufnr].buftype ~= '' then
    return nil
  end
  return vim.fn.fnamemodify(name, ':p')
end

-- 현재 버퍼의 어노테이션이 들어갈 문서. 리뷰할 수 없는 버퍼면 nil.
local function current_document(bufnr)
  if vim.b[bufnr].nitpick_message then
    return document_for('message_buf', bufnr)
  end
  local path = reviewable_path(bufnr)
  return path and document_for('path', path)
end

-- 어노테이션을 단 순서. 범위가 같은 후보 중 나중에 단 것을 앞에 두는 데 쓴다.
local next_seq = 0

local function add(ann, range)
  local bufnr = vim.api.nvim_get_current_buf()
  local doc = current_document(bufnr)
  if not doc then
    vim.notify('nitpick: 파일 버퍼나 :Nitpick paste 버퍼에서만 리뷰할 수 있습니다.', vim.log.levels.WARN)
    return false
  end
  if range then
    local start_row, start_col, end_row, end_col = range[1] - 1, range[2], range[3] - 1, range[4]
    ann.original_text = table.concat(vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col, {}), '\n')
    ann.mark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, start_row, start_col, { end_row = end_row, end_col = end_col })
  end
  ann.bufnr = bufnr
  next_seq = next_seq + 1
  ann.seq = next_seq
  table.insert(doc.annotations, ann)
  redraw(bufnr)
  return true
end

-- 어노테이션의 현재 범위를 0부터 시작하는 (start_row, start_col, end_row, end_col)로 읽는다.
-- 버퍼가 언로드되어 extmark가 없으면 언로드 직전에 저장해 둔 범위(saved_range)를 쓴다.
local function mark_range(ann)
  if ann.saved_range then
    return unpack(ann.saved_range)
  end
  local mark = vim.api.nvim_buf_get_extmark_by_id(ann.bufnr, ns, ann.mark_id, { details = true })
  local details = mark[3]
  return mark[1], mark[2], details.end_row or mark[1], details.end_col or mark[2]
end

-- 어노테이션의 현재 위치를 1부터 시작하는 줄 범위로 읽는다.
local function position(ann)
  local start_row, start_col, end_row, end_col = mark_range(ann)
  -- 끝 열이 0이면 끝 줄의 글자는 범위에 들지 않는다.
  if end_row > start_row and end_col == 0 then
    end_row = end_row - 1
  end
  return start_row + 1, start_col, end_row + 1
end

local function each_positioned(fn)
  for _, doc in ipairs(documents) do
    for _, ann in ipairs(doc.annotations) do
      if ann.mark_id or ann.saved_range then
        fn(doc, ann)
      end
    end
  end
end

function redraw(bufnr)
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  local items = {}
  for _, doc in ipairs(documents) do
    for _, ann in ipairs(doc.annotations) do
      if ann.bufnr == bufnr then
        local range = ann.mark_id and { mark_range(ann) } or nil
        if range or ann.kind == 'global' then
          table.insert(items, { kind = ann.kind, text = ann.text, range = range })
        end
      end
    end
  end
  render.draw(bufnr, items)
end

local group = vim.api.nvim_create_augroup('nitpick', { clear = true })

-- 버퍼를 닫으면(:bdelete 등) extmark가 사라지므로 직전 범위를 저장해 둔다.
vim.api.nvim_create_autocmd('BufUnload', {
  group = group,
  callback = function(args)
    each_positioned(function(_, ann)
      if ann.bufnr == args.buf and ann.mark_id then
        ann.saved_range = { mark_range(ann) }
        ann.mark_id = nil
      end
    end)
  end,
})

-- 같은 파일을 다시 읽으면 저장해 둔 범위로 extmark를 복원한다.
vim.api.nvim_create_autocmd('BufReadPost', {
  group = group,
  callback = function(args)
    local path = reviewable_path(args.buf)
    if not path then
      return
    end
    each_positioned(function(doc, ann)
      if doc.path == path and ann.saved_range then
        local start_row, start_col, end_row, end_col = unpack(ann.saved_range)
        ann.mark_id = vim.api.nvim_buf_set_extmark(args.buf, ns, start_row, start_col, {
          end_row = end_row,
          end_col = end_col,
          -- 디스크의 파일이 그 사이에 짧아졌어도 복원이 실패하지 않게 한다.
          strict = false,
        })
        ann.saved_range = nil
      end
    end)
    -- 버퍼 번호가 바뀌었을 수 있으므로 파일 전체 코멘트까지 모두 새 버퍼로 옮긴다.
    for _, doc in ipairs(documents) do
      if doc.path == path then
        for _, ann in ipairs(doc.annotations) do
          ann.bufnr = args.buf
        end
      end
    end
    redraw(args.buf)
  end,
})

-- 버퍼를 창에 다시 띄우면 창의 스크롤(topfill)이 초기화되므로 다시 그려 첫 줄 위 가상 줄을 보이게 한다.
vim.api.nvim_create_autocmd('BufWinEnter', {
  group = group,
  callback = function(args)
    redraw(args.buf)
  end,
})

-- 커서(0부터 센 row, col)가 범위 안에 드는지. 빈 범위는 그 위치에 커서가 있을 때 안에 든다.
local function contains(start_row, start_col, end_row, end_col, row, col)
  local after_start = row > start_row or (row == start_row and col >= start_col)
  local before_end = row < end_row or (row == end_row and col < end_col)
  local empty = start_row == end_row and start_col == end_col
  return after_start and (before_end or (empty and row == start_row and col == start_col))
end

--- 커서 위치의 후보 어노테이션. 가장 유력한 후보가 먼저 온다.
--- 커서 줄을 범위에 포함하는 어노테이션이 후보이고, 커서가 첫 줄에 있으면 파일 전체 코멘트도 맨 뒤에 들어간다.
--- 순서: 커서 열까지 범위 안에 드는 것 → 줄 수가 적은 것 → 글자 수가 적은 것 → 나중에 단 것
function M.annotations_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line, row, col = cursor[1], cursor[1] - 1, cursor[2]
  local found = {}
  for _, doc in ipairs(documents) do
    for _, ann in ipairs(doc.annotations) do
      if ann.bufnr == bufnr then
        if ann.mark_id or ann.saved_range then
          local start_line, _, end_line = position(ann)
          if start_line <= line and line <= end_line then
            local start_row, start_col, end_row, end_col = mark_range(ann)
            table.insert(found, {
              ann = ann,
              outside = contains(start_row, start_col, end_row, end_col, row, col) and 0 or 1,
              lines = end_line - start_line,
              chars = end_col - start_col,
            })
          end
        elseif ann.kind == 'global' and line == 1 then
          table.insert(found, { ann = ann, global = true })
        end
      end
    end
  end
  table.sort(found, function(a, b)
    if (a.global or false) ~= (b.global or false) then
      return not a.global
    end
    if not a.global then
      if a.outside ~= b.outside then
        return a.outside < b.outside
      end
      if a.lines ~= b.lines then
        return a.lines < b.lines
      end
      if a.chars ~= b.chars then
        return a.chars < b.chars
      end
    end
    return a.ann.seq > b.ann.seq
  end)
  return vim.tbl_map(function(item) return item.ann end, found)
end

--- 커서 위치에서 코멘트를 고칠 수 있는 후보. 삭제 표시는 코멘트가 없으므로 빠진다.
function M.comments_at_cursor()
  return vim.tbl_filter(function(ann) return ann.text ~= nil end, M.annotations_at_cursor())
end

--- 고르는 창에 보여 줄 어노테이션 설명. 예: `L3 comment: 내용`, `L1–5 deletion: "원문"`, `[전체] 내용`
---@return string
function M.describe(ann)
  local function first_line(text)
    return vim.split(text, '\n', { plain = true })[1]
  end
  if ann.kind == 'global' then
    return '[전체] ' .. first_line(ann.text)
  end
  local start_line, _, end_line = position(ann)
  local where = start_line == end_line and ('L%d'):format(start_line) or ('L%d–%d'):format(start_line, end_line)
  local content = ann.kind == 'deletion' and ('"%s"'):format(first_line(ann.original_text)) or first_line(ann.text)
  return ('%s %s: %s'):format(where, ann.kind, content)
end

function M.comment(range, text)
  return add({ kind = 'comment', text = text }, range)
end

function M.delete(range)
  return add({ kind = 'deletion' }, range)
end

function M.global(text)
  return add({ kind = 'global', text = text }, nil)
end

--- 어노테이션(annotations_at_cursor가 돌려준 것)을 지운다.
function M.remove(ann)
  for _, doc in ipairs(documents) do
    for index, candidate in ipairs(doc.annotations) do
      if candidate == ann then
        table.remove(doc.annotations, index)
        if ann.mark_id then
          vim.api.nvim_buf_del_extmark(ann.bufnr, ns, ann.mark_id)
        end
        redraw(ann.bufnr)
        return true
      end
    end
  end
  return false
end

--- 어노테이션(annotations_at_cursor가 돌려준 것)의 코멘트를 바꾼다.
function M.edit(ann, text)
  ann.text = text
  redraw(ann.bufnr)
  return true
end

--- 커서 위치에서 가장 유력한 어노테이션을 지운다.
function M.remove_at_cursor()
  local ann = M.annotations_at_cursor()[1]
  return ann ~= nil and M.remove(ann)
end

--- 커서 위치에서 가장 유력한 코멘트. 없으면 nil.
---@return string?
function M.text_at_cursor()
  local ann = M.comments_at_cursor()[1]
  return ann and ann.text
end

--- 커서 위치에서 가장 유력한 코멘트를 바꾼다.
function M.edit_at_cursor(text)
  local ann = M.comments_at_cursor()[1]
  return ann ~= nil and M.edit(ann, text)
end

function M.clear()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    render.clear(bufnr)
  end
  documents = {}
end

--- 어노테이션이 있는 파일 중 저장하지 않은 변경이 있는 파일의 경로(피드백과 같은 표기).
---@return string[]
function M.unsaved_paths()
  local paths = {}
  for _, doc in ipairs(vim.tbl_filter(function(d) return d.path ~= nil end, documents)) do
    for _, ann in ipairs(doc.annotations) do
      if ann.bufnr and vim.api.nvim_buf_is_loaded(ann.bufnr) and vim.bo[ann.bufnr].modified then
        table.insert(paths, vim.fn.fnamemodify(doc.path, ':.'))
        break
      end
    end
  end
  return paths
end

-- 직렬화(nitpick.export)에 넘길 모양으로 어노테이션의 현재 위치를 읽는다.
local function export_annotations(doc)
  local annotations = {}
  for _, ann in ipairs(doc.annotations) do
    local item = { kind = ann.kind, text = ann.text, original_text = ann.original_text }
    if ann.mark_id or ann.saved_range then
      item.start_line, item.start_col, item.end_line = position(ann)
    end
    table.insert(annotations, item)
  end
  return annotations
end

--- 리뷰 피드백 텍스트. 어노테이션이 하나도 없으면 nil.
--- 파일은 파일 리뷰 형식, :Nitpick paste 버퍼는 메시지 리뷰 형식으로 직렬화한다.
---@return string?
function M.feedback()
  local files, file_total, parts = {}, 0, {}
  for _, doc in ipairs(documents) do
    local annotations = export_annotations(doc)
    if doc.path then
      file_total = file_total + #annotations
      -- cwd 안이면 상대 경로, 밖이면 절대 경로가 된다.
      table.insert(files, { path = vim.fn.fnamemodify(doc.path, ':.'), annotations = annotations })
    elseif #annotations > 0 and vim.api.nvim_buf_is_valid(doc.message_buf) then
      local text = table.concat(vim.api.nvim_buf_get_lines(doc.message_buf, 0, -1, false), '\n')
      table.insert(parts, export.message_feedback({ text = text, annotations = annotations }))
    end
  end
  -- 메시지와 파일을 함께 리뷰한 경우의 형식은 v1 범위 밖이다. 내용을 잃지 않도록 이어 붙이기만 한다.
  if file_total > 0 then
    table.insert(parts, export.file_feedback(files))
  end
  if #parts == 0 then
    return nil
  end
  return table.concat(parts, '\n\n')
end

return M
