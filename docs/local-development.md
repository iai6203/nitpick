# 로컬에서 실행하고 개발하기

이 저장소를 고치면서 직접 써 보거나 테스트할 때 필요한 방법을 정리한 문서입니다. 아래 명령은 저장소 루트(`~/Projects/nitpick`)를 기준으로 합니다.

## 직접 써 보기

### 설치 없이 한 번 실행하기

```sh
nvim -c 'set rtp+=~/Projects/nitpick | runtime plugin/nitpick.lua' README.md
```

평소 설정을 그대로 쓰면서 이 저장소만 runtimepath에 더합니다. `:Nitpick` 명령은 `plugin/nitpick.lua`가 만들기 때문에 `runtime`으로 그 파일을 직접 불러옵니다.

> **`--cmd`를 쓰면 안 됩니다.** lazy.nvim(LazyVim)은 시작할 때 runtimepath를 초기화합니다(`performance.rtp.reset`). 그래서 `--cmd 'set rtp+=…'`로 더한 경로가 지워지고 `E492: Not an editor command: Nitpick`이 납니다. `-c`는 lazy.nvim 초기화가 끝난 뒤에 실행되므로 괜찮습니다.

### 평소 설정에 넣고 쓰기 (LazyVim)

`~/.config/nvim/lua/plugins/nitpick.lua`를 만들고 로컬 경로를 `dir`로 지정합니다.

```lua
return {
  {
    dir = '~/Projects/nitpick',
    name = 'nitpick.nvim',
    cmd = 'Nitpick',
    keys = {
      { '<leader>rc', ':Nitpick comment<CR>', mode = 'x', desc = 'Nitpick comment' },
      { '<leader>rd', ':Nitpick delete<CR>', mode = 'x', desc = 'Nitpick delete' },
      { '<leader>ry', '<Cmd>Nitpick copy<CR>', desc = 'Nitpick copy' },
    },
    opts = {},
  },
}
```

