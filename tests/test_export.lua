-- 파일 리뷰 피드백 직렬화(nitpick.export.file_feedback) 테스트
--
-- 기대값은 원본 plannotator(backnotprop/plannotator@87dcec4)의
-- exportLinkedDocAnnotations(..., BUNDLE_DOC_EXPORT_HEADING)에 같은 입력을 넣어 얻은 출력이다.
-- 단, 줄 번호는 원본의 블록 단위가 아니라 어노테이션의 실제 줄 범위(start_line~end_line)를 쓴다.
--
-- 입력 모양 (제안):
--   문서 목록(documents) = { { path = 'README.md', annotations = { 어노테이션, ... } }, ... }
--   어노테이션 = {
--     kind = 'comment' | 'deletion' | 'global' | 'label',
--     start_line, end_line,  -- 1부터 시작하는 줄 번호 (global에는 없음)
--     start_col,             -- 0부터 시작하는 열 (생략하면 0)
--     original_text,         -- 선택한 원문 (global에는 없음)
--     text,                  -- 코멘트 본문 (deletion에는 없음). label은 "<emoji> <text>" (예: '❓ Clarify this')
--     tip,                   -- label에만: 에이전트에게 줄 지시문 (생략 가능)
--   }

local eq = MiniTest.expect.equality

-- 파일 리뷰 피드백을 만든다(file_feedback).
local function file_feedback(documents)
  return require('nitpick.export').file_feedback(documents)
end

-- 여러 줄 문자열을 읽기 쉽게 쓰기 위한 도우미: 각 원소를 줄바꿈으로 잇는다.
local function lines(list)
  return table.concat(list, '\n')
end

-- 묶음 형식의 머리말. 첫 테스트에서 문자 그대로 검증하고, 나머지 테스트에서는 이 상수로 줄여 쓴다.
local HEADER = lines({
  '# File Feedback',
  '',
  'The following feedback is on the files under review, one section per file, in the order they were given for review.',
  '',
  '',
})

local T = MiniTest.new_set()

T['파일 리뷰 피드백(file_feedback)'] = MiniTest.new_set()
local S = T['파일 리뷰 피드백(file_feedback)']

S['파일이 하나여도 묶음 머리말, 파일 섹션, 개수 문장 순서로 출력한다'] = function()
  -- Given: README.md 한 파일에 전체 코멘트 하나가 있다.
  local documents = {
    { path = 'README.md', annotations = { { kind = 'global', text = '좋아요.' } } },
  }

  -- When
  local output = file_feedback(documents)

  -- Then: 머리말 → 안내 문장 → 파일 경로 섹션 → 개수 문장 → 항목 → 구분선
  eq(
    output,
    lines({
      '# File Feedback',
      '',
      'The following feedback is on the files under review, one section per file, in the order they were given for review.',
      '',
      '## README.md',
      '',
      "I've reviewed this document and have 1 piece of feedback:",
      '',
      '### 1. General feedback about the document',
      '> 좋아요.',
      '',
      '---',
      '',
    })
  )
end

S['한 줄 코멘트는 (line N) 라벨, 원문 인용, 코멘트 인용으로 출력한다'] = function()
  -- Given: 12번째 줄 하나를 선택해 코멘트를 달았다.
  local documents = {
    {
      path = 'README.md',
      annotations = {
        { kind = 'comment', start_line = 12, end_line = 12, original_text = '설치 방법', text = '예시 명령을 추가해 줘.' },
      },
    },
  }

  -- When
  local output = file_feedback(documents)

  -- Then
  eq(
    output,
    HEADER
      .. lines({
        '## README.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 12) Feedback on: "설치 방법"',
        '> 예시 명령을 추가해 줘.',
        '',
        '---',
        '',
      })
  )
end

S['여러 줄 코멘트는 en dash로 이은 (lines A–B) 라벨을 쓴다'] = function()
  -- Given: 20~24번째 줄을 선택해 코멘트를 달았다. 원문의 줄바꿈은 원본처럼 그대로 둔다.
  local documents = {
    {
      path = 'README.md',
      annotations = {
        { kind = 'comment', start_line = 20, end_line = 24, original_text = '첫 줄\n둘째 줄', text = '이 부분을 줄여 줘.' },
      },
    },
  }

  -- When
  local output = file_feedback(documents)

  -- Then: 구분자는 하이픈(-)이 아니라 en dash(–, U+2013)다.
  eq(
    output,
    HEADER
      .. lines({
        '## README.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (lines 20–24) Feedback on: "첫 줄',
        '둘째 줄"',
        '> 이 부분을 줄여 줘.',
        '',
        '---',
        '',
      })
  )
