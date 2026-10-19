-- 화면 표시 통합 테스트 — 하이라이트와 가상 줄(virt_lines)
--
-- 표시는 extmark로 그린다. 어느 네임스페이스에 그리는지는 계약이 아니므로,
-- 테스트는 버퍼의 모든 네임스페이스에서 extmark를 읽어 표시를 찾는다.
-- 줄(row)과 열(col)은 extmark와 같이 0부터 센다.
-- 리뷰(nitpick.review)의 공개 인터페이스와 범위(range) 모양은 tests/test_review.lua 맨 위 설명과 같다.

local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

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

-- 현재 버퍼에서 하이라이트 그룹(group)이 적용된 범위 목록: { { row, col, end_row, end_col }, ... }
local function highlights(group)
  return child.lua(
    [[
    local found = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
      local details = mark[4]
      if details.hl_group == ... then
        table.insert(found, { mark[2], mark[3], details.end_row, details.end_col })
      end
    end
    return found
  ]],
    { group }
  )
end

-- 현재 버퍼의 가상 줄 목록: { { row, above, { { 글자, 하이라이트 그룹 }, ... } }, ... }
-- 가상 줄 하나가 조각(chunk) 하나로 이루어져 있다고 보고 각 줄의 첫 조각만 모은다.
local function virt_lines()
  return child.lua([[
    local found = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
      local details = mark[4]
      if details.virt_lines then
        local chunks = {}
        for _, line in ipairs(details.virt_lines) do
          table.insert(chunks, line[1])
        end
        table.insert(found, { mark[2], details.virt_lines_above, chunks })
      end
    end
    return found
  ]])
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

T['표시(render)'] = MiniTest.new_set()
local S = T['표시(render)']

