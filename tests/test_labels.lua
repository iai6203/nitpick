-- 라벨 설정(setup의 labels) 테스트
--
-- 라벨은 미리 정해 둔 코멘트다. 원본 plannotator(backnotprop/plannotator@87dcec4)의 quick label을 따른다.
--   기본 라벨: packages/ui/utils/quickLabels.ts의 DEFAULT_QUICK_LABELS 10개 뒤에 THUMBS_UP_LABEL(👍 Looks good)을 더한다.
--   원본의 color는 쓰지 않는다.
--
-- 공개 인터페이스 (제안):
--   require('nitpick').setup({ labels = { { id?, emoji, text, tip? }, ... } })
--     labels를 지정하면 기본 목록과 합치지 않고 대체한다.
--   require('nitpick.labels').list()   지금 쓸 라벨 목록: { { id, emoji, text, tip? }, ... }
--     id를 생략하면 text를 kebab-case로 바꿔 만든다.
--
-- 설정은 child Neovim 안의 모듈 상태이므로 테스트마다 새 child를 띄운다.

local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- 지금 쓸 라벨 목록(list)
local function labels()
  return child.lua('return require("nitpick.labels").list()')
end

local function setup(opts)
  child.lua('require("nitpick").setup(...)', { opts })
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'scripts/minimal_init.lua' })
      child.lua([[
        _G.notified = {}
        vim.notify = function(msg, level) table.insert(_G.notified, { msg = msg, level = level }) end
      ]])
    end,
    post_once = child.stop,
  },
})

T['라벨 설정(labels)'] = MiniTest.new_set()
local S = T['라벨 설정(labels)']

-- emoji, text, tip은 원본과 글자 하나까지 같아야 한다. tip이 없는 라벨에는 tip 키가 없다.
-- id는 원본의 id와 같은 규칙(text의 kebab-case)으로 만든다. 원본의 Looks good id(thumbs-up)는 따르지 않는다.
S['기본 라벨은 원본 기본 라벨 10개 뒤에 👍 Looks good을 더한 11개다'] = function()
  -- Given: setup()을 부르지 않았다.

  -- When
  local result = labels()

  -- Then
  eq(result, {
    { id = 'clarify-this', emoji = '❓', text = 'Clarify this' },
    {
      id = 'missing-overview',
      emoji = '🗺️',
      text = 'Missing overview',
      tip = 'Provide a narrative overview of what is being built, why it is being built, and how it will be built. Add this before the implementation details.',
    },
    {
      id = 'verify-this',
      emoji = '🔍',
      text = 'Verify this',
      tip = 'This seems like an assumption. Verify by reading the actual code before proceeding.',
    },
    {
      id = 'give-me-an-example',
      emoji = '🔬',
      text = 'Give me an example',
      tip = 'This is too abstract. Show a before/after, a sample input/output, or a specific scenario so I can see how this actually works.',
    },
    {
      id = 'match-existing-patterns',
      emoji = '🧬',
      text = 'Match existing patterns',
      tip = 'Search the codebase for existing patterns, components, or utilities that already solve this. Reuse what exists rather than introducing a new approach.',
    },
    {
      id = 'consider-alternatives',
      emoji = '🔄',
      text = 'Consider alternatives',
      tip = 'Propose 2-3 alternative approaches with trade-offs based on the actual codebase. Also check the Plannotator plans directory (PLANNOTATOR_DATA_DIR or ~/.plannotator/plans/) for prior plan versions that may have already explored or rejected similar approaches.',
    },
    {
      id = 'ensure-no-regression',
      emoji = '📉',
      text = 'Ensure no regression',
      tip = 'Verify that this change will not break existing behavior. Identify what could regress and how to protect against it.',
    },
    {
      id = 'out-of-scope',
      emoji = '🚫',
      text = 'Out of scope',
      tip = 'This is not part of the current task. Remove it and stay focused on what was actually requested.',
    },
    { id = 'needs-tests', emoji = '🧪', text = 'Needs tests' },
    { id = 'nice-approach', emoji = '👍', text = 'Nice approach' },
    { id = 'looks-good', emoji = '👍', text = 'Looks good' },
  })
end

S['labels 없이 setup()을 불러도 기본 라벨을 쓴다'] = function()
  -- Given / When: labels 없이 setup()을 부른다.
  setup({})

  -- Then: 기본 라벨 11개가 그대로다. 내용 전체는 위의 기본 라벨 테스트에서 검증한다.
  local result = labels()
  eq(#result, 11)
  eq(result[1].id, 'clarify-this')
  eq(result[11].id, 'looks-good')
end

S['labels를 지정하면 기본 목록과 합치지 않고 지정한 목록만 쓴다'] = function()
  -- Given / When: 라벨 하나만 지정한다.
  setup({ labels = { { emoji = '🐛', text = 'Bug' } } })

  -- Then: 기본 라벨은 하나도 남지 않는다.
  eq(labels(), { { id = 'bug', emoji = '🐛', text = 'Bug' } })
end

S['id를 생략하면 text를 kebab-case로 바꿔 만들고, 지정한 id가 있으면 그것을 쓴다'] = function()
  -- Given / When
  setup({
    labels = {
      { emoji = '🐢', text = 'Needs Perf Check' },
      { id = 'sec', emoji = '🔒', text = 'Security review' },
    },
  })

  -- Then
  eq(labels(), {
    { id = 'needs-perf-check', emoji = '🐢', text = 'Needs Perf Check' },
    { id = 'sec', emoji = '🔒', text = 'Security review' },
  })
end

-- 설정 실수 하나 때문에 라벨 전체를 못 쓰게 되지 않도록 잘못된 항목만 뺀다.
S['잘못된 라벨 항목(text 없음, id 중복)은 빼고 나머지를 쓰며, 뺀 항목마다 ERROR로 알린다'] = function()
  -- Given / When: 2번째 항목은 text가 없고, 3번째 항목은 1번째와 id(bug)가 겹친다.
  setup({
    labels = {
      { emoji = '🐛', text = 'Bug' },
      { emoji = '❔' },
      { id = 'bug', emoji = '🪲', text = 'Another bug' },
      { emoji = '🧹', text = 'Cleanup' },
    },
  })

  -- Then: id가 겹치면 먼저 나온 항목이 남는다.
  eq(labels(), {
    { id = 'bug', emoji = '🐛', text = 'Bug' },
    { id = 'cleanup', emoji = '🧹', text = 'Cleanup' },
  })
  eq(child.lua_get('_G.notified'), {
    { msg = 'nitpick: labels[2] 항목을 건너뜁니다: text가 없습니다.', level = vim.log.levels.ERROR },
    { msg = 'nitpick: labels[3] 항목을 건너뜁니다: id가 중복됩니다(bug).', level = vim.log.levels.ERROR },
  })
end

return T