end

S['삭제 표시는 Remove this, 원문 펜스, 고정 문장 순서로 출력한다'] = function()
  -- Given: 7~8번째 줄에 삭제 표시를 했다.
  local documents = {
    {
      path = 'README.md',
      annotations = {
        { kind = 'deletion', start_line = 7, end_line = 8, original_text = '오래된 안내\n두 번째 줄' },
      },
    },
  }

  -- When
  local output = file_feedback(documents)

  -- Then
  eq(
    output,
    HEADER
      .. lines({
        '## README.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (lines 7–8) Remove this',
        '```',
        '오래된 안내',
        '두 번째 줄',
        '```',
        "> I don't want this in the document.",
        '',
        '---',
        '',
      })
  )
end

S['파일 전체 코멘트는 줄 라벨 없이 General feedback 문장으로 출력한다'] = function()
  -- Given: 특정 줄이 아니라 파일 전체에 코멘트를 달았다.
  local documents = {
    { path = 'README.md', annotations = { { kind = 'global', text = '전체적으로 더 짧게 써 줘.' } } },
  }

  -- When
  local output = file_feedback(documents)

  -- Then
  eq(
    output,
    HEADER
      .. lines({
        '## README.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. General feedback about the document',
        '> 전체적으로 더 짧게 써 줘.',
        '',
        '---',
        '',
      })
  )
end

-- 1개일 때 단수 "1 piece"는 위의 첫 두 테스트에서 검증한다.
S['어노테이션이 2개 이상이면 개수 문장에 복수형 pieces를 쓴다'] = function()
  -- Given: 코멘트가 2개 있다.
  local documents = {
    {
      path = 'README.md',
      annotations = {
        { kind = 'comment', start_line = 3, end_line = 3, original_text = '제목', text = '제목을 바꿔 줘.' },
        { kind = 'comment', start_line = 5, end_line = 5, original_text = '소개', text = '소개를 늘려 줘.' },
      },
    },
  }

  -- When
  local output = file_feedback(documents)

  -- Then
  eq(
    output,
    HEADER
      .. lines({
        '## README.md',
        '',
        "I've reviewed this document and have 2 pieces of feedback:",
        '',
        '### 1. (line 3) Feedback on: "제목"',
        '> 제목을 바꿔 줘.',
        '',
        '### 2. (line 5) Feedback on: "소개"',
        '> 소개를 늘려 줘.',
        '',
        '---',
        '',
      })
  )
end

-- 원본 sortAnnotationsInDocumentOrder는 파일 전체 코멘트(blockId = '')를 모든 줄 어노테이션보다 앞에 두고,
-- 전체 코멘트끼리는 만든 순서(입력 순서)를 유지한다.
S['파일 전체 코멘트를 먼저, 나머지는 시작 줄과 시작 열 순서로 정렬해 1부터 번호를 매긴다'] = function()
  -- Given: 어노테이션을 문서 순서와 다르게 달았다.
  --   같은 10번째 줄에는 시작 열(start_col) 5와 0인 코멘트가 있다.
  local documents = {
    {
      path = 'README.md',
      annotations = {
        { kind = 'comment', start_line = 30, end_line = 30, original_text = '마지막', text = 'C' },
        { kind = 'global', text = 'G1' },
        { kind = 'comment', start_line = 10, end_line = 10, start_col = 5, original_text = '뒤쪽', text = 'B' },
        { kind = 'comment', start_line = 10, end_line = 10, start_col = 0, original_text = '앞쪽', text = 'A' },
        { kind = 'global', text = 'G2' },
      },
    },
  }

  -- When
  local output = file_feedback(documents)

  -- Then: G1 → G2 → 10줄 0열(A) → 10줄 5열(B) → 30줄(C)
  eq(
    output,
    HEADER
      .. lines({
        '## README.md',
        '',
        "I've reviewed this document and have 5 pieces of feedback:",
        '',
        '### 1. General feedback about the document',
        '> G1',
        '',
        '### 2. General feedback about the document',
        '> G2',
        '',
        '### 3. (line 10) Feedback on: "앞쪽"',
        '> A',
        '',
        '### 4. (line 10) Feedback on: "뒤쪽"',
        '> B',
        '',
        '### 5. (line 30) Feedback on: "마지막"',
        '> C',
        '',
        '---',
        '',
      })
  )
