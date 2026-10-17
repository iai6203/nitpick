-- 여러 파일에 걸친 리뷰 상태. 위치는 extmark가 들고 있어서 편집을 따라간다.
local export = require('nitpick.export')

local M = {}

local ns = vim.api.nvim_create_namespace('nitpick')

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
  table.insert(doc.annotations, ann)
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
        ann.bufnr = args.buf
        ann.mark_id = vim.api.nvim_buf_set_extmark(args.buf, ns, start_row, start_col, {
          end_row = end_row,
          end_col = end_col,
          -- 디스크의 파일이 그 사이에 짧아졌어도 복원이 실패하지 않게 한다.
          strict = false,
        })
        ann.saved_range = nil
      end
    end)
  end,
})

-- 현재 버퍼에서 커서 줄을 범위에 포함하는 어노테이션의 문서와 위치(index)를 찾는다.
local function find_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  for _, doc in ipairs(documents) do
    for index, ann in ipairs(doc.annotations) do
      if ann.bufnr == bufnr and (ann.mark_id or ann.saved_range) then
        local start_line, _, end_line = position(ann)
        if start_line <= line and line <= end_line then
          return doc, index
        end
      end
    end
  end
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

function M.remove_at_cursor()
  local doc, index = find_at_cursor()
  if not doc then
    return false
  end
  local ann = table.remove(doc.annotations, index)
  if ann.mark_id then
    vim.api.nvim_buf_del_extmark(ann.bufnr, ns, ann.mark_id)
  end
  return true
end

--- 커서 위치 어노테이션의 코멘트. 없거나 코멘트가 없는 어노테이션(삭제 표시)이면 nil.
---@return string?
function M.text_at_cursor()
  local doc, index = find_at_cursor()
  return doc and doc.annotations[index].text
end

function M.edit_at_cursor(text)
  local doc, index = find_at_cursor()
  if not doc then
    return false
  end
  doc.annotations[index].text = text
  return true
end

function M.clear()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
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
