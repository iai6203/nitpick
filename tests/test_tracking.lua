-- 위치 추적 통합 테스트 — 리뷰 도중 파일을 편집하거나 버퍼를 닫아도 어노테이션이 따라간다
--
-- 리뷰(nitpick.review)의 공개 인터페이스와 범위(range) 모양은 tests/test_review.lua 맨 위 설명과 같다.

local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- 여러 줄 문자열을 읽기 쉽게 쓰기 위한 도우미: 각 원소를 줄바꿈으로 잇는다.
local function lines(list)
  return table.concat(list, '\n')
end

-- 파일 리뷰 피드백의 머리말 (tests/test_export.lua에서 문자 그대로 검증)
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

T['위치 추적(review)'] = MiniTest.new_set()
local S = T['위치 추적(review)']

S['어노테이션 위쪽에 줄을 추가하면 출력되는 줄 번호가 그만큼 밀린다'] = function()
  -- Given: 3번째 줄에 코멘트가 있다.
  write_file(project .. '/a.md', { '하나', '둘', '셋' })
  edit(project .. '/a.md')
  review('comment', { 3, 0, 3, #'셋' }, '코멘트')

  -- When: 맨 위에 두 줄을 추가한다.
  child.api.nvim_buf_set_lines(0, 0, 0, false, { '새 줄 1', '새 줄 2' })

  -- Then: 줄 번호가 3 → 5로 밀린다.
  eq(
    review('feedback'),
    HEADER
      .. lines({
        '## a.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 5) Feedback on: "셋"',
        '> 코멘트',
        '',
        '---',
        '',
      })
  )
end

S['범위의 텍스트를 고쳐도 원문(original_text)은 어노테이션을 만든 시점의 텍스트를 유지한다'] = function()
  -- Given: 2번째 줄 "둘"에 코멘트가 있다.
  write_file(project .. '/a.md', { '하나', '둘', '셋' })
  edit(project .. '/a.md')
  review('comment', { 2, 0, 2, #'둘' }, '코멘트')

  -- When: 그 줄을 "고친 둘"로 바꾼다.
  child.api.nvim_buf_set_text(0, 1, 0, 1, #'둘', { '고친 둘' })

  -- Then: 원문은 여전히 "둘"이다.
  eq(
    review('feedback'),
    HEADER
      .. lines({
        '## a.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 2) Feedback on: "둘"',
        '> 코멘트',
        '',
        '---',
        '',
      })
  )
end

-- 범위가 사라지면 extmark는 지워진 자리(다음 줄의 시작)로 모인다. 그 위치를 줄 번호로 쓴다.
S['어노테이션을 단 범위가 통째로 지워져도 어노테이션은 남고 현재 위치를 줄 번호로 쓴다'] = function()
  -- Given: 5줄짜리 파일의 3번째 줄에 코멘트가 있다.
  write_file(project .. '/a.md', { '1', '2', '3', '4', '5' })
  edit(project .. '/a.md')
  review('comment', { 3, 0, 3, #'3' }, '코멘트')

  -- When: 3번째 줄을 지운다.
  child.api.nvim_buf_set_lines(0, 2, 3, false, {})

  -- Then: 어노테이션은 남고, 지워진 자리(이제 "4"가 있는 3번째 줄)를 줄 번호로 쓴다. 원문은 "3" 그대로다.
  eq(
    review('feedback'),
    HEADER
      .. lines({
        '## a.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 3) Feedback on: "3"',
        '> 코멘트',
        '',
        '---',
        '',
      })
  )
end

S['버퍼를 닫았다가(bdelete) 다시 열어도 어노테이션과 표시(extmark)가 남아 있다'] = function()
  -- Given: a.md의 2번째 줄에 코멘트가 있고, 다른 파일 b.md도 열려 있다.
  write_file(project .. '/a.md', { '하나', '둘', '셋' })
  write_file(project .. '/b.md', { 'b' })
  edit(project .. '/a.md')
  review('comment', { 2, 0, 2, #'둘' }, '코멘트')
  edit(project .. '/b.md')

  -- When: a.md 버퍼를 닫았다가 다시 연다.
  child.cmd('bdelete ' .. vim.fn.fnameescape(project .. '/a.md'))
  edit(project .. '/a.md')

  -- Then: 피드백에 코멘트가 같은 줄로 남아 있고, 다시 연 버퍼에 표시(extmark)가 하나 있다.
  eq(
    review('feedback'),
    HEADER
      .. lines({
        '## a.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 2) Feedback on: "둘"',
        '> 코멘트',
        '',
        '---',
        '',
      })
  )
  local extmark_count = child.lua([[
    local ns = vim.api.nvim_create_namespace('nitpick')
    return #vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {})
  ]])
  eq(extmark_count, 1)
end

return T