end

S['여러 파일은 파일마다 경로 섹션을 만들고 번호를 1부터 다시 매긴다'] = function()
  -- Given: b.md에 2개, a.md에 1개의 어노테이션이 있다.
  local documents = {
    {
      path = 'b.md',
      annotations = {
        { kind = 'comment', start_line = 2, end_line = 2, original_text = 'b 둘째 줄', text = 'b 코멘트' },
        { kind = 'deletion', start_line = 4, end_line = 4, original_text = 'b 넷째 줄' },
      },
    },
    {
      path = 'a.md',
      annotations = {
        { kind = 'comment', start_line = 1, end_line = 1, original_text = 'a 첫 줄', text = 'a 코멘트' },
      },
    },
  }

  -- When
  local output = file_feedback(documents)

  -- Then: 개수 문장도 파일마다 따로 쓰고, a.md의 첫 항목은 다시 "### 1."이다.
  eq(
    output,
    HEADER
      .. lines({
        '## b.md',
        '',
        "I've reviewed this document and have 2 pieces of feedback:",
        '',
        '### 1. (line 2) Feedback on: "b 둘째 줄"',
        '> b 코멘트',
        '',
        '### 2. (line 4) Remove this',
        '```',
        'b 넷째 줄',
        '```',
        "> I don't want this in the document.",
        '',
        '## a.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 1) Feedback on: "a 첫 줄"',
        '> a 코멘트',
        '',
        '---',
        '',
      })
  )
end

-- "처음 어노테이션을 단 순서"는 리뷰 상태(tests/test_review.lua)가 문서 목록(documents)의 순서로 넘긴다.
-- 직렬화는 그 순서를 바꾸지 않아야 한다.
S['파일 섹션은 경로 이름순이 아니라 문서 목록(documents)에 주어진 순서대로 출력한다'] = function()
  -- Given: z.md가 a.md보다 먼저 주어졌다.
  local documents = {
    { path = 'z.md', annotations = { { kind = 'comment', start_line = 1, end_line = 1, original_text = 'z', text = 'Z' } } },
    { path = 'a.md', annotations = { { kind = 'comment', start_line = 1, end_line = 1, original_text = 'a', text = 'A' } } },
  }

  -- When
  local output = file_feedback(documents)

  -- Then
  eq(
    output,
    HEADER
      .. lines({
        '## z.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 1) Feedback on: "z"',
        '> Z',
        '',
        '## a.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 1) Feedback on: "a"',
        '> A',
        '',
        '---',
        '',
      })
  )
end

S['어노테이션이 없는 파일은 섹션을 만들지 않는다'] = function()
  -- Given: empty.md에는 어노테이션이 없고 README.md에만 있다.
  local documents = {
    { path = 'empty.md', annotations = {} },
    { path = 'README.md', annotations = { { kind = 'global', text = '좋아요.' } } },
  }

  -- When
  local output = file_feedback(documents)

  -- Then: "## empty.md" 섹션이 없다.
  eq(
    output,
    HEADER
      .. lines({
        '## README.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. General feedback about the document',
        '> 좋아요.',
        '',
        '---',
        '',
      })
  )
end

S['여러 파일이어도 구분선(---)과 줄바꿈은 전체 출력 끝에 한 번만 붙는다'] = function()
  -- Given: 어노테이션이 있는 파일이 둘이다.
  local documents = {
    { path = 'a.md', annotations = { { kind = 'global', text = 'A' } } },
    { path = 'b.md', annotations = { { kind = 'global', text = 'B' } } },
  }

  -- When
  local output = file_feedback(documents)

  -- Then: 끝은 "---\n"이고, 구분선은 파일 사이에 들어가지 않는다.
  eq(output:sub(-5), '\n---\n')
  local _, separator_count = output:gsub('\n%-%-%-\n', '')
  eq(separator_count, 1)
end

