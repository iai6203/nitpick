-- 리뷰 상태(nitpick.review) 통합 테스트 — 여러 파일을 넘나드는 리뷰
--
-- 실제 버퍼와 cwd가 필요하므로 테스트마다 새 child Neovim을 띄운다.
--
-- 공개 인터페이스 (제안):
--   comment(range, text)  현재 버퍼의 범위(range)에 코멘트를 단다. 성공하면 true
--   delete(range)         현재 버퍼의 범위(range)에 삭제 표시를 한다. 성공하면 true
--   global(text)          현재 버퍼의 파일 전체에 코멘트를 단다. 성공하면 true
--   remove_at_cursor()    커서 위치의 어노테이션을 지운다
--   edit_at_cursor(text)  커서 위치의 어노테이션 코멘트를 바꾼다
--   text_at_cursor()      커서 위치의 어노테이션 코멘트. 없으면 nil
--   annotations_at_cursor()  커서 위치의 후보 어노테이션 목록(제안). 가장 유력한 후보가 먼저 온다.
--     *_at_cursor 함수는 후보가 여럿이면 첫 번째 후보에 동작한다.
--   clear()               리뷰 전체를 초기화한다
--   feedback()            파일 리뷰 피드백 텍스트. 어노테이션이 없으면 nil
--
--   범위(range) = { start_line, start_col, end_line, end_col }
--     줄은 1부터, 열은 0부터 센 바이트 위치이고 end_col은 포함하지 않는다(nvim_buf_get_text와 같음).
--   표시(extmark)는 'nitpick' 네임스페이스에 만든다.

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

-- 테스트마다 새로 만드는 임시 프로젝트 디렉터리.
-- macOS의 /var → /private/var 심볼릭 링크 때문에 경로가 달라지지 않도록 실제 경로로 바꿔 둔다.
local project

local function write_file(path, content_lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  vim.fn.writefile(content_lines, path)
end

local function edit(path)
  child.cmd('edit ' .. vim.fn.fnameescape(path))
end

-- child Neovim 안에서 리뷰(nitpick.review)의 함수를 호출한다.
local function review(fn_name, ...)
  return child.lua(('return require("nitpick.review").%s(...)'):format(fn_name), { ... })
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'scripts/minimal_init.lua' })
      project = vim.fn.resolve(vim.fn.tempname())
      vim.fn.mkdir(project, 'p')
      child.cmd('cd ' .. vim.fn.fnameescape(project))
    end,
    post_case = function()
      vim.fn.delete(project, 'rf')
    end,
    post_once = child.stop,
  },
})

T['리뷰(review)'] = MiniTest.new_set()
local S = T['리뷰(review)']

