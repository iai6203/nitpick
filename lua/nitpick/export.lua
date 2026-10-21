-- 어노테이션을 plannotator와 같은 형식의 피드백 텍스트로 바꾼다.
-- 형식 출처: backnotprop/plannotator@87dcec4 packages/ui/utils/parser.ts
local M = {}

local BUNDLE_TITLE = 'File Feedback'
local BUNDLE_INTRO =
  'The following feedback is on the files under review, one section per file, in the order they were given for review.'

-- 원본처럼 파일 전체 코멘트를 앞에 두고, 나머지는 문서 위치 순서로 정렬한다.
-- 같은 위치끼리는 입력 순서를 유지한다(table.sort는 안정 정렬이 아니므로 순번으로 비교).
local function sort_in_document_order(annotations)
  local indexed = {}
  for i, ann in ipairs(annotations) do
    indexed[i] = { ann = ann, index = i }
  end
  table.sort(indexed, function(a, b)
    local a_global, b_global = a.ann.kind == 'global', b.ann.kind == 'global'
    if a_global ~= b_global then
      return a_global
    end
    if not a_global then
      if a.ann.start_line ~= b.ann.start_line then
        return a.ann.start_line < b.ann.start_line
      end
      local a_col, b_col = a.ann.start_col or 0, b.ann.start_col or 0
      if a_col ~= b_col then
        return a_col < b_col
      end
    end
    return a.index < b.index
  end)
  local sorted = {}
  for i, item in ipairs(indexed) do
    sorted[i] = item.ann
  end
  return sorted
end

local function line_label(ann)
  if ann.kind == 'global' then
    return nil
  end
  if ann.end_line <= ann.start_line then
    return ('line %d'):format(ann.start_line)
  end
  return ('lines %d–%d'):format(ann.start_line, ann.end_line)
end

-- 본문을 인용(>)으로 감싼다. 원본은 앞에 '> '를 한 번만 붙여 둘째 줄부터 인용 밖으로 나가므로,
-- 여기서만 원본과 다르게 모든 줄에 붙인다. 빈 줄은 끝 공백 없이 '>'로 쓴다.
local function quote(text)
  local lines = {}
  for _, line in ipairs(vim.split(text, '\n', { plain = true })) do
    table.insert(lines, line == '' and '>' or '> ' .. line)
  end
  return table.concat(lines, '\n') .. '\n'
end

local function render_entry(ann, number, subject, level)
  local out = ('%s %d. '):format(('#'):rep(level), number)
  local label = line_label(ann)
  if label then
    out = out .. '(' .. label .. ') '
  end
  if ann.kind == 'deletion' then
    out = out .. 'Remove this\n'
    out = out .. '```\n' .. ann.original_text .. '\n```\n'
    out = out .. "> I don't want this in the " .. subject .. '.\n'
  elseif ann.kind == 'comment' then
    out = out .. 'Feedback on: "' .. ann.original_text .. '"\n'
    out = out .. quote(ann.text)
  elseif ann.kind == 'label' then
    -- 원본의 isQuickLabel 코멘트: 코멘트 인용 대신 tip이 있으면 tip을 인용한다.
    out = out .. '[' .. ann.text .. '] Feedback on: "' .. ann.original_text .. '"\n'
    if ann.tip then
      out = out .. quote(ann.tip)
    end
  elseif ann.kind == 'global' then
    out = out .. 'General feedback about the ' .. subject .. '\n'
    out = out .. quote(ann.text)
  end
  return out .. '\n'
end

local function pieces(count)
  return ('%d piece%s'):format(count, count ~= 1 and 's' or '')
end

-- 원본 labelSummaryBlock: 라벨 본문별 개수를 문서 순서에서 처음 나온 순서대로. 라벨이 없으면 ''.
local function label_summary(sorted, level)
  local order, counts = {}, {}
  for _, ann in ipairs(sorted) do
    if ann.kind == 'label' then
      if not counts[ann.text] then
        table.insert(order, ann.text)
        counts[ann.text] = 0
      end
      counts[ann.text] = counts[ann.text] + 1
    end
  end
  if #order == 0 then
    return ''
  end
  local out = ('#'):rep(level) .. ' Label Summary\n\n'
  for _, text in ipairs(order) do
    out = out .. ('- **%s**: %d\n'):format(text, counts[text])
  end
  return out .. '\n'
end

--- 여러 파일의 어노테이션을 원본의 묶음 형식(BUNDLE_DOC_EXPORT_HEADING)으로 직렬화한다.
---@param documents { path: string, annotations: table[] }[] 처음 어노테이션을 단 순서
---@return string
function M.file_feedback(documents)
  local out = '# ' .. BUNDLE_TITLE .. '\n\n' .. BUNDLE_INTRO .. '\n\n'
  for _, doc in ipairs(documents) do
    if #doc.annotations > 0 then
      out = out .. '## ' .. doc.path .. '\n\n'
      out = out .. "I've reviewed this document and have " .. pieces(#doc.annotations) .. ' of feedback:\n\n'
      local sorted = sort_in_document_order(doc.annotations)
      for number, ann in ipairs(sorted) do
        out = out .. render_entry(ann, number, 'document', 3)
      end
      out = out .. label_summary(sorted, 3)
    end
  end
  return out .. '---\n'
end

local MESSAGE_EXCERPT_MAX_CHARS = 1200

-- 원본 excerptMessageText: 바이트가 아니라 글자 수로 자른다.
local function excerpt_message_text(text)
  local trimmed = vim.trim(text)
  if vim.fn.strchars(trimmed) <= MESSAGE_EXCERPT_MAX_CHARS then
    return trimmed
  end
  local cut = vim.fn.strcharpart(trimmed, 0, MESSAGE_EXCERPT_MAX_CHARS):gsub('%s+$', '')
  return cut .. '...'
end

-- 원본 fencedBlock: 본문에 들어 있는 펜스보다 긴 펜스로 감싼다.
local function fenced_block(text, language)
  local fence = '```'
  while text:find(fence, 1, true) do
    fence = fence .. '`'
  end
  return fence .. language .. '\n' .. text .. '\n' .. fence .. '\n'
end

--- 붙여넣은 답변 하나의 어노테이션을 원본 exportMessageAnnotations 형식으로 직렬화한다.
---@param message { text: string, annotations: table[] }
---@return string
function M.message_feedback(message)
  local out = '# Message Feedback\n\n'
    .. 'The following feedback spans 1 assistant message. Each section includes an excerpt of the message it applies to.\n\n'
  out = out .. '## Message 1\n\n'
  out = out .. 'Message excerpt:\n'
  out = out .. fenced_block(excerpt_message_text(message.text), 'markdown') .. '\n'
  out = out .. '# Feedback for Message 1\n\n'
  out = out .. "I've reviewed this message and have " .. pieces(#message.annotations) .. ' of feedback:\n\n'
  local sorted = sort_in_document_order(message.annotations)
  for number, ann in ipairs(sorted) do
    out = out .. render_entry(ann, number, 'message', 2)
  end
  out = out .. '---\n'
  local summary = label_summary(sorted, 2)
  if summary ~= '' then
    out = out .. '\n' .. summary
  end
  -- 원본은 전체 출력에 trimEnd()를 적용한다.
  return (out:gsub('%s+$', ''))
end

return M