S['코멘트가 여러 줄이면 원본처럼 첫 줄에만 인용 표시(> )를 붙인다'] = function()
  -- Given: 코멘트 본문(text)에 줄바꿈이 있다.
  local documents = {
    {
      path = 'README.md',
      annotations = {
        { kind = 'comment', start_line = 1, end_line = 1, original_text = '제목', text = '첫 줄\n둘째 줄' },
      },
    },
  }

  -- When
  local output = file_feedback(documents)

  -- Then: 둘째 줄 앞에는 "> "가 없다.
  eq(
    output,
    HEADER
      .. lines({
        '## README.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 1) Feedback on: "제목"',
        '> 첫 줄',
        '둘째 줄',
        '',
        '---',
        '',
      })
  )
end

-- 라벨(kind = 'label') ---------------------------------------------------------
-- 원본은 라벨을 isQuickLabel 코멘트로 다룬다. 항목 머리에 "[<emoji> <text>]"를 붙이고,
-- 코멘트 인용 대신 tip이 있으면 tip을 인용하며, 라벨이 있는 파일 끝에 라벨별 개수(Label Summary)를 붙인다.

T['라벨 직렬화(file_feedback)'] = MiniTest.new_set()
local L = T['라벨 직렬화(file_feedback)']

-- 원본 기본 라벨 "🔍 Verify this"의 tip
local VERIFY_TIP = 'This seems like an assumption. Verify by reading the actual code before proceeding.'

L['tip이 없는 라벨은 [라벨] 머리 줄만 출력하고 인용(>) 줄을 붙이지 않는다'] = function()
  -- Given: 3번째 줄에 tip이 없는 라벨 "❓ Clarify this"를 달았다.
  local documents = {
    {
      path = 'README.md',
      annotations = {
        { kind = 'label', start_line = 3, end_line = 3, original_text = '설치 방법', text = '❓ Clarify this' },
      },
    },
  }

  -- When
  local output = file_feedback(documents)

  -- Then: 머리 줄 바로 다음이 빈 줄이고, 그 뒤에 라벨 요약이 온다.
  eq(
    output,
    HEADER
      .. lines({
        '## README.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 3) [❓ Clarify this] Feedback on: "설치 방법"',
        '',
        '### Label Summary',
        '',
        '- **❓ Clarify this**: 1',
        '',
        '---',
        '',
      })
  )
end

L['tip이 있는 라벨은 머리 줄 다음에 tip을 인용(>)으로 출력한다'] = function()
  -- Given: 5~6번째 줄에 tip이 있는 라벨 "🔍 Verify this"를 달았다.
  local documents = {
    {
      path = 'README.md',
      annotations = {
        {
          kind = 'label',
          start_line = 5,
          end_line = 6,
          original_text = '항상 빠르다',
          text = '🔍 Verify this',
          tip = VERIFY_TIP,
        },
      },
    },
  }

  -- When
  local output = file_feedback(documents)

  -- Then
  eq(
    output,
    HEADER
      .. lines({
        '## README.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (lines 5–6) [🔍 Verify this] Feedback on: "항상 빠르다"',
        '> This seems like an assumption. Verify by reading the actual code before proceeding.',
        '',
        '### Label Summary',
        '',
        '- **🔍 Verify this**: 1',
        '',
        '---',
        '',
      })
  )
end

L['라벨 요약(Label Summary)은 파일마다 그 파일의 항목 뒤, 다음 파일 섹션이나 구분선(---) 앞에 붙는다'] = function()
  -- Given: 두 파일에 라벨이 하나씩 있다.
  local documents = {
    {
      path = 'README.md',
      annotations = {
        { kind = 'label', start_line = 3, end_line = 3, original_text = '설치 방법', text = '❓ Clarify this' },
      },
    },
    {
      path = 'docs/guide.md',
      annotations = {
        { kind = 'label', start_line = 10, end_line = 10, original_text = '파서를 고친다', text = '🧪 Needs tests' },
      },
    },
  }

  -- When
  local output = file_feedback(documents)

  -- Then: 각 요약에는 그 파일의 라벨만 들어간다.
  eq(
    output,
    HEADER
      .. lines({
        '## README.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 3) [❓ Clarify this] Feedback on: "설치 방법"',
        '',
        '### Label Summary',
        '',
        '- **❓ Clarify this**: 1',
        '',
        '## docs/guide.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 10) [🧪 Needs tests] Feedback on: "파서를 고친다"',
        '',
        '### Label Summary',
        '',
        '- **🧪 Needs tests**: 1',
        '',
        '---',
        '',
      })
  )
