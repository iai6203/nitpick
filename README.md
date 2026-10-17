# nitpick.nvim

Neovim에서 문서와 코드에 [Plannotator](https://github.com/backnotprop/plannotator)처럼 리뷰를 달고, 그 피드백을 **Plannotator와 같은 형식**으로 클립보드에 복사하는 플러그인입니다.

복사한 피드백은 Claude Code, Codex, ChatGPT 등 어디에나 붙여넣을 수 있습니다. 에이전트는 Plannotator에서 보낸 피드백을 받을 때와 같은 형식을 받습니다.

- 여러 파일을 오가며 리뷰한 내용이 하나의 피드백으로 모입니다.
- 별도 모드가 없습니다. 평소처럼 이동하고 편집하다가 필요할 때 명령을 실행하면 됩니다.
- 키맵을 만들지 않습니다. 원하는 키에 직접 매핑하세요.
- 리뷰 도중 파일을 편집하거나 버퍼를 닫았다가 다시 열어도 어노테이션이 제자리를 따라갑니다.
- 에이전트의 답변을 붙여넣고 리뷰할 수 있는 메시지 버퍼를 제공합니다(Plannotator의 `last`에 해당).

## 요구 사항

- Neovim 0.10 이상
- 복사할 때 쓸 클립보드 provider (`:checkhealth provider`로 확인). 없으면 unnamed 레지스터(`"`)에 넣고 알려 줍니다.

## 설치

### lazy.nvim / LazyVim

```lua
return {
  {
    dir = '~/Projects/nitpick', -- 저장소를 내려받은 경로
    name = 'nitpick.nvim',
    cmd = 'Nitpick',
    keys = {
      { '<leader>rc', ':Nitpick comment<CR>', mode = 'x', desc = 'Nitpick comment' },
      { '<leader>rd', ':Nitpick delete<CR>', mode = 'x', desc = 'Nitpick delete' },
      { '<leader>rc', '<Cmd>Nitpick comment<CR>', desc = 'Nitpick comment line' },
      { '<leader>rg', '<Cmd>Nitpick global<CR>', desc = 'Nitpick global comment' },
      { '<leader>re', '<Cmd>Nitpick edit<CR>', desc = 'Nitpick edit' },
      { '<leader>rx', '<Cmd>Nitpick remove<CR>', desc = 'Nitpick remove' },
      { '<leader>ry', '<Cmd>Nitpick copy<CR>', desc = 'Nitpick copy' },
      { '<leader>rp', '<Cmd>Nitpick paste<CR>', desc = 'Nitpick paste' },
    },
    opts = {},
  },
}
```

LazyVim이라면 `~/.config/nvim/lua/plugins/nitpick.lua`에 위 내용을 넣으면 됩니다.

> visual 모드 키맵에는 `<Cmd>` 대신 `:`를 쓰세요. 그래야 선택 범위(`'<,'>`)가 명령에 넘어갑니다.

### 설치 없이 써 보기

```sh
nvim -c 'set rtp+=~/Projects/nitpick | runtime plugin/nitpick.lua' README.md
```

lazy.nvim은 시작할 때 runtimepath를 초기화하므로 `--cmd`가 아니라 `-c`를 써야 합니다.

## 사용법

| 명령 | 동작 |
|---|---|
| `:[range]Nitpick comment [내용]` | 범위에 코멘트를 답니다. visual 글자 단위(`v`)로 선택했으면 선택한 글자만, 아니면 줄 전체가 대상입니다. 범위가 없으면 커서 줄 |
| `:[range]Nitpick delete` | 범위에 삭제 표시를 합니다 |
| `:Nitpick global [내용]` | 현재 파일 전체에 코멘트를 답니다 |
| `:Nitpick edit [내용]` | 커서 위치의 코멘트를 고칩니다. 입력창에 기존 내용이 채워져 있습니다 |
| `:Nitpick remove` | 커서 위치의 어노테이션을 지웁니다 |
| `:Nitpick clear` | 리뷰 전체를 지웁니다 |
| `:Nitpick copy` | 피드백을 클립보드(`+`)에 복사합니다 |
| `:Nitpick paste` | 답변을 붙여넣고 리뷰할 메시지 버퍼를 새 탭에 엽니다 |

`[내용]`을 생략하면 `vim.ui.input` 입력창이 열립니다. 취소하거나 빈 내용을 입력하면 아무것도 추가하지 않습니다.

### 파일 리뷰

1. 파일을 열고 리뷰할 부분을 visual로 선택한 뒤 `:Nitpick comment`를 실행합니다.
2. 지워야 할 부분은 선택한 뒤 `:Nitpick delete`를 실행합니다.
3. 파일 전체에 대한 의견은 `:Nitpick global`로 남깁니다.
4. 다른 파일로 옮겨 가며 반복합니다.
5. `:Nitpick copy`로 복사해서 에이전트에게 붙여넣습니다.

복사한 뒤에도 어노테이션은 남아 있습니다. 다음 리뷰를 시작하기 전에 `:Nitpick clear`로 지우세요.

### 답변 리뷰

1. `:Nitpick paste`로 메시지 버퍼를 엽니다. `nofile` + `markdown` 버퍼라 저장되지 않습니다.
2. 에이전트의 답변을 붙여넣습니다.
3. 파일 리뷰와 같은 방법으로 어노테이션을 달고 `:Nitpick copy`를 실행합니다.

메시지 버퍼의 리뷰는 Plannotator의 메시지 형식(`# Message Feedback`)으로 복사됩니다.

## 출력 형식

파일 두 개를 리뷰하고 복사하면 이런 내용이 클립보드에 들어갑니다.

````markdown
# File Feedback

The following feedback is on the files under review, one section per file, in the order they were given for review.

## README.md

I've reviewed this document and have 2 pieces of feedback:

### 1. (line 3) Feedback on: "npm install"
> 예시 명령을 pnpm으로 바꿔 줘.

### 2. (line 4) Remove this
```
오래된 안내 문장
```
> I don't want this in the document.

## docs/guide.md

I've reviewed this document and have 1 piece of feedback:

### 1. General feedback about the document
> 전체적으로 더 짧게 써 줘.

---
````

- 형식은 Plannotator(`backnotprop/plannotator@87dcec4`)의 `exportLinkedDocAnnotations`(파일 묶음)와 `exportMessageAnnotations`(메시지)를 따르며, 테스트에서 바이트 단위로 비교합니다.
- 줄 번호는 Plannotator의 문단 단위가 아니라 **실제로 선택한 줄 범위**입니다.
- 경로는 Neovim의 현재 디렉터리 기준 상대 경로이고, 그 밖에 있는 파일이면 절대 경로입니다.
- 파일은 처음 어노테이션을 단 순서대로 나옵니다.
- 저장하지 않은 변경이 있는 파일이 포함되어 있으면 복사는 하되 경고를 띄웁니다. 받는 쪽은 디스크의 파일을 읽으므로 줄 번호가 어긋날 수 있습니다.

## 화면 표시

| 하이라이트 그룹 | 쓰이는 곳 | 기본값 |
|---|---|---|
| `NitpickComment` | 코멘트 범위 | `DiagnosticUnderlineInfo`에 연결 |
| `NitpickDelete` | 삭제 표시 범위 | 취소선 |
| `NitpickCommentText` | 코멘트 가상 줄 (`  ↳ 내용`) | `Comment`에 연결 |

코멘트 본문은 범위의 끝 줄 아래에, 파일 전체 코멘트는 첫 줄 위에 `  ↳ [전체] 내용`으로 보입니다. 하이라이트 그룹은 `default`로 정의하므로 직접 정한 색이 우선합니다.

```lua
vim.api.nvim_set_hl(0, 'NitpickComment', { undercurl = true, sp = '#7aa2f7' })
```

## 클립보드 설정

### macOS

별도 설정이 필요 없습니다(`pbcopy`).

### WSL2

Windows 클립보드에 복사하려면 [win32yank](https://github.com/equalsraf/win32yank)를 설치해 `PATH`에 두세요. Neovim이 자동으로 찾아 씁니다.

tmux 안에서 쓰거나 SSH로 접속했다면 OSC 52를 쓸 수도 있습니다.

```lua
local osc52 = require('vim.ui.clipboard.osc52')
vim.g.clipboard = {
  name = 'OSC 52',
  copy = { ['+'] = osc52.copy('+'), ['*'] = osc52.copy('*') },
  paste = { ['+'] = osc52.paste('+'), ['*'] = osc52.paste('*') },
}
```

tmux를 쓴다면 `~/.tmux.conf`에 `set -g set-clipboard on`도 필요합니다.

## 개발

```sh
make test
```

처음 실행하면 [mini.test](https://github.com/nvim-mini/mini.nvim)를 `deps/`에 내려받습니다.

- 로컬에서 실행하기, 테스트 구성, 화면 확인, 원본 형식과 비교하는 방법: [`docs/local-development.md`](docs/local-development.md)
- 테스트 사례 목록: [`docs/test-list.md`](docs/test-list.md)

## 감사

피드백 형식은 [Plannotator](https://github.com/backnotprop/plannotator)(Apache-2.0 / MIT)를 따릅니다.
