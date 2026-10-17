-- 사용자 명령(:Nitpick)과 설정(setup), 메시지 버퍼 통합 테스트
--
-- 공개 인터페이스 (제안):
--   require('nitpick').setup(opts)   키맵을 만들지 않는다. 명령은 setup 없이도 plugin/nitpick.lua가 만든다.
--   :Nitpick global {text}           현재 파일 전체에 코멘트
--   :[range]Nitpick comment {text}   범위에 코멘트. visual에서 실행하면 선택한 글자 범위를 쓴다
--   :[range]Nitpick delete           범위에 삭제 표시
--   :Nitpick edit {text}             커서 위치의 어노테이션 코멘트 수정
--   :Nitpick remove                  커서 위치의 어노테이션 삭제
--     edit/remove는 커서 위치의 후보가 여럿이면 vim.ui.select로 고르게 한다.
--   :Nitpick clear                   리뷰 초기화
--   :Nitpick copy                    피드백을 클립보드에 복사
--   :Nitpick paste                   답변을 붙여넣을 메시지 버퍼를 연다
--
-- 실제 시스템 클립보드를 건드리지 않도록 child Neovim에는 가짜 클립보드 provider(g:clipboard)를 넣는다.

local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- 여러 줄 문자열을 읽기 쉽게 쓰기 위한 도우미: 각 원소를 줄바꿈으로 잇는다.
local function lines(list)
  return table.concat(list, '\n')
end

-- 파일 리뷰 피드백의 머리말 (tests/test_export.lua 사례 1에서 문자 그대로 검증)
local HEADER = lines({
  '# File Feedback',
  '',
  'The following feedback is on the files under review, one section per file, in the order they were given for review.',
  '',
  '',
})

-- 테스트마다 새로 만드는 임시 프로젝트 디렉터리 (cwd)
local project

local function write_file(path, content_lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  vim.fn.writefile(content_lines, path)
end

local function edit(path)
  child.cmd('edit ' .. vim.fn.fnameescape(path))
end

local function feedback()
  return child.lua('return require("nitpick.review").feedback()')
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'scripts/minimal_init.lua' })
      project = vim.fn.resolve(vim.fn.tempname())
      vim.fn.mkdir(project, 'p')
      child.cmd('cd ' .. vim.fn.fnameescape(project))
      child.lua([[
        _G.clip = { { '' }, 'v' }
        local function copy(lines, regtype) _G.clip = { lines, regtype } end
        local function paste() return _G.clip end
        vim.g.clipboard = { name = 'fake', copy = { ['+'] = copy, ['*'] = copy }, paste = { ['+'] = paste, ['*'] = paste } }
      ]])
    end,
    post_case = function()
      vim.fn.delete(project, 'rf')
    end,
    post_once = child.stop,
  },
})

-- 사례 31 ---------------------------------------------------------------------

T['설정(setup)'] = MiniTest.new_set()

-- 모든 모드의 전역 키맵과 현재 버퍼 키맵을 모은다.
-- Lua 함수(callback)는 RPC로 넘길 수 없으므로 함수가 있는지만 남긴다.
local function all_keymaps()
  return child.lua([[
    local function plain(list)
      for _, map in ipairs(list) do
        map.callback = map.callback ~= nil and 'function' or nil
      end
      return list
    end
    local maps = {}
    for _, mode in ipairs({ 'n', 'v', 'x', 's', 'o', 'i', 'c', 't' }) do
      maps[mode] = { global = plain(vim.api.nvim_get_keymap(mode)), buffer = plain(vim.api.nvim_buf_get_keymap(0, mode)) }
    end
    return maps
  ]])
end