S['코멘트 범위에 하이라이트 그룹 NitpickComment가 적용된다'] = function()
  -- Given
  write_file(project .. '/a.md', { '하나', '가나 다라 마' })
  edit(project .. '/a.md')

  -- When: 2번째 줄의 "다라"에 코멘트를 단다.
  review('comment', { 2, #'가나 ', 2, #'가나 다라' }, '코멘트')

  -- Then: 정확히 그 글자 범위(0부터 센 줄 1, 열 7~13)에 하이라이트가 있다.
  eq(highlights('NitpickComment'), { { 1, #'가나 ', 1, #'가나 다라' } })
end

S['삭제 표시 범위에 하이라이트 그룹 NitpickDelete가 적용된다'] = function()
  -- Given
  write_file(project .. '/a.md', { '하나', '둘', '셋' })
  edit(project .. '/a.md')

  -- When: 2~3번째 줄에 삭제 표시를 한다.
  review('delete', { 2, 0, 3, #'셋' })

  -- Then
  eq(highlights('NitpickDelete'), { { 1, 0, 2, #'셋' } })
  eq(highlights('NitpickComment'), {})
end

S['코멘트 범위의 끝 줄 아래에 코멘트 본문이 줄마다 가상 줄로 보인다'] = function()
  -- Given
  write_file(project .. '/a.md', { '하나', '둘', '셋', '넷' })
  edit(project .. '/a.md')

  -- When: 2~3번째 줄에 두 줄짜리 코멘트를 단다.
  review('comment', { 2, 0, 3, #'셋' }, '첫 줄\n둘째 줄')

  -- Then: 끝 줄(0부터 센 줄 2)의 아래(above = false)에 가상 줄 두 개가 있다.
  eq(virt_lines(), {
    {
      2,
      false,
      {
        { '  ↳ 첫 줄', 'NitpickCommentText' },
        { '  ↳ 둘째 줄', 'NitpickCommentText' },
      },
    },
  })
end

S['코멘트를 수정하면(edit_at_cursor) 가상 줄의 내용도 바뀐다'] = function()
  -- Given: 1번째 줄에 코멘트가 있고 커서가 그 줄에 있다.
  write_file(project .. '/a.md', { '하나', '둘' })
  edit(project .. '/a.md')
  review('comment', { 1, 0, 1, #'하나' }, '처음')
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  -- When
  review('edit_at_cursor', '고친 코멘트')

  -- Then: 가상 줄은 하나뿐이고 내용이 바뀌었다.
  eq(virt_lines(), { { 0, false, { { '  ↳ 고친 코멘트', 'NitpickCommentText' } } } })
end

S['어노테이션을 지우면(remove_at_cursor) 하이라이트와 가상 줄이 함께 사라진다'] = function()
  -- Given: 1번째 줄에 코멘트가 있고 커서가 그 줄에 있다.
  write_file(project .. '/a.md', { '하나', '둘' })
  edit(project .. '/a.md')
  review('comment', { 1, 0, 1, #'하나' }, '코멘트')
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  -- When
  review('remove_at_cursor')

  -- Then
  eq(highlights('NitpickComment'), {})
  eq(virt_lines(), {})
end

S['버퍼를 닫았다가(bdelete) 다시 열면 하이라이트와 가상 줄도 복원된다'] = function()
  -- Given: a.md의 2번째 줄에 코멘트가 있고, 다른 파일 b.md도 열려 있다.
  write_file(project .. '/a.md', { '하나', '둘', '셋' })
  write_file(project .. '/b.md', { 'b' })
  edit(project .. '/a.md')
  review('comment', { 2, 0, 2, #'둘' }, '코멘트')
  edit(project .. '/b.md')

  -- When
  child.cmd('bdelete ' .. vim.fn.fnameescape(project .. '/a.md'))
  edit(project .. '/a.md')

  -- Then
  eq(highlights('NitpickComment'), { { 1, 0, 1, #'둘' } })
  eq(virt_lines(), { { 1, false, { { '  ↳ 코멘트', 'NitpickCommentText' } } } })
end

S['파일 전체 코멘트는 버퍼 첫 줄 위에 [전체] 가상 줄로 보인다'] = function()
  -- Given
  write_file(project .. '/a.md', { '하나', '둘' })
  edit(project .. '/a.md')

  -- When
  review('global', '전체적으로 좋아요')

  -- Then: 첫 줄(0부터 센 줄 0)의 위(above = true)에 가상 줄이 있고, 하이라이트 범위는 없다.
  eq(virt_lines(), { { 0, true, { { '  ↳ [전체] 전체적으로 좋아요', 'NitpickCommentText' } } } })
  eq(highlights('NitpickComment'), {})
end

-- Neovim은 첫 줄 위의 가상 줄을 창이 그만큼 위로 스크롤된 상태(topfill)일 때만 보여 준다.
-- 그래서 실제로 보이는지는 현재 창의 topfill(winsaveview)로 확인한다.

local function topfill()
  return child.lua_get('vim.fn.winsaveview().topfill')
end

S['파일 전체 코멘트를 달면 첫 줄부터 보여 주는 창이 가상 줄이 보이도록 위로 스크롤된다'] = function()
  -- Given: 첫 줄부터 보여 주는 창이다.
  write_file(project .. '/a.md', { '하나', '둘' })
  edit(project .. '/a.md')
  eq(topfill(), 0)

  -- When
  review('global', '전체적으로 좋아요')

  -- Then: 가상 줄 1개만큼 위로 스크롤되었다.
  eq(topfill(), 1)
end

S['파일 전체 코멘트가 있는 파일을 창에 다시 띄우면 가상 줄이 보인다'] = function()
  -- Given: a.md에 전체 코멘트를 단 뒤 같은 창에 b.md를 띄웠다.
  write_file(project .. '/a.md', { '하나' })
  write_file(project .. '/b.md', { 'b' })
  edit(project .. '/a.md')
  review('global', '전체 코멘트')
  edit(project .. '/b.md')

  -- When: 다시 a.md를 띄운다(버퍼는 그대로 남아 있다).
  edit(project .. '/a.md')

  -- Then
  eq(topfill(), 1)
end

S['파일 전체 코멘트가 있는 파일을 닫았다가(bdelete) 다시 열면 가상 줄이 보인다'] = function()
  -- Given: a.md에 전체 코멘트를 단 뒤 b.md로 옮겨 a.md 버퍼를 닫았다.
  write_file(project .. '/a.md', { '하나' })
  write_file(project .. '/b.md', { 'b' })
  edit(project .. '/a.md')
  review('global', '전체 코멘트')
  edit(project .. '/b.md')
  child.cmd('bdelete ' .. vim.fn.fnameescape(project .. '/a.md'))

  -- When
  edit(project .. '/a.md')

  -- Then
  eq(topfill(), 1)
end

T['하이라이트 그룹'] = MiniTest.new_set()

-- 하이라이트 그룹(name)의 정의. 링크를 따라가지 않는다.
local function hl(name)
  return child.lua('return vim.api.nvim_get_hl(0, { name = ... })', { name })
end

-- 하이라이트 그룹들을 정의한다: { 그룹 이름 = nvim_set_hl의 값, ... }
local function set_hl(groups)
  child.lua(
    [[
    for name, value in pairs(...) do
      vim.api.nvim_set_hl(0, name, value)
    end
  ]],
    { groups }
  )
end

T['하이라이트 그룹']['사용자가 정의하지 않았으면 코멘트 가상 줄 하이라이트는 Comment로 연결된다'] = function()
  -- When: 리뷰(nitpick.review)를 불러온다.
  child.lua('require("nitpick.review")')

  -- Then
  eq(hl('NitpickCommentText').link, 'Comment')
end

-- 범위 하이라이트의 기본 배경색은 진단 글자색을 Normal 배경에 20% 섞은 색이다.
-- 섞기는 RGB 채널마다 배경 × 0.8 + 글자색 × 0.2로 계산한다.
-- 예: 배경 #000000에 글자색 #ffffff를 섞으면 0xff × 0.2 = 0x33 → #333333

T['하이라이트 그룹']['코멘트 범위(NitpickComment)의 기본 배경색은 DiagnosticInfo 글자색을 Normal 배경에 20% 섞은 색이다'] = function()
  -- Given: Normal 배경은 검정, DiagnosticInfo 글자색은 흰색이다.
  set_hl({ Normal = { bg = '#000000' }, DiagnosticInfo = { fg = '#ffffff' } })

  -- When: 리뷰(nitpick.review)를 불러온다.
  child.lua('require("nitpick.review")')

  -- Then
  eq(hl('NitpickComment').bg, 0x333333)
end

T['하이라이트 그룹']['코멘트 범위(NitpickComment)의 기본값에는 글자색이 없어 문법 하이라이트의 글자색을 가리지 않는다'] = function()
  -- Given
  set_hl({ Normal = { bg = '#000000' }, DiagnosticInfo = { fg = '#ffffff' } })

  -- When
  child.lua('require("nitpick.review")')

  -- Then: 글자색(fg)도 다른 그룹으로의 연결(link)도 없다.
  local group = hl('NitpickComment')
  eq(group.fg, nil)
  eq(group.link, nil)
end

T['하이라이트 그룹']['삭제 표시(NitpickDelete)의 기본값은 취소선에 DiagnosticError 글자색을 20% 섞은 배경색이다'] = function()
  -- Given: Normal 배경은 검정, DiagnosticError 글자색은 흰색이다.
  set_hl({ Normal = { bg = '#000000' }, DiagnosticError = { fg = '#ffffff' } })

  -- When
  child.lua('require("nitpick.review")')

  -- Then
  local group = hl('NitpickDelete')
  eq(group.strikethrough, true)
  eq(group.bg, 0x333333)
end

-- 투명 배경 colorscheme처럼 Normal에 배경색이 없으면 'background' 옵션으로 바탕색을 정한다.
-- dark → #000000, light → #ffffff

T['하이라이트 그룹']['Normal에 배경색이 없고 background=light면 흰 바탕에 섞는다'] = function()
  -- Given: Normal에 배경색이 없고, 밝은 배경이며, DiagnosticInfo 글자색은 검정이다.
  -- background를 바꾸면 기본 colorscheme이 다시 적용되므로 색은 그 뒤에 정한다.
  child.o.background = 'light'
  set_hl({ Normal = {}, DiagnosticInfo = { fg = '#000000' } })

  -- When
  child.lua('require("nitpick.review")')

  -- Then: 0xff × 0.8 = 0xcc → #cccccc
  eq(hl('NitpickComment').bg, 0xcccccc)
end

T['하이라이트 그룹']['Normal에 배경색이 없고 background=dark면 검은 바탕에 섞는다'] = function()
  -- Given: Normal에 배경색이 없고, 어두운 배경이며, DiagnosticInfo 글자색은 흰색이다.
  -- background를 바꾸면 기본 colorscheme이 다시 적용되므로 색은 그 뒤에 정한다.
  child.o.background = 'dark'
  set_hl({ Normal = {}, DiagnosticInfo = { fg = '#ffffff' } })

  -- When
  child.lua('require("nitpick.review")')

  -- Then
  eq(hl('NitpickComment').bg, 0x333333)
end

T['하이라이트 그룹']['DiagnosticInfo에 글자색이 없으면 코멘트 범위는 예전처럼 DiagnosticUnderlineInfo로 연결된다'] = function()
  -- Given: 섞을 글자색이 없다.
  set_hl({ Normal = { bg = '#000000' }, DiagnosticInfo = {} })

  -- When
  child.lua('require("nitpick.review")')

  -- Then
  eq(hl('NitpickComment').link, 'DiagnosticUnderlineInfo')
end

T['하이라이트 그룹']['DiagnosticError에 글자색이 없으면 삭제 표시는 예전처럼 취소선만 쓴다'] = function()
  -- Given: 섞을 글자색이 없다.
  set_hl({ Normal = { bg = '#000000' }, DiagnosticError = {} })

  -- When
  child.lua('require("nitpick.review")')

  -- Then
  local group = hl('NitpickDelete')
  eq(group.strikethrough, true)
  eq(group.bg, nil)
end

T['하이라이트 그룹']['사용자가 먼저 정의한 하이라이트는 덮어쓰지 않는다'] = function()
  -- Given: 사용자가 NitpickComment를 빨간 글자로 정했다.
  child.lua('vim.api.nvim_set_hl(0, "NitpickComment", { fg = "#ff0000" })')

  -- When: 리뷰(nitpick.review)를 불러오고 코멘트를 단다.
  write_file(project .. '/a.md', { '하나' })
  edit(project .. '/a.md')
  review('comment', { 1, 0, 1, #'하나' }, '코멘트')

  -- Then: 사용자 정의(fg = 0xff0000)가 그대로이고 기본 연결로 바뀌지 않았다.
  eq(child.lua_get('vim.api.nvim_get_hl(0, { name = "NitpickComment" })'), { fg = 0xff0000 })
end

T['하이라이트 그룹']['colorscheme을 바꾸면 새 Normal 배경과 DiagnosticInfo 글자색으로 배경색을 다시 계산한다'] = function()
  -- Given: 흰 바탕에 흰 글자색이라 섞은 배경색이 #ffffff인 상태로 리뷰(nitpick.review)를 불러왔다.
  set_hl({ Normal = { bg = '#ffffff' }, DiagnosticInfo = { fg = '#ffffff' } })
  child.lua('require("nitpick.review")')
  eq(hl('NitpickComment').bg, 0xffffff)

  -- When: colorscheme이 하듯 하이라이트를 지우고(:hi clear) 새 색을 정한 뒤 ColorScheme 이벤트를 보낸다.
  child.cmd('hi clear')
  set_hl({ Normal = { bg = '#000000' }, DiagnosticInfo = { fg = '#ffffff' } })
  child.cmd('doautocmd ColorScheme')

  -- Then
  eq(hl('NitpickComment').bg, 0x333333)
end

-- 라벨은 코멘트와 따로 색을 바꿀 수 있도록 자기 하이라이트 그룹을 쓴다.

local CLARIFY = { id = 'clarify-this', emoji = '❓', text = 'Clarify this' }

T['표시(render)']['라벨 범위에는 NitpickLabel이 적용되고, 끝 줄 아래에 [라벨] 가상 줄이 NitpickLabelText로 보인다'] = function()
  -- Given
  write_file(project .. '/a.md', { '하나', '가나 다라 마' })
  edit(project .. '/a.md')

  -- When: 2번째 줄의 "다라"에 라벨 "❓ Clarify this"를 단다.
  review('label', { 2, #'가나 ', 2, #'가나 다라' }, CLARIFY)

  -- Then: 라벨 범위에 NitpickLabel만 있고(NitpickComment 아님), 가상 줄은 "  ↳ [❓ Clarify this]"다.
  eq(highlights('NitpickLabel'), { { 1, #'가나 ', 1, #'가나 다라' } })
  eq(highlights('NitpickComment'), {})
  eq(virt_lines(), {
    { 1, false, { { '  ↳ [❓ Clarify this]', 'NitpickLabelText' } } },
  })
end

T['하이라이트 그룹']['사용자가 정의하지 않았으면 라벨 하이라이트는 코멘트 하이라이트로 연결된다'] = function()
  -- When: 리뷰(nitpick.review)를 불러온다.
  child.lua('require("nitpick.review")')

  -- Then
  eq(child.lua_get('vim.api.nvim_get_hl(0, { name = "NitpickLabel" }).link'), 'NitpickComment')
  eq(child.lua_get('vim.api.nvim_get_hl(0, { name = "NitpickLabelText" }).link'), 'NitpickCommentText')
end

T['하이라이트 그룹']['사용자가 먼저 정의한 라벨 하이라이트는 덮어쓰지 않는다'] = function()
  -- Given: 사용자가 NitpickLabel을 초록 글자로 정했다.
  child.lua('vim.api.nvim_set_hl(0, "NitpickLabel", { fg = "#00ff00" })')

  -- When: 리뷰(nitpick.review)를 불러오고 라벨을 단다.
  write_file(project .. '/a.md', { '하나' })
  edit(project .. '/a.md')
  review('label', { 1, 0, 1, #'하나' }, CLARIFY)

  -- Then
  eq(child.lua_get('vim.api.nvim_get_hl(0, { name = "NitpickLabel" })'), { fg = 0x00ff00 })
end

T['하이라이트 그룹']['colorscheme을 바꿔도 라벨 하이라이트가 다시 정의된다'] = function()
  -- Given: 리뷰(nitpick.review)를 불러왔다.
  child.lua('require("nitpick.review")')

  -- When: colorscheme을 다시 불러온다(:hi clear 후 ColorScheme 이벤트).
  child.cmd('colorscheme default')

  -- Then
  eq(child.lua_get('vim.api.nvim_get_hl(0, { name = "NitpickLabel" }).link'), 'NitpickComment')
  eq(child.lua_get('vim.api.nvim_get_hl(0, { name = "NitpickLabelText" }).link'), 'NitpickCommentText')
end

-- 사인 컬럼 막대: 어노테이션 범위의 모든 줄 사인 컬럼에 막대 문자를 표시한다.
-- 설정(setup의 sign)으로 문자를 바꾸거나 끌 수 있고, 기본은 '▎'다.

-- 현재 버퍼의 사인 목록을 줄 순서로: { { row, 문자, 하이라이트 그룹 }, ... }
-- Neovim이 사인 문자 뒤를 공백으로 채워 두 칸으로 만들기 때문에 양 끝 공백을 지워서 비교한다.
local function signs()
  return child.lua([[
    local found = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
      local details = mark[4]
      if details.sign_text then
        table.insert(found, { mark[2], vim.trim(details.sign_text), details.sign_hl_group })
      end
    end
    table.sort(found, function(a, b)
      return a[1] < b[1]
    end)
    return found
  ]])
end

local function setup(opts)
  child.lua('require("nitpick").setup(...)', { opts })
end

T['사인 컬럼 막대'] = MiniTest.new_set()
local G = T['사인 컬럼 막대']

G['설정하지 않았으면 코멘트 범위의 모든 줄에 막대(▎)가 NitpickCommentSign으로 보인다'] = function()
  -- Given
  write_file(project .. '/a.md', { '하나', '둘', '셋', '넷' })
  edit(project .. '/a.md')

  -- When: 2~3번째 줄에 코멘트를 단다.
  review('comment', { 2, 0, 3, #'셋' }, '코멘트')

  -- Then: 0부터 센 줄 1, 2에만 막대가 있다.
  eq(signs(), {
    { 1, '▎', 'NitpickCommentSign' },
    { 2, '▎', 'NitpickCommentSign' },
  })
end

G['라벨 범위에는 NitpickLabelSign, 삭제 표시 범위에는 NitpickDeleteSign으로 막대가 보인다'] = function()
  -- Given
  write_file(project .. '/a.md', { '하나', '둘' })
  edit(project .. '/a.md')

  -- When: 1번째 줄에 라벨을, 2번째 줄에 삭제 표시를 단다.
  review('label', { 1, 0, 1, #'하나' }, CLARIFY)
  review('delete', { 2, 0, 2, #'둘' })

  -- Then
  eq(signs(), {
    { 0, '▎', 'NitpickLabelSign' },
    { 1, '▎', 'NitpickDeleteSign' },
  })
end

G['파일 전체 코멘트(global)에는 막대가 없다'] = function()
  -- Given
  write_file(project .. '/a.md', { '하나' })
  edit(project .. '/a.md')

  -- When
  review('global', '전체 코멘트')

  -- Then
  eq(signs(), {})
end

G['어노테이션을 지우면(remove_at_cursor) 막대도 사라진다'] = function()
  -- Given: 1번째 줄에 코멘트가 있고 커서가 그 줄에 있다.
  write_file(project .. '/a.md', { '하나', '둘' })
  edit(project .. '/a.md')
  review('comment', { 1, 0, 1, #'하나' }, '코멘트')
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  -- When
  review('remove_at_cursor')

  -- Then
  eq(signs(), {})
end

G['버퍼를 닫았다가(bdelete) 다시 열면 막대도 복원된다'] = function()
  -- Given: a.md의 2번째 줄에 코멘트가 있고, 다른 파일 b.md도 열려 있다.
  write_file(project .. '/a.md', { '하나', '둘', '셋' })
  write_file(project .. '/b.md', { 'b' })
  edit(project .. '/a.md')
  review('comment', { 2, 0, 2, #'둘' }, '코멘트')
  edit(project .. '/b.md')

  -- When
  child.cmd('bdelete ' .. vim.fn.fnameescape(project .. '/a.md'))
  edit(project .. '/a.md')

  -- Then
  eq(signs(), { { 1, '▎', 'NitpickCommentSign' } })
end

G['setup의 sign에 문자를 주면 그 문자로 막대를 그린다'] = function()
  -- Given: 막대 문자(sign)를 '|'로 설정했다.
  setup({ sign = '|' })
  write_file(project .. '/a.md', { '하나' })
  edit(project .. '/a.md')

  -- When
  review('comment', { 1, 0, 1, #'하나' }, '코멘트')

  -- Then
  eq(signs(), { { 0, '|', 'NitpickCommentSign' } })
end

G['setup의 sign이 false면 막대 없이 범위 하이라이트와 가상 줄만 보인다'] = function()
  -- Given: 막대(sign)를 껐다.
  setup({ sign = false })
  write_file(project .. '/a.md', { '하나' })
  edit(project .. '/a.md')

  -- When
  review('comment', { 1, 0, 1, #'하나' }, '코멘트')

  -- Then
  eq(signs(), {})
  eq(highlights('NitpickComment'), { { 0, 0, 0, #'하나' } })
  eq(virt_lines(), { { 0, false, { { '  ↳ 코멘트', 'NitpickCommentText' } } } })
end

T['하이라이트 그룹']['사용자가 정의하지 않았으면 막대 하이라이트는 종류별 진단 색으로 연결된다'] = function()
  -- When: 리뷰(nitpick.review)를 불러온다.
  child.lua('require("nitpick.review")')

  -- Then: 코멘트는 DiagnosticInfo, 삭제 표시는 DiagnosticError, 라벨은 코멘트 막대를 따른다.
  eq(hl('NitpickCommentSign').link, 'DiagnosticInfo')
  eq(hl('NitpickDeleteSign').link, 'DiagnosticError')
  eq(hl('NitpickLabelSign').link, 'NitpickCommentSign')
end

return T
