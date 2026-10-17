-- 복사(nitpick.copy) 통합 테스트
--
-- 공개 인터페이스 (제안):
--   copy()  리뷰 피드백(nitpick.review.feedback)을 클립보드에 복사한다. 복사했으면 true
--
-- 실제 시스템 클립보드를 건드리지 않도록 child Neovim에는 가짜 클립보드 provider(g:clipboard)를 넣는다.
-- 가짜 provider는 복사한 내용을 _G.clip에 담고, getreg('+')는 그 내용을 그대로 돌려준다.
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

-- 클립보드에 복사한다(copy).
local function copy()
  return child.lua('return require("nitpick.copy").copy()')
end

local function start_child(extra_args)
  child.restart(vim.list_extend({ '-u', 'scripts/minimal_init.lua' }, extra_args or {}))
  project = vim.fn.resolve(vim.fn.tempname())
  vim.fn.mkdir(project, 'p')
  child.cmd('cd ' .. vim.fn.fnameescape(project))
  -- 알림(vim.notify)을 기록해 둔다.
  child.lua([[
    _G.notified = {}
    vim.notify = function(msg, level) table.insert(_G.notified, { msg = msg, level = level }) end
  ]])
end

-- 기록된 알림 중 경고 수준(vim.log.levels.WARN)인 것의 개수.
-- 복사에 성공하면 성공 알림(INFO)도 뜨므로 경고만 따로 센다.
local function warn_count()
  return child.lua([[
    local count = 0
    for _, n in ipairs(_G.notified) do
      if n.level == vim.log.levels.WARN then count = count + 1 end
    end
    return count
  ]])
end

local function install_fake_clipboard()
  child.lua([[
    _G.clip = { { '이전 클립보드' }, 'v' }
    local function copy(lines, regtype) _G.clip = { lines, regtype } end
    local function paste() return _G.clip end
    vim.g.clipboard = { name = 'fake', copy = { ['+'] = copy, ['*'] = copy }, paste = { ['+'] = paste, ['*'] = paste } }
  ]])
end

local T = MiniTest.new_set({
  hooks = {
    post_case = function()
      vim.fn.delete(project, 'rf')
    end,
    post_once = child.stop,
  },
})

T['복사(copy)'] = MiniTest.new_set()
local S = T['복사(copy)']

S['복사하면 리뷰 피드백(feedback)이 + 레지스터(클립보드)에 들어간다'] = function()
  -- Given: 클립보드가 있고, a.md에 코멘트가 하나 있다.
  start_child()
  install_fake_clipboard()
  write_file(project .. '/a.md', { '하나' })
  edit(project .. '/a.md')
  review('comment', { 1, 0, 1, #'하나' }, '코멘트')

  -- When
  local copied = copy()

  -- Then: 클립보드 내용이 피드백 텍스트와 같다.
  eq(copied, true)
  eq(child.fn.getreg('+'), review('feedback'))
end

S['복사한 뒤에도 어노테이션은 그대로 남는다'] = function()
  -- Given: 코멘트가 있는 상태에서 피드백을 기록해 둔다.
  start_child()
  install_fake_clipboard()
  write_file(project .. '/a.md', { '하나' })
  edit(project .. '/a.md')
  review('comment', { 1, 0, 1, #'하나' }, '코멘트')
  local before = review('feedback')

  -- When
  copy()

  -- Then: 복사 전과 같은 피드백이 남아 있다.
  eq(review('feedback'), before)
end

-- 경고 문구는 정해지지 않았으므로 경고 수준(vim.log.levels.WARN)의 알림이 떴는지만 확인한다.
S['저장하지 않은 변경이 있는 파일이 포함되어 있어도 복사는 하되 경고를 띄운다'] = function()
  -- Given: 코멘트를 단 뒤 파일을 고치고 저장하지 않았다.
  start_child()
  install_fake_clipboard()
  write_file(project .. '/a.md', { '하나' })
  edit(project .. '/a.md')
  review('comment', { 1, 0, 1, #'하나' }, '코멘트')
  child.api.nvim_buf_set_lines(0, 1, 1, false, { '저장 안 한 줄' })

  -- When
  local copied = copy()

  -- Then: 복사는 되고, 경고 알림이 한 번 떴다.
  eq(copied, true)
  eq(child.fn.getreg('+'), review('feedback'))
  eq(warn_count(), 1)
end

-- 경고 문구는 정해지지 않았으므로 경고 수준(vim.log.levels.WARN)의 알림이 떴는지만 확인한다.
S['클립보드 provider가 없으면 unnamed 레지스터에 넣고 경고를 띄운다'] = function()
  -- Given: 클립보드 provider를 끈 Neovim이다(g:loaded_clipboard_provider = 1).
  start_child({ '--cmd', 'let g:loaded_clipboard_provider = 1' })
  eq(child.fn.has('clipboard'), 0)
  write_file(project .. '/a.md', { '하나' })
  edit(project .. '/a.md')
  review('comment', { 1, 0, 1, #'하나' }, '코멘트')

  -- When
  local copied = copy()

  -- Then: unnamed 레지스터(")에 피드백이 들어가고, 경고 알림이 한 번 떴다.
  eq(copied, true)
  eq(child.fn.getreg('"'), review('feedback'))
  eq(warn_count(), 1)
end

-- 성공 문구는 정해지지 않았으므로 정보 수준(vim.log.levels.INFO)의 알림 하나만 떴는지 확인한다.
S['클립보드에 복사하면 정보 수준의 성공 알림 하나만 띄운다'] = function()
  -- Given: 클립보드가 있고, 저장된 파일에 코멘트가 하나 있다(경고할 상황이 없다).
  start_child()
  install_fake_clipboard()
  write_file(project .. '/a.md', { '하나' })
  edit(project .. '/a.md')
  review('comment', { 1, 0, 1, #'하나' }, '코멘트')

  -- When
  copy()

  -- Then
  eq(child.lua_get('#_G.notified'), 1)
  eq(child.lua_get('_G.notified[1].level'), vim.log.levels.INFO)
end

S['어노테이션이 0개면 복사하지 않고 리뷰 내용이 없다고 알린다'] = function()
  -- Given: 클립보드와 unnamed 레지스터에 이전 내용이 있고, 어노테이션은 없다.
  start_child()
  install_fake_clipboard()
  child.fn.setreg('"', '이전 레지스터')

  -- When
  local copied = copy()

  -- Then: 복사하지 않았고(false), 두 레지스터 모두 그대로이며, "리뷰 내용이 없습니다" 알림이 떴다.
  eq(copied, false)
  eq(child.fn.getreg('+'), '이전 클립보드')
  eq(child.fn.getreg('"'), '이전 레지스터')
  eq(child.lua_get('#_G.notified'), 1)
  eq(child.lua_get('_G.notified[1].msg:find("리뷰 내용이 없습니다", 1, true) ~= nil'), true)
end

return T
