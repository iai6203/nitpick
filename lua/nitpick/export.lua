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
    out = out .. '> ' .. ann.text .. '\n'
  elseif ann.kind == 'global' then
    out = out .. 'General feedback about the ' .. subject .. '\n'
    out = out .. '> ' .. ann.text .. '\n'
  end
  return out .. '\n'
end

local function pieces(count)
  return ('%d piece%s'):format(count, count ~= 1 and 's' or '')
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
      for number, ann in ipairs(sort_in_document_order(doc.annotations)) do
        out = out .. render_entry(ann, number, 'document', 3)
      end
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
  for number, ann in ipairs(sort_in_document_order(message.annotations)) do
    out = out .. render_entry(ann, number, 'message', 2)
  end
  out = out .. '---\n'
  -- 원본은 전체 출력에 trimEnd()를 적용한다.
  return (out:gsub('%s+$', ''))
end

return M