`dir`로 지정하면 lazy.nvim이 저장소를 복사하지 않고 그 자리의 파일을 그대로 씁니다. 코드를 고친 뒤 Neovim을 다시 열면 바로 반영됩니다. 전체 키맵 예시는 [README](../README.md#설치)에 있습니다.

### 고친 코드 반영하기

**Neovim을 다시 여는 것이 가장 확실합니다.** `package.loaded['nitpick.review'] = nil`로 모듈만 다시 불러오면, 지금까지의 리뷰 상태가 사라지고 autocmd만 다시 등록되어 기존 extmark와 어긋날 수 있습니다.

### 상태 확인하기

```vim
" 명령이 등록되었는지 (2면 등록됨)
:echo exists(':Nitpick')

" 지금 복사될 피드백 미리 보기
:lua print(require('nitpick.review').feedback())

" 알림을 놓쳤을 때
:messages

" 클립보드 provider 확인
:checkhealth provider
```

## 테스트

### 전체 실행

```sh
make test
```

처음 실행하면 [mini.test](https://github.com/nvim-mini/mini.nvim)(stable 브랜치)를 `deps/mini.nvim`에 내려받습니다. `deps/`는 git에서 제외되어 있습니다.

### 파일 하나만 실행

```sh
nvim --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run_file('tests/test_copy.lua')"
```

### 테스트 구성

| 파일 | 내용 | 방식 |
|---|---|---|
| `tests/test_export.lua` | 파일 리뷰 피드백 형식 | 순수 함수 |
| `tests/test_export_message.lua` | 메시지 리뷰 피드백 형식 | 순수 함수 |
| `tests/test_review.lua` | 여러 파일 리뷰 상태, 경로 | child Neovim |
| `tests/test_tracking.lua` | 편집·버퍼 닫기에도 위치 추적 | child Neovim |
| `tests/test_copy.lua` | 클립보드 복사, 경고 | child Neovim |
| `tests/test_commands.lua` | `:Nitpick` 명령, `setup()`, 입력창, 메시지 버퍼 | child Neovim |
| `tests/test_render.lua` | 하이라이트, 가상 줄, topfill | child Neovim |

- **child Neovim**: 테스트마다 `scripts/minimal_init.lua`로 새 Neovim을 띄우고 임시 디렉터리를 cwd로 씁니다. 사용 중인 Neovim 설정은 쓰지 않습니다.
- **클립보드**: 실제 시스템 클립보드를 덮어쓰지 않도록 가짜 provider(`vim.g.clipboard`)를 넣습니다. "provider 없음"은 `--cmd 'let g:loaded_clipboard_provider = 1'`로 만듭니다.
- **입력창**: `vim.ui.input`을 가짜로 바꿔, 미리 정해 둔 값을 입력한 것처럼 돌려줍니다.

## 화면을 텍스트로 확인하기

색이나 모양은 자동 테스트로 확인하지 않습니다. 대신 child Neovim의 화면을 텍스트로 찍어 볼 수 있습니다.

```sh
printf '# 설치\n\nnpm install 을 실행합니다.\n오래된 안내 문장\n' > /tmp/nitpick-demo.md

nvim --headless --noplugin -u scripts/minimal_init.lua -l /dev/stdin <<'EOF'
local child = MiniTest.new_child_neovim()
child.start({ '-u', 'scripts/minimal_init.lua' })
child.cmd('edit /tmp/nitpick-demo.md')
child.lua([[
  local r = require('nitpick.review')
  r.global('전체적으로 더 짧게')
  r.comment({ 3, 0, 3, #'npm install' }, '예시 명령을 pnpm으로')
  r.delete({ 4, 0, 4, #'오래된 안내 문장' })
]])
print(child.get_screenshot())
child.stop()
EOF
```

출력의 위쪽은 화면 글자이고, 아래쪽은 칸마다 적용된 하이라이트를 번호로 보여 줍니다. 같은 번호는 같은 하이라이트입니다.

```
01|  ↳ [전체] 전체적으로 더 짧게
02|# 설치
03|
04|npm install 을 실행합니다.
05|  ↳ 예시 명령을 pnpm으로
06|오래된 안내 문장
```

## 원본 Plannotator와 형식 비교하기

피드백 형식 테스트(`test_export*.lua`)의 기대값은 원본 Plannotator에 같은 입력을 넣어 얻은 출력입니다. 예외로, 여러 줄 본문의 인용(`> `)은 원본과 달리 모든 줄에 붙이므로 해당 테스트(`tests/test_export.lua`의 "여러 줄 인용" 주석 아래 사례와 `tests/test_export_message.lua`의 여러 줄 코멘트 사례)는 원본 출력과 다릅니다. 형식을 바꾸거나 원본이 바뀌었는지 확인하려면 이렇게 합니다. [Bun](https://bun.sh)이 필요합니다.

1. 원본을 기준 커밋으로 내려받고, 스크립트를 실행하지 않는 옵션으로 의존성을 설치합니다.

   ```sh
   git clone https://github.com/backnotprop/plannotator /tmp/plannotator
   git -C /tmp/plannotator checkout 87dcec4
   (cd /tmp/plannotator && bun install --ignore-scripts)
   ```

2. 원본의 직렬화 함수를 불러 출력을 만듭니다. 파일 리뷰는 `exportLinkedDocAnnotations(map, BUNDLE_DOC_EXPORT_HEADING)`, 메시지 리뷰는 `exportMessageAnnotations([...])`입니다. 둘 다 `packages/ui/utils/parser.ts`에 있습니다.

   - 원본은 줄 번호를 문단(block) 단위로 매깁니다. 어노테이션마다 `startLine`과 `sourceLineCount`가 우리 줄 범위와 같은 block을 하나씩 만들어 넘기면 같은 줄 번호가 나옵니다.
   - 파일 리뷰 출력은 앞의 빈 줄을 지워야 합니다(`.replace(/^\n+/, '')`). 원본 화면도 그렇게 합니다.

3. 나온 문자열을 테스트의 기대값과 비교합니다.