-- 사례 16
-- 사례 9의 "처음 어노테이션을 단 순서"도 여기서 검증한다: 직렬화는 받은 순서를 그대로 쓰므로(사례 9),
-- 리뷰(review)가 파일을 처음 어노테이션을 단 순서로 넘겨야 한다.
S['서로 다른 파일에 단 어노테이션이 하나의 피드백(feedback)에 처음 단 파일 순서로 모인다'] = function()
  -- Given: b.md → a.md → 다시 b.md 순서로 오가며 어노테이션을 단다.
  write_file(project .. '/b.md', { 'b 첫 줄', 'b 둘째 줄' })
  write_file(project .. '/a.md', { 'a 첫 줄' })

  edit(project .. '/b.md')
  review('comment', { 2, 0, 2, #'b 둘째 줄' }, 'b 둘째 코멘트')
  edit(project .. '/a.md')
  review('global', 'a 전체 코멘트')
  edit(project .. '/b.md')
  review('comment', { 1, 0, 1, #'b 첫 줄' }, 'b 첫 코멘트')

  -- When
  local output = review('feedback')

  -- Then: 처음 어노테이션을 단 b.md 섹션이 먼저 나오고, 섹션 안은 줄 순서다.
  --   원문(original_text)은 범위(range)의 버퍼 텍스트다.
  eq(
    output,
    HEADER
      .. lines({
        '## b.md',
        '',
        "I've reviewed this document and have 2 pieces of feedback:",
        '',
        '### 1. (line 1) Feedback on: "b 첫 줄"',
        '> b 첫 코멘트',
        '',
        '### 2. (line 2) Feedback on: "b 둘째 줄"',
        '> b 둘째 코멘트',
        '',
        '## a.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. General feedback about the document',
        '> a 전체 코멘트',
        '',
        '---',
        '',
      })
  )
end

-- 사례 17
S['커서 위치의 어노테이션을 지우면(remove_at_cursor) 그 어노테이션만 사라진다'] = function()
  -- Given: 1번째 줄과 3번째 줄에 코멘트가 있고, 커서는 3번째 줄에 있다.
  write_file(project .. '/a.md', { '하나', '둘', '셋' })
  edit(project .. '/a.md')
  review('comment', { 1, 0, 1, #'하나' }, '첫 코멘트')
  review('delete', { 3, 0, 3, #'셋' })
  child.api.nvim_win_set_cursor(0, { 3, 0 })

  -- When
  review('remove_at_cursor')

  -- Then: 3번째 줄의 삭제 표시만 사라지고 1번째 줄 코멘트는 남는다.
  eq(
    review('feedback'),
    HEADER
      .. lines({
        '## a.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 1) Feedback on: "하나"',
        '> 첫 코멘트',
        '',
        '---',
        '',
      })
  )
end

-- 사례 18
S['커서 위치의 어노테이션 코멘트를 수정하면(edit_at_cursor) 수정된 내용으로 출력된다'] = function()
  -- Given: 2번째 줄에 코멘트가 있고, 커서는 그 줄에 있다.
  write_file(project .. '/a.md', { '하나', '둘' })
  edit(project .. '/a.md')
  review('comment', { 2, 0, 2, #'둘' }, '처음 코멘트')
  child.api.nvim_win_set_cursor(0, { 2, 0 })

  -- When
  review('edit_at_cursor', '고친 코멘트')

  -- Then: 원문과 줄 번호는 그대로이고 코멘트만 바뀐다.
  eq(
    review('feedback'),
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

-- 사례 19
S['리뷰를 초기화하면(clear) 모든 파일의 어노테이션과 표시(extmark)가 사라진다'] = function()
  -- Given: 두 파일에 어노테이션이 있다.
  write_file(project .. '/a.md', { 'a' })
  write_file(project .. '/b.md', { 'b' })
  edit(project .. '/a.md')
  review('comment', { 1, 0, 1, 1 }, 'A')
  edit(project .. '/b.md')
  review('delete', { 1, 0, 1, 1 })

  -- When
  review('clear')

  -- Then: 피드백(feedback)이 없고, 어느 버퍼에도 'nitpick' 네임스페이스의 표시(extmark)가 남지 않는다.
  eq(review('feedback'), vim.NIL)
  local extmark_count = child.lua([[
    local ns = vim.api.nvim_create_namespace('nitpick')
    local count = 0
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      count = count + #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
    end
    return count
  ]])
  eq(extmark_count, 0)
end

-- 사례 21
-- 알림 문구는 정해지지 않았으므로 경고 수준(vim.log.levels.WARN)의 알림이 떴는지만 확인한다.
S['파일도 메시지 버퍼도 아닌 이름 없는 버퍼에서는 어노테이션을 추가하지 않고 경고를 띄운다'] = function()
  -- Given: 이름 없는 새 버퍼에 글이 있고, 알림(vim.notify)을 기록해 둔다.
  child.cmd('enew')
  child.api.nvim_buf_set_lines(0, 0, -1, false, { '이름 없는 글' })
  child.lua([[
    _G.notified = {}
    vim.notify = function(msg, level) table.insert(_G.notified, { msg = msg, level = level }) end
  ]])

  -- When
  local added = review('comment', { 1, 0, 1, #'이름 없는 글' }, '코멘트')

  -- Then: 추가되지 않았고(false), 피드백(feedback)도 없으며, 경고 알림이 한 번 떴다.
  eq(added, false)
  eq(review('feedback'), vim.NIL)
  eq(child.lua_get('#_G.notified'), 1)
  eq(child.lua_get('_G.notified[1].level'), vim.log.levels.WARN)
end

-- 사례 22
S['경로는 cwd 안이면 cwd 기준 상대 경로로, cwd 밖이면 절대 경로로 쓴다'] = function()
  -- Given: cwd(project) 안의 docs/a.md와 cwd 밖의 파일에 각각 전체 코멘트를 단다.
  local outside = vim.fn.resolve(vim.fn.tempname()) .. '/b.md'
  write_file(project .. '/docs/a.md', { 'a' })
  write_file(outside, { 'b' })

  edit(project .. '/docs/a.md')
  review('global', '안쪽')
  edit(outside)
  review('global', '바깥쪽')

  -- When
  local output = review('feedback')
  vim.fn.delete(vim.fn.fnamemodify(outside, ':h'), 'rf')

  -- Then
  eq(
    output,
    HEADER
      .. lines({
        '## docs/a.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. General feedback about the document',
        '> 안쪽',
        '',
        '## ' .. outside,
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. General feedback about the document',
        '> 바깥쪽',
        '',
        '---',
        '',
      })
  )
end

-- 사례 47~52, 64 --------------------------------------------------------------
-- 비슷한 위치에 단 어노테이션 중 원하는 것을 고를 수 있도록, 커서 위치의 후보를 유력한 순서로 돌려준다.

T['커서 위치의 후보(annotations_at_cursor)'] = MiniTest.new_set()
local A = T['커서 위치의 후보(annotations_at_cursor)']

-- 후보 목록을 종류(kind)와 코멘트(text)만 남겨 읽는다. 삭제 표시는 코멘트가 없다.
local function candidates()
  return child.lua([[
    return vim.tbl_map(function(ann)
      return { kind = ann.kind, text = ann.text }
    end, require('nitpick.review').annotations_at_cursor())
  ]])
end

-- 사례 47
A['커서 줄을 범위에 포함하는 어노테이션은 모두 후보가 되고, 커서 줄에 없는 어노테이션은 빠진다'] = function()
  -- Given: 1~3번째 줄 코멘트, 2번째 줄 삭제 표시, 3번째 줄 코멘트가 있고 커서는 2번째 줄에 있다.
  write_file(project .. '/a.md', { '하나', '둘', '셋' })
  edit(project .. '/a.md')
  review('comment', { 1, 0, 3, #'셋' }, '넓은 코멘트')
  review('delete', { 2, 0, 2, #'둘' })
  review('comment', { 3, 0, 3, #'셋' }, '셋째 줄 코멘트')
  child.api.nvim_win_set_cursor(0, { 2, 0 })

  -- When
  local result = candidates()

  -- Then: 순서와 관계없이 2번째 줄을 포함하는 두 어노테이션만 후보다.
  table.sort(result, function(a, b) return a.kind < b.kind end)
  eq(result, { { kind = 'comment', text = '넓은 코멘트' }, { kind = 'deletion' } })
end

-- 사례 48
-- 열 조건이 범위 너비(사례 49)나 단 순서(사례 50)보다 먼저임을 보이려고,
-- 커서 열을 포함하는 "다라마"를 더 넓게, 먼저 단다.
A['커서 열까지 범위 안에 드는 후보가 줄만 겹치는 후보보다 앞에 온다'] = function()
  -- Given: "가나 다라마 바"에서 "다라마"와 "가나"에 차례로 코멘트를 달고, 커서를 "다" 위에 둔다.
  write_file(project .. '/a.md', { '가나 다라마 바' })
  edit(project .. '/a.md')
  review('comment', { 1, #'가나 ', 1, #'가나 다라마' }, '다라마 코멘트')
  review('comment', { 1, 0, 1, #'가나' }, '가나 코멘트')
  child.api.nvim_win_set_cursor(0, { 1, #'가나 ' })

  -- When
  local result = candidates()

  -- Then
  eq(result, { { kind = 'comment', text = '다라마 코멘트' }, { kind = 'comment', text = '가나 코멘트' } })
end

-- 사례 49 (줄 수 비교)
-- 단 순서(사례 50)와 구별하려고 좁은 범위를 먼저 단다.
A['커서 열 조건이 같으면 줄 수가 적은 후보가 앞에 온다'] = function()
  -- Given: 3번째 줄 코멘트를 먼저, 1~5번째 줄 코멘트를 나중에 달고 커서는 3번째 줄에 있다.
  write_file(project .. '/a.md', { '1', '2', '3', '4', '5' })
  edit(project .. '/a.md')
  review('comment', { 3, 0, 3, 1 }, '좁은 코멘트')
  review('comment', { 1, 0, 5, 1 }, '넓은 코멘트')
  child.api.nvim_win_set_cursor(0, { 3, 0 })

  -- When
  local result = candidates()

  -- Then
  eq(result, { { kind = 'comment', text = '좁은 코멘트' }, { kind = 'comment', text = '넓은 코멘트' } })
end

-- 사례 49 (글자 수 비교)
A['줄 수도 같으면 글자 수가 적은 후보가 앞에 온다'] = function()
  -- Given: "가나다라마"에서 "나다"를 먼저, 줄 전체를 나중에 달고 커서를 "나" 위에 둔다.
  write_file(project .. '/a.md', { '가나다라마' })
  edit(project .. '/a.md')
  review('comment', { 1, #'가', 1, #'가나다' }, '나다 코멘트')
  review('comment', { 1, 0, 1, #'가나다라마' }, '줄 코멘트')
  child.api.nvim_win_set_cursor(0, { 1, #'가' })

  -- When
  local result = candidates()

  -- Then
  eq(result, { { kind = 'comment', text = '나다 코멘트' }, { kind = 'comment', text = '줄 코멘트' } })
end

-- 사례 50
A['범위가 완전히 같으면 나중에 단 후보가 앞에 온다'] = function()
  -- Given: 같은 줄 전체에 "먼저"와 "나중" 코멘트를 차례로 단다.
  write_file(project .. '/a.md', { '하나' })
  edit(project .. '/a.md')
  review('comment', { 1, 0, 1, #'하나' }, '먼저')
  review('comment', { 1, 0, 1, #'하나' }, '나중')
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  -- When
  local result = candidates()

  -- Then
  eq(result, { { kind = 'comment', text = '나중' }, { kind = 'comment', text = '먼저' } })
end

-- 사례 51, 51-1
-- 전체 코멘트는 첫 줄 위 가상 줄에 보이므로 첫 줄에서 고를 수 있다.
-- 단 순서(사례 50)와 구별하려고 전체 코멘트를 나중에 단다.
A['커서가 첫 줄에 있으면 파일 전체 코멘트(global)도 범위 후보들 뒤에 후보로 들어간다'] = function()
  -- Given: 1번째 줄 코멘트를 단 뒤 전체 코멘트를 달고, 커서는 1번째 줄에 있다.
  write_file(project .. '/a.md', { '하나', '둘' })
  edit(project .. '/a.md')
  review('comment', { 1, 0, 1, #'하나' }, '첫 줄 코멘트')
  review('global', '전체 코멘트')
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  -- When
  local result = candidates()

  -- Then
  eq(result, { { kind = 'comment', text = '첫 줄 코멘트' }, { kind = 'global', text = '전체 코멘트' } })
end

-- 사례 51
A['커서가 첫 줄이 아니면 파일 전체 코멘트(global)는 후보에 들어가지 않는다'] = function()
  -- Given: 전체 코멘트와 2번째 줄 코멘트가 있고, 커서는 2번째 줄에 있다.
  write_file(project .. '/a.md', { '하나', '둘' })
  edit(project .. '/a.md')
  review('global', '전체 코멘트')
  review('comment', { 2, 0, 2, #'둘' }, '둘째 줄 코멘트')
  child.api.nvim_win_set_cursor(0, { 2, 0 })

  -- When
  local result = candidates()

  -- Then
  eq(result, { { kind = 'comment', text = '둘째 줄 코멘트' } })
end

-- 사례 52
A['다른 버퍼의 어노테이션은 같은 줄에 있어도 후보에 들어가지 않는다'] = function()
  -- Given: a.md와 b.md의 1번째 줄에 각각 코멘트가 있고, 커서는 b.md의 1번째 줄에 있다.
  write_file(project .. '/a.md', { 'a' })
  write_file(project .. '/b.md', { 'b' })
  edit(project .. '/a.md')
  review('comment', { 1, 0, 1, 1 }, 'a 코멘트')
  edit(project .. '/b.md')
  review('comment', { 1, 0, 1, 1 }, 'b 코멘트')
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  -- When
  local result = candidates()

  -- Then
  eq(result, { { kind = 'comment', text = 'b 코멘트' } })
end

-- 사례 64 ---------------------------------------------------------------------
-- 후보가 여럿일 때 *_at_cursor 함수는 처음 단 후보가 아니라 가장 유력한(정렬된 첫 번째) 후보에 동작한다.
-- 아래 세 테스트는 같은 상황을 쓴다: "가나 다라마 바" 줄 전체 코멘트를 먼저, "다라마" 코멘트를 나중에 달고
-- 커서를 "다" 위에 둔다. 가장 유력한 후보는 "다라마" 코멘트다.

local function given_line_and_word_comments()
  write_file(project .. '/a.md', { '가나 다라마 바' })
  edit(project .. '/a.md')
  review('comment', { 1, 0, 1, #'가나 다라마 바' }, '줄 코멘트')
  review('comment', { 1, #'가나 ', 1, #'가나 다라마' }, '단어 코멘트')
  child.api.nvim_win_set_cursor(0, { 1, #'가나 ' })
end

A['후보가 여럿이면 커서 위치의 코멘트(text_at_cursor)는 가장 유력한 후보의 코멘트다'] = function()
  -- Given
  given_line_and_word_comments()

  -- When / Then
  eq(review('text_at_cursor'), '단어 코멘트')
end

A['후보가 여럿이면 지우기(remove_at_cursor)는 가장 유력한 후보만 지운다'] = function()
  -- Given
  given_line_and_word_comments()

  -- When
  review('remove_at_cursor')

  -- Then: 줄 코멘트만 남는다.
  eq(
    review('feedback'),
    HEADER
      .. lines({
        '## a.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 1) Feedback on: "가나 다라마 바"',
        '> 줄 코멘트',
        '',
        '---',
        '',
      })
  )
end

A['후보가 여럿이면 고치기(edit_at_cursor)는 가장 유력한 후보의 코멘트만 바꾼다'] = function()
  -- Given
  given_line_and_word_comments()

  -- When
  review('edit_at_cursor', '고친 단어 코멘트')

  -- Then: 줄 코멘트는 그대로이고 "다라마" 코멘트만 바뀐다.
  eq(
    review('feedback'),
    HEADER
      .. lines({
        '## a.md',
        '',
        "I've reviewed this document and have 2 pieces of feedback:",
        '',
        '### 1. (line 1) Feedback on: "가나 다라마 바"',
        '> 줄 코멘트',
        '',
        '### 2. (line 1) Feedback on: "다라마"',
        '> 고친 단어 코멘트',
        '',
        '---',
        '',
      })
  )
end

return T
