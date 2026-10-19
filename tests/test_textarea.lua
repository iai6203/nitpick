-- 여러 줄 입력창(nitpick.textarea) 테스트
--
-- 공개 인터페이스:
--   require('nitpick.textarea').open({ prompt?, default? }, on_confirm)
--     vim.ui.input과 같은 모양이다. 확정하면 on_confirm(내용), 취소하면 on_confirm(nil)을 부른다.
--     확정: <C-s>(insert/normal), <CR>(normal) / 취소: <Esc>·q(normal), 창을 떠나기
--
-- 결과는 child Neovim의 _G.results에 기록한다(취소는 vim.NIL로 남긴다).

local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

local function open(opts)
  child.lua(
    [[
    _G.results = {}
    _G.origin_win = vim.api.nvim_get_current_win()
    require('nitpick.textarea').open(..., function(input)
      table.insert(_G.results, input == nil and vim.NIL or input)
    end)
  ]],
    { opts or {} }
  )
end

local function results()
  return child.lua_get('_G.results')
end

local function window_count()
  return #child.api.nvim_list_wins()
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'scripts/minimal_init.lua' })
    end,
    post_once = child.stop,
  },
})

T['열면 플로팅 창으로 포커스가 옮겨 가고 insert 모드로 시작한다'] = function()
  -- When
  open({ prompt = 'Nitpick comment: ' })

  -- Then
  eq(window_count(), 2)
  eq(child.api.nvim_win_get_config(0).relative, 'editor')
  eq(child.api.nvim_get_mode().mode, 'i')
end

T['insert 모드의 <CR>은 줄을 바꾸고, <C-s>로 여러 줄 내용을 확정한다'] = function()
  -- Given
  open()

  -- When
  child.type_keys('첫 줄', '<CR>', '둘째 줄', '<C-s>')

  -- Then: 줄바꿈이 그대로 들어가고, 창이 닫혀 원래 창으로 돌아간다.
  eq(results(), { '첫 줄\n둘째 줄' })
  eq(window_count(), 1)
  eq(child.api.nvim_get_current_win(), child.lua_get('_G.origin_win'))
  eq(child.api.nvim_get_mode().mode, 'n')
end

T['normal 모드의 <CR>로 확정한다'] = function()
  -- Given
  open()

  -- When
  child.type_keys('내용', '<Esc>', '<CR>')

  -- Then
  eq(results(), { '내용' })
end

T['앞뒤 빈 줄과 공백은 잘라 낸다'] = function()
  -- Given
  open()

  -- When
  child.type_keys('<CR>', '  내용  ', '<CR>', '<CR>', '<C-s>')

  -- Then
  eq(results(), { '내용' })
end

T['default가 있으면 그 내용을 채워 두고 끝에서 이어 쓴다'] = function()
  -- Given: 기존 코멘트가 두 줄이다.
  open({ default = '하나\n둘' })

  -- When
  child.type_keys('셋', '<C-s>')

  -- Then
  eq(results(), { '하나\n둘셋' })
end

T['normal 모드의 <Esc>나 q로 취소하면 nil을 넘긴다'] = function()
  for _, key in ipairs({ '<Esc>', 'q' }) do
    -- Given
    open({ default = '고치던 내용' })

    -- When
    child.type_keys('<Esc>', key)

    -- Then
    eq(results(), { vim.NIL })
    eq(window_count(), 1)
  end
end

T['다른 창으로 옮겨 가면 취소한다'] = function()
  -- Given
  open()
  child.type_keys('쓰던 내용', '<Esc>')

  -- When
  child.lua('vim.api.nvim_set_current_win(_G.origin_win)')
  child.lua('vim.wait(50, function() return #_G.results > 0 end)')

  -- Then: 한 번만 취소하고 입력창은 닫힌다.
  eq(results(), { vim.NIL })
  eq(window_count(), 1)
end

return T