T['설정(setup)']['setup()은 어떤 키맵도 만들지 않는다'] = function()
  -- Given: 플러그인이 로드된 직후의 키맵을 기록해 둔다.
  write_file(project .. '/a.md', { '하나' })
  edit(project .. '/a.md')
  local before = all_keymaps()

  -- When
  child.lua('require("nitpick").setup()')

  -- Then: 키맵이 하나도 늘거나 바뀌지 않았고, 플러그인 로드만으로 생긴 nitpick 키맵도 없다.
  local after = all_keymaps()
  eq(after, before)
  local nitpick_maps = child.lua([[
    local found = {}
    for _, mode in ipairs({ 'n', 'v', 'x', 's', 'o', 'i', 'c', 't' }) do
      for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
        local text = (map.rhs or '') .. (map.desc or '')
        if text:lower():find('nitpick', 1, true) then table.insert(found, mode .. ' ' .. map.lhs) end
      end
    end
    return found
  ]])
  eq(nitpick_maps, {})
end

-- 사례 32 ---------------------------------------------------------------------
-- 모든 기능을 :Nitpick <sub> 명령으로 쓸 수 있다. setup()을 부르지 않은 상태에서 실행한다.

T['명령(:Nitpick)'] = MiniTest.new_set()
local C = T['명령(:Nitpick)']

C[':Nitpick global {text}는 현재 파일 전체에 코멘트를 단다'] = function()
  -- Given
  write_file(project .. '/a.md', { '하나' })
  edit(project .. '/a.md')

  -- When
  child.cmd('Nitpick global 전체적으로 좋아요')

  -- Then
  eq(
    feedback(),
    HEADER
      .. lines({
        '## a.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. General feedback about the document',
        '> 전체적으로 좋아요',
        '',
        '---',
        '',
      })
  )
end

C[':Nitpick edit {text}는 커서 위치의 어노테이션 코멘트를 바꾼다'] = function()
  -- Given: 2번째 줄에 코멘트가 있고 커서가 그 줄에 있다.
  write_file(project .. '/a.md', { '하나', '둘' })
  edit(project .. '/a.md')
  child.lua('require("nitpick.review").comment({ 2, 0, 2, #"둘" }, "처음")')
  child.api.nvim_win_set_cursor(0, { 2, 0 })

  -- When
  child.cmd('Nitpick edit 고친 코멘트')

  -- Then
  eq(
    feedback(),
    HEADER
      .. lines({
        '## a.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 2) Feedback on: "둘"',
        '> 고친 코멘트',
        '',
        '---',
        '',
      })
  )
end

C[':Nitpick remove는 커서 위치의 어노테이션을 지운다'] = function()
  -- Given: 1번째 줄과 2번째 줄에 코멘트가 있고 커서가 2번째 줄에 있다.
  write_file(project .. '/a.md', { '하나', '둘' })
  edit(project .. '/a.md')
  child.lua('require("nitpick.review").comment({ 1, 0, 1, #"하나" }, "A")')
  child.lua('require("nitpick.review").comment({ 2, 0, 2, #"둘" }, "B")')
  child.api.nvim_win_set_cursor(0, { 2, 0 })

  -- When
  child.cmd('Nitpick remove')

  -- Then: 1번째 줄 코멘트만 남는다.
  eq(
    feedback(),
    HEADER
      .. lines({
        '## a.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 1) Feedback on: "하나"',
        '> A',
        '',
        '---',
        '',
      })
  )
end

C[':Nitpick clear는 리뷰를 초기화한다'] = function()
  -- Given
  write_file(project .. '/a.md', { '하나' })
  edit(project .. '/a.md')
  child.lua('require("nitpick.review").global("A")')

  -- When
  child.cmd('Nitpick clear')

  -- Then
  eq(feedback(), vim.NIL)
end

C[':Nitpick copy는 피드백을 클립보드에 복사한다'] = function()
  -- Given
  write_file(project .. '/a.md', { '하나' })
  edit(project .. '/a.md')
  child.lua('require("nitpick.review").global("A")')

  -- When
  child.cmd('Nitpick copy')

  -- Then
  eq(child.fn.getreg('+'), feedback())
end

-- 사례 33 ---------------------------------------------------------------------

