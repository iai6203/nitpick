-- 메시지 리뷰 피드백 직렬화(nitpick.export.message_feedback) 테스트
--
-- 기대값은 원본 plannotator(backnotprop/plannotator@87dcec4)의
-- exportMessageAnnotations에 같은 입력을 넣어 얻은 출력이다.
-- 줄 번호는 파일 리뷰와 마찬가지로 어노테이션의 실제 줄 범위(start_line~end_line)를 쓴다.
--
-- 입력 모양 (제안):
--   메시지(message) = { text = '붙여넣은 답변 전체', annotations = { 어노테이션, ... } }
--   어노테이션의 모양은 파일 리뷰(tests/test_export.lua)와 같다.
--
-- 파일 리뷰와 다른 점(원본 그대로):
--   - 항목 제목이 "###"가 아니라 "##"이다.
--   - 원본이 끝 공백을 지우므로(trimEnd) 출력이 "---"로 끝나고 마지막 줄바꿈이 없다.

local eq = MiniTest.expect.equality

-- 메시지 리뷰 피드백을 만든다(message_feedback).
local function message_feedback(message)
  return require('nitpick.export').message_feedback(message)
end

-- 여러 줄 문자열을 읽기 쉽게 쓰기 위한 도우미: 각 원소를 줄바꿈으로 잇는다.
local function lines(list)
  return table.concat(list, '\n')
end

-- 메시지 리뷰의 머리말. 사례 13에서 문자 그대로 검증하고, 나머지 테스트에서는 이 상수로 줄여 쓴다.
local HEADER = lines({
  '# Message Feedback',
  '',
  'The following feedback spans 1 assistant message. Each section includes an excerpt of the message it applies to.',
  '',
  '## Message 1',
  '',
  'Message excerpt:',
  '',
})

local T = MiniTest.new_set()

T['메시지 리뷰 피드백(message_feedback)'] = MiniTest.new_set()
local S = T['메시지 리뷰 피드백(message_feedback)']

-- 사례 13
S['머리말, 메시지 발췌, 메시지 피드백 순서로 출력하고 주체(subject)를 message로 쓴다'] = function()
  -- Given: 붙여넣은 답변에 전체 코멘트, 한 줄 코멘트, 삭제 표시가 하나씩 있다.
  local message = {
    text = '# 계획\n\n첫 단계를 진행합니다.\n오래된 문장',
    annotations = {
      { kind = 'global', text = '전체적으로 좋아.' },
      { kind = 'comment', start_line = 3, end_line = 3, original_text = '첫 단계', text = '더 구체적으로.' },
      { kind = 'deletion', start_line = 4, end_line = 4, original_text = '오래된 문장' },
    },
  }

  -- When
  local output = message_feedback(message)

  -- Then: 전체 코멘트와 삭제 문장에 "document"가 아니라 "message"가 들어가고,
  --   항목 제목은 "##", 출력은 마지막 줄바꿈 없이 "---"로 끝난다.
  eq(
    output,
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
      '오래된 문장',
      '```',
      '',
      '# Feedback for Message 1',
      '',
      "I've reviewed this message and have 3 pieces of feedback:",
      '',
      '## 1. General feedback about the message',
      '> 전체적으로 좋아.',
      '',
      '## 2. (line 3) Feedback on: "첫 단계"',
      '> 더 구체적으로.',
      '',
      '## 3. (line 4) Remove this',
      '```',
      '오래된 문장',
      '```',
      "> I don't want this in the message.",
      '',
      '---',
    })
  )
end

-- 사례 14
-- 원본은 1200 "글자"에서 자른다. 바이트가 아니라 글자 수이므로 한글로 검증한다.
S['1200자를 넘는 메시지는 발췌문을 1200자에서 자르고 ...을 붙인다'] = function()
  -- Given: 한글 '가'가 1201자인 메시지다.
  local message = {
    text = string.rep('가', 1201),
    annotations = { { kind = 'global', text = '길다.' } },
  }

  -- When
  local output = message_feedback(message)

  -- Then: 발췌문은 '가' 1200자 뒤에 "..."이 붙는다.
  eq(
    output,
    HEADER
      .. lines({
        '```markdown',
        string.rep('가', 1200) .. '...',
        '```',
        '',
        '# Feedback for Message 1',
        '',
        "I've reviewed this message and have 1 piece of feedback:",
        '',
        '## 1. General feedback about the message',
        '> 길다.',
        '',
        '---',
      })
  )
end

-- 사례 15
S['메시지 본문에 ``` 펜스가 있으면 발췌문을 더 긴 ```` 펜스로 감싼다'] = function()
  -- Given: 붙여넣은 답변 안에 코드 블록이 있다.
  local message = {
    text = '예시:\n```lua\nprint(1)\n```',
    annotations = { { kind = 'global', text = '좋아.' } },
  }

  -- When
  local output = message_feedback(message)

  -- Then: 바깥 펜스가 백틱 4개라서 안쪽 ``` 때문에 발췌문이 중간에 끊기지 않는다.
  eq(
    output,
    HEADER
      .. lines({
        '````markdown',
        '예시:',
        '```lua',
        'print(1)',
        '```',
        '````',
        '',
        '# Feedback for Message 1',
        '',
        "I've reviewed this message and have 1 piece of feedback:",
        '',
        '## 1. General feedback about the message',
        '> 좋아.',
        '',
        '---',
      })
  )
end

-- 사례 70
-- 메시지 형식에서는 라벨 요약(Label Summary)이 구분선(---) 뒤에 "##" 제목으로 붙고,
-- 원본이 끝 공백을 지우므로(trimEnd) 요약 목록의 마지막 줄로 끝난다.
S['라벨이 있으면 구분선(---) 뒤에 ## Label Summary를 붙이고 끝 공백 없이 끝난다'] = function()
  -- Given: 붙여넣은 답변 3번째 줄에 라벨 "❓ Clarify this"를 달았다.
  local message = {
    text = '# 계획\n\n첫 단계를 진행합니다.',
    annotations = {
      { kind = 'label', start_line = 3, end_line = 3, original_text = '첫 단계', text = '❓ Clarify this' },
    },
  }

  -- When
  local output = message_feedback(message)

  -- Then
  eq(
    output,
    HEADER
      .. lines({
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
        '## 1. (line 3) [❓ Clarify this] Feedback on: "첫 단계"',
        '',
        '---',
        '',
        '## Label Summary',
        '',
        '- **❓ Clarify this**: 1',
      })
  )
end

return T