end

L['라벨 요약은 라벨별 개수를 문서 순서에서 처음 나온 순서대로 나열한다'] = function()
  -- Given: 5번째 줄 Verify, 1번째 줄 Clarify, 9번째 줄 Verify 순서로 달았다.
  --   단 순서로는 Verify가 먼저지만, 문서 순서로는 Clarify(1번째 줄)가 먼저 나온다.
  local documents = {
    {
      path = 'README.md',
      annotations = {
        { kind = 'label', start_line = 5, end_line = 5, original_text = '첫 가정', text = '🔍 Verify this', tip = VERIFY_TIP },
        { kind = 'label', start_line = 1, end_line = 1, original_text = '제목', text = '❓ Clarify this' },
        { kind = 'label', start_line = 9, end_line = 9, original_text = '둘째 가정', text = '🔍 Verify this', tip = VERIFY_TIP },
      },
    },
  }

  -- When
  local output = file_feedback(documents)

  -- Then: Clarify 1개, Verify 2개 순서다.
  eq(
    output,
    HEADER
      .. lines({
        '## README.md',
        '',
        "I've reviewed this document and have 3 pieces of feedback:",
        '',
        '### 1. (line 1) [❓ Clarify this] Feedback on: "제목"',
        '',
        '### 2. (line 5) [🔍 Verify this] Feedback on: "첫 가정"',
        '> This seems like an assumption. Verify by reading the actual code before proceeding.',
        '',
        '### 3. (line 9) [🔍 Verify this] Feedback on: "둘째 가정"',
        '> This seems like an assumption. Verify by reading the actual code before proceeding.',
        '',
        '### Label Summary',
        '',
        '- **❓ Clarify this**: 1',
        '- **🔍 Verify this**: 2',
        '',
        '---',
        '',
      })
  )
end

L['라벨이 없는 파일에는 라벨 요약을 붙이지 않고, 라벨이 있는 파일에만 붙인다'] = function()
  -- Given: README.md에는 일반 코멘트만, docs/guide.md에는 라벨만 있다.
  local documents = {
    {
      path = 'README.md',
      annotations = {
        { kind = 'comment', start_line = 2, end_line = 2, original_text = '설치 방법', text = '예시를 추가해 줘.' },
      },
    },
    {
      path = 'docs/guide.md',
      annotations = {
        { kind = 'label', start_line = 4, end_line = 4, original_text = 'parse()', text = '👍 Looks good' },
      },
    },
  }

  -- When
  local output = file_feedback(documents)

  -- Then
  eq(
    output,
    HEADER
      .. lines({
        '## README.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 2) Feedback on: "설치 방법"',
        '> 예시를 추가해 줘.',
        '',
        '## docs/guide.md',
        '',
        "I've reviewed this document and have 1 piece of feedback:",
        '',
        '### 1. (line 4) [👍 Looks good] Feedback on: "parse()"',
        '',
        '### Label Summary',
        '',
        '- **👍 Looks good**: 1',
        '',
        '---',
        '',
      })
  )
end

L['라벨도 일반 코멘트와 똑같이 피드백 개수, 번호, 문서 순서 정렬에 포함된다'] = function()
  -- Given: 5번째 줄 코멘트를 먼저, 2번째 줄 라벨을 나중에 달았다.
  local documents = {
    {
      path = 'README.md',
      annotations = {
        { kind = 'comment', start_line = 5, end_line = 5, original_text = '예시', text = '더 짧게 써 줘.' },
        { kind = 'label', start_line = 2, end_line = 2, original_text = '설치 방법', text = '❓ Clarify this' },
      },
    },
  }

  -- When
  local output = file_feedback(documents)

  -- Then: 개수는 2개이고, 2번째 줄의 라벨이 1번이다.
  eq(
    output,
    HEADER
      .. lines({
        '## README.md',
        '',
        "I've reviewed this document and have 2 pieces of feedback:",
        '',
        '### 1. (line 2) [❓ Clarify this] Feedback on: "설치 방법"',
        '',
        '### 2. (line 5) Feedback on: "예시"',
        '> 더 짧게 써 줘.',
        '',
        '### Label Summary',
        '',
        '- **❓ Clarify this**: 1',
        '',
        '---',
        '',
      })
  )
end

return T
