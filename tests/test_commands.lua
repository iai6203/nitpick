-- 사용자 명령(:Nitpick)과 설정(setup), 메시지 버퍼 통합 테스트
--
-- 공개 인터페이스 (제안):
--   require('nitpick').setup(opts)   키맵을 만들지 않는다. 명령은 setup 없이도 plugin/nitpick.lua가 만든다.
--   :Nitpick global {text}           현재 파일 전체에 코멘트
--   :[range]Nitpick comment {text}   범위에 코멘트. visual에서 실행하면 선택한 글자 범위를 쓴다
--   :[range]Nitpick delete           범위에 삭제 표시
--   :Nitpick edit {text}             커서 위치의 어노테이션 코멘트 수정
--   :Nitpick remove                  커서 위치의 어노테이션 삭제
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

return T
