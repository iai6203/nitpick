-- 라벨: 미리 정해 둔 코멘트. 원본 plannotator의 quick label을 따른다.
-- 출처: backnotprop/plannotator@87dcec4 packages/ui/utils/quickLabels.ts
local M = {}

-- 원본 DEFAULT_QUICK_LABELS 10개 뒤에 THUMBS_UP_LABEL(👍 Looks good)을 더한다. 원본의 color는 쓰지 않는다.
local DEFAULTS = {
  { emoji = '❓', text = 'Clarify this' },
  {
    emoji = '🗺️',
    text = 'Missing overview',
    tip = 'Provide a narrative overview of what is being built, why it is being built, and how it will be built. Add this before the implementation details.',
  },
  {
    emoji = '🔍',
    text = 'Verify this',
    tip = 'This seems like an assumption. Verify by reading the actual code before proceeding.',
  },
  {
    emoji = '🔬',
    text = 'Give me an example',
    tip = 'This is too abstract. Show a before/after, a sample input/output, or a specific scenario so I can see how this actually works.',
  },
  {
    emoji = '🧬',
    text = 'Match existing patterns',
    tip = 'Search the codebase for existing patterns, components, or utilities that already solve this. Reuse what exists rather than introducing a new approach.',
  },
  {
    emoji = '🔄',
    text = 'Consider alternatives',
    tip = 'Propose 2-3 alternative approaches with trade-offs based on the actual codebase. Also check the Plannotator plans directory (PLANNOTATOR_DATA_DIR or ~/.plannotator/plans/) for prior plan versions that may have already explored or rejected similar approaches.',
  },
  {
    emoji = '📉',
    text = 'Ensure no regression',
    tip = 'Verify that this change will not break existing behavior. Identify what could regress and how to protect against it.',
  },
  {
    emoji = '🚫',
    text = 'Out of scope',
    tip = 'This is not part of the current task. Remove it and stay focused on what was actually requested.',
  },
  { emoji = '🧪', text = 'Needs tests' },
  { emoji = '👍', text = 'Nice approach' },
  { emoji = '👍', text = 'Looks good' },
}

-- id를 생략하면 원본처럼 text의 kebab-case를 쓴다. 예: 'Clarify this' → 'clarify-this'
local function default_id(text)
  return (text:lower():gsub('%s+', '-'))
end

-- 설정한 라벨에 id를 채운다. 잘못된 항목(text 없음, id 중복)은 알리고 뺀다.
local function normalize(list)
  local result, seen = {}, {}
  for index, label in ipairs(list) do
    local problem
    if type(label.text) ~= 'string' or label.text == '' then
      problem = 'text가 없습니다.'
    else
      local id = label.id or default_id(label.text)
      if seen[id] then
        problem = ('id가 중복됩니다(%s).'):format(id)
      else
        seen[id] = true
        table.insert(result, { id = id, emoji = label.emoji, text = label.text, tip = label.tip })
      end
    end
    if problem then
      vim.notify(('nitpick: labels[%d] 항목을 건너뜁니다: %s'):format(index, problem), vim.log.levels.ERROR)
    end
  end
  return result
end

local current = normalize(DEFAULTS)

--- 라벨 목록을 바꾼다. nil이면 기본 라벨을 쓴다. 기본 목록과 합치지 않는다.
---@param list table[]?
function M.configure(list)
  current = normalize(list or DEFAULTS)
end

--- 지금 쓸 라벨 목록: { { id, emoji, text, tip? }, ... }
---@return table[]
function M.list()
  return current
end

---@return table?
function M.find(id)
  for _, label in ipairs(current) do
    if label.id == id then
      return label
    end
  end
  return nil
end

--- 피드백과 화면에 쓰는 라벨 본문. 예: '❓ Clarify this'
---@return string
function M.display(label)
  if label.emoji and label.emoji ~= '' then
    return label.emoji .. ' ' .. label.text
  end
  return label.text
end

return M