C['visual 글자 단위 선택에서 :Nitpick comment {text}를 실행하면 선택한 글자만 원문으로 쓴다'] = function()
  -- Given: 2번째 줄 "가나 다라마 바"에서 "다라마"를 글자 단위(v)로 선택한다.
  write_file(project .. '/a.md', { '첫 줄', '가나 다라마 바' })
  edit(project .. '/a.md')
  child.api.nvim_win_set_cursor(0, { 2, #'가나 ' })
  child.type_keys('v', 'e')

  -- When: visual 모드에서 ":"를 누르면 명령줄에 '<,'>가 채워진다.
  child.type_keys(':', 'Nitpick comment 단어를 바꿔 줘', '<CR>')

  -- Then
  eq(
    feedback(),
    HEADER
      .. lines({
        '## a.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 2) Feedback on: "다라마"',
        '> 단어를 바꿔 줘',
        '',
        '---',
        '',
      })
  )
end

C['visual 줄 단위 선택에서 :Nitpick delete를 실행하면 선택한 줄 전체에 삭제 표시를 한다'] = function()
  -- Given: 2~3번째 줄을 줄 단위(V)로 선택한다.
  write_file(project .. '/a.md', { '하나', '둘', '셋', '넷' })
  edit(project .. '/a.md')
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  child.type_keys('V', 'j')

  -- When
  child.type_keys(':', 'Nitpick delete', '<CR>')

  -- Then: 원문은 두 줄 전체다.
  eq(
    feedback(),
    HEADER
      .. lines({
        '## a.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (lines 2–3) Remove this',
        '```',
        '둘',
        '셋',
        '```',
        "> I don't want this in the document.",
        '',
        '---',
        '',
      })
  )
end

-- 사례 36~38 ------------------------------------------------------------------
-- 코멘트 내용을 인자로 주지 않으면 입력창(vim.ui.input)으로 받는다.
-- 테스트에서는 입력창을 가짜로 바꿔, 받은 옵션(opts)을 _G.prompts에 기록하고 _G.next_input을 입력한 것처럼 돌려준다.

T['입력창(vim.ui.input)'] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.lua([[
        _G.prompts = {}
        _G.next_input = nil
        vim.ui.input = function(opts, on_confirm)
          table.insert(_G.prompts, opts)
          on_confirm(_G.next_input)
        end
      ]])
    end,
  },
})
local I = T['입력창(vim.ui.input)']

-- 사례 36
I['내용 없이 :Nitpick global을 실행하면 입력창에 입력한 내용으로 전체 코멘트를 단다'] = function()
  -- Given: 입력창에 "입력한 전체 코멘트"를 입력할 것이다.
  write_file(project .. '/a.md', { '하나' })
  edit(project .. '/a.md')
  child.lua('_G.next_input = "입력한 전체 코멘트"')

  -- When
  child.cmd('Nitpick global')

  -- Then: 입력창이 한 번 열렸고, 입력한 내용이 코멘트가 된다.
  eq(child.lua_get('#_G.prompts'), 1)
  eq(
    feedback(),
    HEADER
      .. lines({
        '## a.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. General feedback about the document',
        '> 입력한 전체 코멘트',
        '',
        '---',
        '',
      })
  )
end

-- 사례 36
I['내용 없이 범위를 주고 :Nitpick comment를 실행하면 입력창에 입력한 내용으로 그 범위에 코멘트를 단다'] = function()
  -- Given
  write_file(project .. '/a.md', { '하나', '둘' })
  edit(project .. '/a.md')
  child.lua('_G.next_input = "입력한 코멘트"')

  -- When
  child.cmd('2Nitpick comment')

  -- Then
  eq(child.lua_get('#_G.prompts'), 1)
  eq(
    feedback(),
    HEADER
      .. lines({
        '## a.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 2) Feedback on: "둘"',
        '> 입력한 코멘트',
        '',
        '---',
        '',
      })
  )
end

-- 사례 37
I['입력창을 취소하면(nil) 어노테이션을 추가하지 않는다'] = function()
  -- Given: 입력창에서 취소할 것이다(_G.next_input = nil).
  write_file(project .. '/a.md', { '하나' })
  edit(project .. '/a.md')

  -- When
  child.cmd('1Nitpick comment')

  -- Then
  eq(child.lua_get('#_G.prompts'), 1)
  eq(feedback(), vim.NIL)
end

-- 사례 37
I['입력창에 빈 내용을 입력하면 어노테이션을 추가하지 않는다'] = function()
  -- Given: 입력창에 빈 문자열을 입력할 것이다.
  write_file(project .. '/a.md', { '하나' })
  edit(project .. '/a.md')
  child.lua('_G.next_input = ""')

  -- When
  child.cmd('Nitpick global')

  -- Then
  eq(child.lua_get('#_G.prompts'), 1)
  eq(feedback(), vim.NIL)
end

-- 사례 38
I['내용 없이 :Nitpick edit을 실행하면 입력창에 기존 코멘트가 채워져 있고 입력한 내용으로 바뀐다'] = function()
  -- Given: 1번째 줄에 "처음 코멘트"가 있고 커서가 그 줄에 있다.
  write_file(project .. '/a.md', { '하나' })
  edit(project .. '/a.md')
  child.lua('require("nitpick.review").comment({ 1, 0, 1, #"하나" }, "처음 코멘트")')
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.lua('_G.next_input = "고친 코멘트"')

  -- When
  child.cmd('Nitpick edit')

  -- Then: 입력창의 기본값(default)이 기존 코멘트였고, 코멘트가 입력한 내용으로 바뀐다.
  eq(child.lua_get('_G.prompts[1].default'), '처음 코멘트')
  eq(
    feedback(),
    HEADER
      .. lines({
        '## a.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 1) Feedback on: "하나"',
        '> 고친 코멘트',
        '',
        '---',
        '',
      })
  )
end

-- 사례 34 ---------------------------------------------------------------------

T['메시지 버퍼(:Nitpick paste)'] = MiniTest.new_set()

T['메시지 버퍼(:Nitpick paste)'][':Nitpick paste는 nofile 마크다운 버퍼를 열고, 그 버퍼의 리뷰는 메시지 형식으로 복사된다'] = function()
  -- Given: 메시지 버퍼를 열어 답변을 붙여넣는다.
  child.cmd('Nitpick paste')
  child.api.nvim_buf_set_lines(0, 0, -1, false, { '# 계획', '', '첫 단계를 진행합니다.' })

  -- When: 3번째 줄에 코멘트를 달고 복사한다.
  child.cmd('3Nitpick comment 더 구체적으로')
  child.cmd('Nitpick copy')

  -- Then: 버퍼는 nofile + markdown이고, 클립보드에는 파일 형식이 아니라 메시지 형식이 들어간다.
  eq(child.bo.buftype, 'nofile')
  eq(child.bo.filetype, 'markdown')
  eq(
    child.fn.getreg('+'),
    lines({
      '# Message Feedback',
      '',
      'The following feedback spans 1 assistant message. Each section includes an excerpt of the message it applies to.',
      '',
      '## Message 1',
      '',
      'Message excerpt:',
      '```markdown',
      '# 계획',
      '',
      '첫 단계를 진행합니다.',
      '```',
      '',
      '# Feedback for Message 1',
      '',
      "I've reviewed this message and have 1 piece of feedback:",
      '',
      '## 1. (line 3) Feedback on: "첫 단계를 진행합니다."',
      '> 더 구체적으로',
      '',
      '---',
    })
  )
end

-- 사례 53~62 ------------------------------------------------------------------
-- 비슷한 위치에 단 어노테이션이 여럿이면 :Nitpick remove / edit이 고르는 창(vim.ui.select)을 띄운다.
-- 테스트에서는 고르는 창을 가짜로 바꿔, 항목을 format_item으로 보여 준 모양을 _G.selects에 기록하고
-- _G.next_choice번째 항목을 고른 것처럼 돌려준다(nil이면 취소).
-- 입력창(vim.ui.input)과 알림(vim.notify)도 가짜로 바꿔 기록한다.

T['겹친 어노테이션 고르기(vim.ui.select)'] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.lua([[
        _G.selects = {}
        _G.next_choice = nil
        vim.ui.select = function(items, opts, on_choice)
          local format_item = opts.format_item or tostring
          table.insert(_G.selects, vim.tbl_map(format_item, items))
          local choice = _G.next_choice
          on_choice(choice and items[choice], choice)
        end
        _G.prompts = {}
        _G.next_input = nil
        vim.ui.input = function(opts, on_confirm)
          table.insert(_G.prompts, opts)
          on_confirm(_G.next_input)
        end
        _G.notified = {}
        vim.notify = function(msg, level) table.insert(_G.notified, { msg = msg, level = level }) end
      ]])
    end,
  },
})
local P = T['겹친 어노테이션 고르기(vim.ui.select)']

-- 여러 테스트가 쓰는 상황: "가나 다라마 바" 줄 전체 코멘트("줄 코멘트")를 먼저, "다라마" 코멘트("단어 코멘트")를
-- 나중에 달고 커서를 "다" 위에 둔다. 정렬 순서는 단어 코멘트 → 줄 코멘트다.
local function given_line_and_word_comments()
  write_file(project .. '/a.md', { '가나 다라마 바' })
  edit(project .. '/a.md')
  child.lua('require("nitpick.review").comment({ 1, 0, 1, #"가나 다라마 바" }, "줄 코멘트")')
  child.lua('require("nitpick.review").comment({ 1, #"가나 ", 1, #"가나 다라마" }, "단어 코멘트")')
  child.api.nvim_win_set_cursor(0, { 1, #'가나 ' })
end

-- 두 코멘트가 모두 남아 있을 때의 피드백
local BOTH_COMMENTS = HEADER
  .. lines({
    '## a.md',
    '',
    "I've reviewed this document and have 2 pieces of feedback:",
    '',
    '### 1. (line 1) Feedback on: "가나 다라마 바"',
    '> 줄 코멘트',
    '',
    '### 2. (line 1) Feedback on: "다라마"',
    '> 단어 코멘트',
    '',
    '---',
    '',
  })

-- 사례 53 (보강)
P[':Nitpick remove는 후보가 하나면 고르는 창 없이 바로 지운다'] = function()
  -- Given: 1번째 줄에만 코멘트가 있고 커서가 그 줄에 있다.
  write_file(project .. '/a.md', { '하나', '둘' })
  edit(project .. '/a.md')
  child.lua('require("nitpick.review").comment({ 1, 0, 1, #"하나" }, "A")')
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  -- When
  child.cmd('Nitpick remove')

  -- Then
  eq(child.lua_get('#_G.selects'), 0)
  eq(feedback(), vim.NIL)
end

-- 사례 54
-- 두 번째 항목을 골랐을 때 줄 코멘트가 지워지면, 항목이 정렬 순서(단어 → 줄)대로 놓였다는 뜻이다.
P[':Nitpick remove는 후보가 여럿이면 고르는 창을 띄우고 고른 어노테이션만 지운다'] = function()
  -- Given: 고르는 창에서 두 번째 항목을 고른다.
  given_line_and_word_comments()
  child.lua('_G.next_choice = 2')

  -- When
  child.cmd('Nitpick remove')

  -- Then: 고르는 창이 한 번 떴고, 두 번째 항목인 줄 코멘트만 지워졌다.
  eq(child.lua_get('#_G.selects'), 1)
  eq(
    feedback(),
    HEADER
      .. lines({
        '## a.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 1) Feedback on: "다라마"',
        '> 단어 코멘트',
        '',
        '---',
        '',
      })
  )
end

-- 사례 55
-- 항목 모양은 위치, 종류, 내용이다. 여러 줄인 코멘트는 첫 줄만 보여 준다.
P['고르는 창의 항목은 위치, 종류, 내용을 보여 준다'] = function()
  -- Given: 1번째 줄 삭제 표시, 1~2번째 줄의 두 줄짜리 코멘트, 전체 코멘트가 있고 커서는 1번째 줄에 있다.
  write_file(project .. '/a.md', { '하나', '둘' })
  edit(project .. '/a.md')
  child.lua('require("nitpick.review").comment({ 1, 0, 2, #"둘" }, "첫 줄\\n둘째 줄")')
  child.lua('require("nitpick.review").delete({ 1, 0, 1, #"하나" })')
  child.lua('require("nitpick.review").global("전체 코멘트")')
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  -- When: 고르는 창에서 취소한다.
  child.cmd('Nitpick remove')

  -- Then: 좁은 범위 → 넓은 범위 → 전체 코멘트 순서다.
  eq(child.lua_get('_G.selects'), { { 'L1 deletion: "하나"', 'L1–2 comment: 첫 줄', '[전체] 전체 코멘트' } })
end

-- 사례 56
P['고르는 창에서 취소하면 :Nitpick remove는 아무것도 지우지 않는다'] = function()
  -- Given: 고르는 창에서 아무것도 고르지 않는다(_G.next_choice = nil).
  given_line_and_word_comments()

  -- When
  child.cmd('Nitpick remove')

  -- Then
  eq(child.lua_get('#_G.selects'), 1)
  eq(feedback(), BOTH_COMMENTS)
end

-- 사례 57
P[':Nitpick remove는 커서 위치에 어노테이션이 없으면 경고를 띄운다'] = function()
  -- Given: 1번째 줄에 코멘트가 있고 커서는 2번째 줄에 있다.
  write_file(project .. '/a.md', { '하나', '둘' })
  edit(project .. '/a.md')
  child.lua('require("nitpick.review").comment({ 1, 0, 1, #"하나" }, "A")')
  child.api.nvim_win_set_cursor(0, { 2, 0 })

  -- When
  child.cmd('Nitpick remove')

  -- Then: 경고가 한 번 떴고 코멘트는 남아 있다.
  eq(child.lua_get('_G.notified'), { { msg = 'nitpick: 커서 위치에 어노테이션이 없습니다.', level = vim.log.levels.WARN } })
  eq(child.lua_get('#_G.selects'), 0)
  eq(
    feedback(),
    HEADER
      .. lines({
        '## a.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 1) Feedback on: "하나"',
        '> A',
        '',
        '---',
        '',
      })
  )
end

-- 사례 57-1
P['커서가 첫 줄에 있으면 :Nitpick remove로 파일 전체 코멘트를 지울 수 있다'] = function()
  -- Given: 전체 코멘트만 있고 커서는 1번째 줄에 있다.
  write_file(project .. '/a.md', { '하나', '둘' })
  edit(project .. '/a.md')
  child.lua('require("nitpick.review").global("전체 코멘트")')
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  -- When
  child.cmd('Nitpick remove')

  -- Then
  eq(feedback(), vim.NIL)
end

-- 사례 58
P[':Nitpick edit의 후보에는 삭제 표시가 들어가지 않는다'] = function()
  -- Given: 같은 줄에 삭제 표시를 먼저, 코멘트를 나중에 단다.
  write_file(project .. '/a.md', { '하나' })
  edit(project .. '/a.md')
  child.lua('require("nitpick.review").delete({ 1, 0, 1, #"하나" })')
  child.lua('require("nitpick.review").comment({ 1, 0, 1, #"하나" }, "처음")')
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  -- When
  child.cmd('Nitpick edit 고친 코멘트')

  -- Then: 수정 후보는 코멘트 하나뿐이라 고르는 창 없이 코멘트가 바뀌고, 삭제 표시는 그대로다.
  eq(child.lua_get('#_G.selects'), 0)
  eq(
    feedback(),
    HEADER
      .. lines({
        '## a.md',
        '',
        "I've reviewed this document and have 2 pieces of feedback:",
        '',
        '### 1. (line 1) Remove this',
        '```',
        '하나',
        '```',
        "> I don't want this in the document.",
        '',
        '### 2. (line 1) Feedback on: "하나"',
        '> 고친 코멘트',
        '',
        '---',
        '',
      })
  )
end

-- 사례 60
P[':Nitpick edit은 후보가 여럿이면 먼저 고르고, 고른 코멘트를 기본값으로 입력창을 연 뒤 그 코멘트만 바꾼다'] = function()
  -- Given: 고르는 창에서 두 번째 항목(줄 코멘트)을 고르고, 입력창에 "고친 줄 코멘트"를 입력한다.
  given_line_and_word_comments()
  child.lua('_G.next_choice = 2')
  child.lua('_G.next_input = "고친 줄 코멘트"')

  -- When
  child.cmd('Nitpick edit')

  -- Then: 입력창의 기본값(default)이 고른 코멘트였고, 줄 코멘트만 바뀌었다.
  eq(child.lua_get('#_G.selects'), 1)
  eq(child.lua_get('_G.prompts[1].default'), '줄 코멘트')
  eq(
    feedback(),
    HEADER
      .. lines({
        '## a.md',
        '',
        "I've reviewed this document and have 2 pieces of feedback:",
        '',
        '### 1. (line 1) Feedback on: "가나 다라마 바"',
        '> 고친 줄 코멘트',
        '',
        '### 2. (line 1) Feedback on: "다라마"',
        '> 단어 코멘트',
        '',
        '---',
        '',
      })
  )
end

-- 사례 60-1 (버그 재현)
-- snacks, telescope 같은 고르는 창은 자기 float 창에서 on_choice를 부르고, 입력창은 새 float 창을 열어 포커스를 옮긴다.
-- 이 사례에서만 두 창을 그렇게 동작하는 가짜로 바꾼다.
P['후보가 여럿인 :Nitpick edit에서 고른 뒤 입력창이 자기 창을 열면 포커스는 그 입력창에 있다'] = function()
  -- Given: 고르는 창은 float 창을 연 상태에서 두 번째 항목을 고르고, 입력창은 float 창을 열어 포커스를 옮긴다.
  given_line_and_word_comments()
  child.lua([[
    local function open_float()
      return vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true, {
        relative = 'editor', row = 1, col = 1, width = 20, height = 1,
      })
    end
    vim.ui.select = function(items, _, on_choice)
      local picker = open_float()
      on_choice(items[2], 2)
      if vim.api.nvim_win_is_valid(picker) then
        vim.api.nvim_win_close(picker, true)
      end
    end
    vim.ui.input = function()
      _G.input_win = open_float()
    end
  ]])

  -- When
  child.cmd('Nitpick edit')

  -- Then: 현재 창이 입력창이다.
  eq(child.api.nvim_get_current_win(), child.lua_get('_G.input_win'))
end

-- 사례 61 (고르는 창 취소)
P[':Nitpick edit의 고르는 창에서 취소하면 입력창을 열지 않고 아무것도 바꾸지 않는다'] = function()
  -- Given: 고르는 창에서 아무것도 고르지 않는다(_G.next_choice = nil).
  given_line_and_word_comments()

  -- When
  child.cmd('Nitpick edit')

  -- Then
  eq(child.lua_get('#_G.selects'), 1)
  eq(child.lua_get('#_G.prompts'), 0)
  eq(feedback(), BOTH_COMMENTS)
end

-- 사례 61 (입력창 취소)
P[':Nitpick edit에서 고른 뒤 입력창을 취소하면 아무것도 바꾸지 않는다'] = function()
  -- Given: 고르는 창에서 두 번째 항목을 고르고, 입력창은 취소한다(_G.next_input = nil).
  given_line_and_word_comments()
  child.lua('_G.next_choice = 2')

  -- When
  child.cmd('Nitpick edit')

  -- Then: 고르는 창과 입력창이 한 번씩 떴고, 코멘트는 그대로다.
  eq(child.lua_get('#_G.selects'), 1)
  eq(child.lua_get('#_G.prompts'), 1)
  eq(feedback(), BOTH_COMMENTS)
end

-- 사례 62 (현재 동작 기록: 기존에 테스트가 없던 경고를 변경 전에 고정한다)
P[':Nitpick edit은 커서 위치에 코멘트가 없으면 경고를 띄운다'] = function()
  -- Given: 커서 줄에는 삭제 표시만 있다.
  write_file(project .. '/a.md', { '하나' })
  edit(project .. '/a.md')
  child.lua('require("nitpick.review").delete({ 1, 0, 1, #"하나" })')
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  -- When
  child.cmd('Nitpick edit')

  -- Then: 경고가 한 번 떴고 입력창은 열리지 않았다.
  eq(child.lua_get('_G.notified'), { { msg = 'nitpick: 커서 위치에 코멘트가 없습니다.', level = vim.log.levels.WARN } })
  eq(child.lua_get('#_G.prompts'), 0)
end

return T
