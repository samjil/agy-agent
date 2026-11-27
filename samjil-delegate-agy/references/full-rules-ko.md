# Full rules (Korean)

The full working rules for this skill, in Korean (the delegation rules were rewritten in 2026-11: default is to do the work directly). Optional reading; the English SKILL.md and the other reference files are enough for normal use. Where this text mentions `install.ps1` or the GitHub repository, that is the installer described in the English SKILL.md.


# samjil-delegate-agy: Antigravity CLI 위임 (명세를 정할 수 있는 일은 Gemini 4 Hydrogen/Neon/Carbon 단계 + 슬래시 명령 최적화로 위임 + 매우 복잡한 결정은 Neon/Carbon 과 상의 + 필수 검토)

## 먼저 설치해야 하는 것 (Requirements)

이 스킬은 규칙 문서이고, 실제로 agy 를 돌리는 워처·스크립트·세션 훅은 저장소의 `install.ps1` 이 설치한다. 스킬만으로는 위임이 동작하지 않는다.

- **Windows + PowerShell 5.1** 전용이다(macOS · Linux 미지원).
- **Antigravity CLI(`agy`)** 를 설치하고 로그인해 둔다. 설치와 로그인은 Antigravity 공식 안내를 따른다. 이 스킬은 `agy` 를 설치하거나 로그인시키지 않는다.
  준비가 됐는지는 PowerShell 에서 아래 세 가지로 확인한다.
  1. `Get-Command agy` — `agy` 실행 파일이 PATH 에 잡힌다.
  2. `agy models` — 모델 목록(`gemini-4-hydrogen-medium` 등)이 나온다. 목록이 나오면 로그인과 네트워크가 되는 것이다.
  3. `agy -p "ok라고만 답해"` — 응답이 한 줄 돌아온다. 이게 되면 위임을 쓸 수 있다.
- 저장소 <https://github.com/samjil/agy-agent> 를 받아 `install.ps1` 을 실행한다. 스킬 · 워처 런타임(`~/.samjil/delegate-agy/`) · 세션 시작 훅 · 대시보드 뷰어가 설치된다.

*English summary:* delegates specifiable implementation, fixes, refactors, tests and UI work plus bulky simple jobs to the Antigravity CLI (`agy`) on Gemini 4 Hydrogen/Neon/Carbon tiers with slash-command optimization (`@cmd`/`@mode`) through a local watcher, consults Neon (`think`) or Carbon (`think-carbon`) before very complex decisions, keeps context-heavy work and final calls on risky changes for Claude, and requires reviewing every result. It needs Windows with PowerShell 5.1, the `agy` CLI, and the runtime installed by `install.ps1` from <https://github.com/samjil/agy-agent>; the skill alone will not delegate.

## 위임 범위와 단계 (발동 규칙)

이 스킬은 **작업 요청을 받으면 먼저 위임할 수 있는지 보고, 할 수 있으면 위임하는 규칙**이다. 기본은 위임이고, 직접 하는 것은 아래 "직접 한다" 칸의 이유가 있을 때뿐이다(2026-11-20 사용자 결정: 한도 비교 없이 되도록 위임). 새 세션에서도 같다 — 세션 시작 훅(`session-start-hook.ps1`)이 규칙 한 줄과 워처 상태만 문맥에 넣으며, 워처가 꺼져 있어도 위임하면 `submit-task.ps1` 이 자동으로 켜고 켜지지 않으면 작업자를 직접 실행한다.

- **사용자가 "위임"이라고 말하지 않아도 불러온다.** 코드 · 문서 · 설정 파일 · xlsx/pptx 를 고치거나 만드는 작업을 시작하기 전, 그리고 그런 작업을 Agent 도구로 넘기기 전에 이 스킬을 먼저 불러온다.

### 0. Agent 도구(Claude 서브에이전트)보다 agy 가 먼저

agy 가 할 수 있는 일을 Agent 도구로 넘기지 않는다. **Agent 도구는 agy 가 못 하는 일이거나, agy 가 실패 · 시간 초과했을 때만 쓴다.**
컨텍스트가 커서 서브에이전트가 agy 제출 · 대기 · 검토를 대신 맡는 경우(7절)는 괜찮다: 일 자체는 agy 가 한다.

| agy 로 간다(위임) | agy 로 못 간다(Claude 나 Claude 서브에이전트) |
|---|---|
| md 여러 개 일괄 수정(로컬 경로 지우기, 명칭 바꾸기, 번호 다시 매기기) | 운영 · 개발 DB 조회 |
| xlsx(openpyxl) · pptx(python-pptx) 문구 바꾸기 | VPN 이 필요한 SSH 확인 |
| 범위가 분명한 웹뷰 리팩터링, vitest 등 시험 작성 | 브라우저로 MR 처리 · 웹 콘솔 작업, 메일 읽기 |
| 저장소 밖 폴더의 코드 · 문서 · 설정 수정(`@cwd` 로 지정) | 사용자 결정을 계속 받아 가며 하는 설계 판단 |
| 여러 파일을 읽고 요약하는 1차 탐색 | 웹 검색이 필요한 사실 확인(agy 에는 웹 검색이 없다) |

- **Agent 도구 관문(PreToolUse 훅):** `install.ps1` 이 Agent 도구에 `PreToolUse` 훅을 건다. 읽기 전용 종류(Explore · Plan · claude-code-guide · web-fetch 등)나 프롬프트에 agy · submit-task 가 들어 있는 호출은 그냥 통과하고,
  그 밖의 Agent 호출은 **세션마다 처음 한 번** 막고 위 규칙을 알린다. agy 로 못 가는 일이면 같은 호출을 다시 하면 통과한다(두 번째부터는 참고 한 줄만 붙는다).
  환경 변수 `AGY_AGENT_GATE` 로 바꾼다: `once`(기본) · `note`(막지 않고 참고 한 줄만) · `off`(끄기).
- 저장소 밖 폴더 예: `@cwd: D:\OneDrive - Example\Projects\my-webview`. 규칙은 같다(폴더를 사용자에게 한 번 확인, git 아래가 아니면 바꿀 파일을 먼저 복사해 둔다).

### 왜 이렇게 배치했나 (공용 Gemini Models 한도 · Carbon / Neon / Hydrogen 특성)

모든 Gemini 모델은 **하나의 공용 "Gemini Models" 한도**를 함께 쓴다(Argon 별도 주간 한도는 폐지).
- **Carbon (`gemini-4-carbon-low|medium|high`)**: 최상위(flagship) 모델로 가장 깊은 추론이 가능하나(AA 지능 지수 `high` 60), 속도(~56 tok/s, 첫 토큰 ~73초)가 느리고 한도 소모가 가장 크다(기준 100%, API $4/$20). **아키텍처·초기 설계, 원인 불명의 다중 서비스 버그, 난해한 레거시 로직, 대규모 변경 전 최종 검토 — 즉 Neon 으로 풀지 못한 문제**에만 쓴다.
- **Neon (`gemini-4-neon-low|medium|high|xhigh`)**: 균형 잡힌 주력 모델이다(AA 지능 지수 `high` 60 / `xhigh` 61, AA Coding Agent Index **1위 58.64**(`xhigh`), ~101–110 tok/s, 첫 토큰 ~41초). 한도는 Carbon 대비 ~30–32% 적다(API $3/$15). **실무 개발의 80% 이상(다중 파일 수정 · 리팩터링 · 디버깅)**을 맡긴다. 일부 계정에서 `xhigh` 가 HTTP 400 을 돌려주면 워처가 `neon-high` 로 폴백한다.
- **Hydrogen (`gemini-4-hydrogen-low|medium|high|xhigh`)**: 빠른 실행 모델이다(AA 지능 지수 `high` 51 / `xhigh` 54, ~165–170 tok/s, 첫 토큰 ~20초). 한도는 Carbon 대비 50% 이상 적다(API $1.50/$7.50). **보일러플레이트 · 단위 테스트 · 단순 UI · 요약 · 명세가 분명한 반복 작업**에 쓴다.
- **Orchestrator (Neon / Carbon)**: `Orchestrator (Neon)` 은 Neon 이 계획/검토하고 Hydrogen 이 편집·시험을 실행하며, `Orchestrator (Carbon)` 은 Carbon 이 읽기 전용으로 의존성 파악과 설계를 맡고 Hydrogen 이 구현한다(단독 Carbon 대비 한도 ~24% 절감, 완료 속도 ~19% 빠름). **실행자는 언제나 Hydrogen** 이다.
- 토큰을 미리 예상하는 방식은 실제와 어긋나 의미가 없어 예상 기록 · 통계 · 보정은 없다.
- Claude 호출 하나의 비용은 대화 컨텍스트 크기에 비례한다. 위임 한 건의 호출 수를 줄이는 것이 핵심이다.

### 1. 위임하는 일과 직접 하는 일

| 위임한다(기본) | 직접 한다 — 이것만 |
|---|---|
| Claude 가 명세(경로 · AS-IS → TO-BE · 이름 · 확인 방법)를 정할 수 있는 구현 · 수정 · 리팩터링 · 시험 작성 · 화면 구현 | 이 대화의 맥락이 필요하고 브리프에 담을 수 없는 일 |
| 양이 많고 단순한 일: 긴 로그 · 문서 요약, 번역, 여러 파일에 같은 수정, 형식 변환, 시험 데이터, 1차 검색 · 코드 탐색 | 한두 줄 수정(브리프를 쓰는 비용이 더 크다) |
| 무엇을 정하기 전에 큰 파일 · 여러 파일을 읽고 요약하는 일 | 보안 · 인증 · 결제 · 마이그레이션처럼 틀리면 되돌리기 어려운 일의 **최종 판단**(초안은 맡겨도 판단과 줄 단위 검토는 Claude) |
| 방금 바꾼 코드의 시험 · 문서 작성과 갱신 | 사용자와의 대화, agy 결과 검토 |

- **헷갈리면 위임한다.** "맥락이 조금 필요한" 일은 대개 사실 몇 가지만 필요하다: 그 사실을 브리프에 적어 위임한다.
- 큰 일은 여러 브리프로 나눠 병렬로(`-NoWait`, 최대 5개) 보낸다. 일부만 직접 하고 나머지를 미루지 않는다.
- 같은 요청 안에서도 꼭 직접 해야 하는 부분만 남기고 나머지는 위임한다.

그 밖에 Claude 전용 도구(웹 검색 · 브라우저 · MCP)가 꼭 필요한 일은 직접 한다. xlsx · pptx 문구 바꾸기처럼 파이썬 라이브러리(openpyxl · python-pptx)로 되는 일은 문서 스킬 대신 agy 에 위임한다.
사용자가 "agy 에게 시켜 줘"라고 했는데 직접 할 일이면 한 줄로 알리고 직접 할지 묻는다. 사용자가 그래도 원하면 따른다. 워처가 꺼져 있어도(`DEAD` · `MANUAL_STOP`) 묻지 않고 그대로 `submit-task.ps1` 로 제출한다.

### 2. 단계 고르기 (`@model: <단계>`)

빠른 단순·반복 작업은 **Hydrogen**, 실무 개발 80%+의 주력은 **Neon**, 아키텍처·원인 불명 다중 서비스 버그·난해한 레거시·대규모 변경 최종 검토처럼 Neon 으로 풀지 못한 최난도만 **Carbon** 을 쓴다. Claude 계열 · GPT-OSS 는 쓰지 않는다.

| 단계 | 쓰는 때 | 모델 | 대기 한도 |
|---|---|---|---|
| `quick` | 조회 · 요약 · 번역 · 형식 변환 · 짧은 질문 (가장 빠르고 한도 최소) | Hydrogen low | 3분 |
| `build` | 보일러플레이트 · 단위 테스트 · 단순 UI · 명세가 분명한 반복 수정 (**코드 작업 기본**, Carbon 대비 한도 50%+ 절감) | Hydrogen medium | 8분 |
| `build-high` | Hydrogen 상위 추론 구현 · `high` 세션(Orchestrator 실행기 포함)의 `agy-sub` 동급 위임 | Hydrogen high | 10분 |
| `build-hard` | 다중 파일 수정 · 리팩터링 · 디버깅 · 경계 조건이 많은 일반 실무 구현 · build 실패 재시도 (Carbon 대비 한도 ~30% 절감) | Neon medium | 12분 |
| `feature` | 여러 파일 새 기능에서 작업 나누기 · 하위 계획까지 agy 에 맡길 때 (Neon 계획/검토 + Hydrogen 실행) | Orchestrator (Neon) | 20분 |
| `feature-carbon` | 아키텍처·초기 설계가 까다로운 다중 파일 기능 (Carbon 읽기 전용 설계 + Hydrogen 실행, 단독 Carbon 대비 한도 ~24% 절감·~19% 빠름) | Orchestrator (Carbon) | 20분 |
| `think` | 파일 수정은 적고 깊은 추론: 설계 검토 · 난해한 버그 원인 분석 · 상의 (주력 Neon) | Neon high | 20분 |
| `think-carbon` | 아키텍처·초기 설계, 원인 불명 다중 서비스 버그, 난해한 레거시, 대규모 변경 최종 검토 — Neon 으로 풀지 못한 일 (한도 소모 최대) | Carbon high | 20분 |
| `deep` | 파일 수는 적어도 논리가 극도로 까다로운 구현: 알고리즘 · 동시성/경쟁 조건 · 파서/상태 기계 · 수치 정밀도 · 측정 목표가 있는 성능 개선 · think/think-carbon 이 원인을 짚은 버그의 수정 · build-hard 실패의 다시 보내기 | Neon Extra (xhigh) | 20분 |

- **`deep` 은 Claude 가 스스로 고른다.** 사용자가 말하지 않아도 위 조건이면 쓴다. 명세가 분명하고 논리가 평범한 일에는 쓰지 않는다(느리고 토큰 소모가 크다). 계정에서 `xhigh` 가 effort/thinking-level 관련 HTTP 400 을 돌려주면 워처가 `neon-high` 로 폴백한다.
- **`build` vs `build-hard` vs `feature`/`feature-carbon` 의 구분:** 보일러플레이트·단위 테스트·단순 UI·명세가 분명한 소규모 수정이면 `build`, 다중 파일 수정·리팩터링·디버깅·경계 조건이 많거나 재시도면 `build-hard`(Neon medium), 작업 나누기·하위 계획까지 맡길 때만 `feature`(Orchestrator Neon) 또는 `feature-carbon`(Orchestrator Carbon).
- **기본은 Neon(80%+), Carbon(`think-carbon`/`feature-carbon`)은 예외적으로만:** 한도 소모가 가장 크므로 아키텍처·초기 설계, 원인 불명 다중 서비스 버그, 난해한 레거시, 대규모 변경 최종 검토, 또는 Neon 이 실패한 문제에만 쓰고, 명세가 분명한 반복 작업은 Hydrogen 을 쓴다.
- `@model` 을 빼면 워처가 `quick`(읽기만 하는 짧은 일) 또는 `build`(파일을 바꾸는 일)만 고른다. 더 높은 단계는 자동으로 고르지 않는다.
- 폴백(한도 · 과부하 오류 또는 `-xhigh` 의 effort 관련 HTTP 400)과 모델 이름은 `references/models.md`, 설정 파일은 `~/.samjil/delegate-agy/config/models.json`(바꿀 값은 같은 폴더 `models.local.json`).

### 2-1. 실행 슬래시 명령어·모드 최적화 (`@cmd` / `@mode`)

지시문 머리에 `@model:` 과 함께 선택적으로 `@cmd: <명령>` 또는 `@mode: <모드>` 를 적으면 작업 성격에 맞는 `agy` 실행 방식을 활용할 수 있다(세부: `references/brief-and-commands.md`).

| 지시어 | 적합한 위임 작업 | 워처 처리 · 한도 규칙 |
|---|---|---|
| `@cmd: goal` | 명세가 명확해 끝까지(100% 완료·전체 테스트 통과) 자율 실행할 작업 | 완료 시 agy 가 붙이는 `<!-- GOAL_COMPLETE -->` 마커를 워처가 정리. |
| `@cmd: swarm` | **파일 소유권이 겹치지 않게** 넓게 나뉘는 작업 + 독립 검증자(Verifier) 교차 검증 | 워처가 `workspace:"inherit"` · 커밋 금지 규칙을 자동 주입하고 대기 한도를 20분 이상으로 높이며, 하위 워커 대화 활동까지 추적해 조기 멈춤 오판을 막음. **agy 사용량이 커서 작업 모양이 맞을 때만 쓴다.** |
| `@cmd: run-workflow` | 다수 파일 정형 팬아웃 또는 엄격한 JSON 스키마 단계별 Python 오케스트레이션 | `parallel()` / `pipeline()` 실행, `workspace:"inherit"` 주입 · 20분 이상 대기 · 하위 대화 추적. **agy 사용량이 커서 작업 모양이 맞을 때만 쓴다.** |
| `@cmd: boost` | 단일 난이도가 극도로 높은 버그·레이스 컨디션·알고리즘 (구현→반박→수정→재검증) | 대기 한도 20분 이상 · 하위 대화 추적. **agy 사용량이 커서 작업 모양이 맞을 때만 쓴다.** |
| `@cmd: browser` | 로컬 화면 UI 회귀 확인·스크린샷·콘솔/네트워크 점검 (`chrome-devtools-mcp`) | 브라우저 서브에이전트 하위 대화를 추적. 보고서/스크린샷 경로를 [4. 검증]에 명시. |
| `@cmd: plan` · `@mode: plan` | 수정 전 읽기 전용 설계/계획 점검 | `@mode: plan` 은 내부적으로 `/plan` 을 붙이므로 둘을 동시에 적지 않는다. |

- **`Orchestrator` vs `/swarm` vs `/run-workflow`:** 단일 흐름 다중 파일 기능은 `feature`/`feature-carbon` (선형 비용), 파일이 깔끔히 분리되고 상호 검증이 필요할 때만 `@cmd: swarm`, N개 파일 기계적 반복·단계 파이프라인은 `@cmd: run-workflow`. 이미 파일별 명세를 다 쪼갠 작업은 `-NoWait` 로 여러 개의 `build` 작업을 병렬 제출하는 편이 더 가볍고 저렴하다.
- **대형 지시문(`> 8000자`)·`@upgrade` 호환:** 본문 첫머리에 `/swarm` 을 쓰는 대신 `@cmd: swarm` 으로 적으면, 워처가 파일 참조로 넘길 때도 `"/swarm @prompt_xxx.txt"` 처럼 명령줄 앞에 붙여 슬래시 명령이 정상 확장된다.
- **대화형 TUI 전용 명령과 소비자 플랜 안내:** `/teamwork`, `/grill-me`, `/rewind`, `/fork`, `/btw`, `/tasks`, `/agents`, `/diff`, `/context`, `/compact`, `/learn`, `/permissions`, `/resume` 은 대화형 TUI 전용이라 헤드리스 워처에서 실행할 수 없다(`@cmd` 와 `agy-brief-lint` 가 거부/경고). 또한 Google Antigravity 공식 FAQ 는 소비자 플랜(Google AI Pro/Ultra)에서 `agy -p` 를 직접 스크립팅·CI 용으로 안내하고 외부 에이전트 내부 자동 래핑은 공식 지원하지 않는다고 명시한다. 따라서 `/teamwork` 같은 장기 마일스톤이나 `/grill-me` 정렬, 직접 실행이 나은 경우에는 명세를 `docs/spec-<주제>.md` 파일로 저장하고 사용자가 대화형 `agy` 터미널에서 `@파일명` 과 함께 실행하도록 안내한다.

### 3. 매우 복잡한 일은 Neon(`think`) 또는 Carbon(`think-carbon`)과 최소 한 번 상의한 뒤 결정

기준: 여러 모듈에 걸친 설계, 되돌리기 어려운 구조 변경, 원인이 안 보이는 버그, 방향이 둘 이상이라 고르기 어려운 결정.

- 상의는 `submit-task.ps1` 위임(`@model: think` 기본, 이어서 논의할 때는 `@session: consult-<주제>`)으로 한다. 최난도 아키텍처·초기 설계·원인 불명 다중 서비스 버그·난해한 레거시·대규모 변경 최종 검토처럼 세컨드 오피니언이나 Neon 으로 풀리지 않는 판단이 필요하면 `@model: think-carbon` 을 적는다.
- 보내는 것: 문제, 선택지, Claude 의 추천과 이유, **관련 파일 경로와 지켜야 할 제약**(상대 모델은 이 대화를 모른다). 그리고 항상 "단순 동의 금지 — 반론 · 놓친 경계 조건 · 대안 위주로, 바꾸기를 권하는 것은 번호 목록으로"를 넣는다.
- 횟수: 원칙 1회 왕복, 최대 2회(핵심 아키텍처 결정 시 Neon/Carbon 교차 세컨드 오피니언 등). 상의 호출은 위임 한 건의 "Claude 호출 3회" 한도와 따로 센다.
- 상의가 대기 한도(20분)를 넘기거나 실패하면 다시 묻지 않고 혼자 결정하고, 상의하지 못했다는 사실을 사용자에게 알린다.
- 상의 의견을 반영해 결정한 뒤 사용자에게 "상의해 바꾼 점"을 한두 줄로 알린다. 받아들이지 않은 의견은 이유와 함께 한 줄로.
- 상의는 판단을 돕는 것이지 넘기는 것이 아니다. 최종 결정과 책임은 Claude 에게 있다.
- 난해한 버그는 `think`(또는 다중 서비스/레거시 버그는 `think-carbon`)으로 원인 · 고칠 방향을 받고, 고치는 일은 `deep`(Neon Extra, 여유 한도 시 `@cmd: boost`)으로 보낸다(원인 진단 ↔ 실행).

### 4. 기다리는 한도는 단계의 대기 한도 (취소)

- 제출은 `-NoWait`, 같은 메시지에서 백그라운드 대기 한 번: `submit-task.ps1 -Poll <ID> -CancelOnTimeout`. `-MaxWaitSec` 을 안 주면 작업 단계의 대기 한도(quick 3분 · build 8분 · build-hard 12분 · 나머지 20분)까지 기다린다. 제출할 때 표준 오류에 `[단계] <단계> (<모델>) · 대기 한도 <초>` 가 찍힌다.
- 한도 안에 안 끝나면 그 대기가 작업을 취소하고(`===CANCELLED=== <ID>`, 종료 코드 4) Claude 가 직접 한다. 단계의 대기 한도가 지났을 때 작업이 여전히 진행 중(새 단계·도구 출력 등)이거나 대기열에서 차례를 기다리는 중이면 계속 기다리며, 최근 5분 동안 진행이 없거나 2시간 절대 한도를 넘기면 취소한다. 반복해서 확인하지 않는다(확인할 때마다 대화 전체를 다시 읽는다).
- `-MaxWaitSec <초>` 는 `-WaitSeconds` 와 같은 뜻이고 주면 그것을 쓴다(안 주고 `-CancelOnTimeout` 도 없으면 기본 170초). 
- 일찍 취소하려면 `submit-task.ps1 -Cancel <ID>`: 대기 중이면 inbox 의 지시 파일을 치우고, 실행 중이면 `running\<ID>.json` 의 작업자 프로세스 트리를 끝낸다. 워처가 취소 표시(`running\<ID>.cancel`)를 보고 그 작업을 실패가 아니라 **취소(CANCELLED)** 로 마무리하고(워처가 꺼져 있으면 submit-task 가 직접 마무리한다), 뷰어 카드는 "취소"로 보인다. 이미 끝난 작업은 `===DONE===`, 없는 작업은 `===NOTFOUND===` 이다.
- **상태는 추측하지 않고 확인한다:** 사용자에게 위임이 "아직 도는 중" · "기다리는 중"이라고 말하기 전에 `submit-task.ps1 -Status <ID>`(즉시 끝나는 읽기 전용 확인. `===STATUS=== <ID> <상태> | ...`, 종료 코드 0 끝남 / 2 대기열 · 실행 중 / 4 작업자 사라짐)로 실제 상태를 보고 "몇 시에 끝남", "실행 중, 마지막 활동 N초 전", "작업자 사라짐"처럼 구체적으로 알린다. 대기를 맡긴 서브에이전트가 "백그라운드 작업을 기다리는 중"으로 오래 남아 있으면 그냥 기다리지 말고 `-Status` 와 그 서브에이전트가 띄운 프로세스를 직접 확인한다. 서브에이전트에게는 대기 · 시험마다 벽시계 상한(예: "15분을 넘기면 그때까지의 결과로 보고")을 준다.
### 5. 다시 보내기는 사다리대로 한 단계 · 한 번만

- 시험에서 막히면 `build` → `build-hard`, `build-hard` → `deep` 으로 **한 단계만** 올려 한 번 다시 보낸다(같은 브리프 + 무엇이 실패했는지). 워처의 실패 메시지에도 `[단계 build. 한 단계 올려 다시 보낼 곳: build-hard]` 처럼 적힌다.
- 이때만 백그라운드 대기를 두 번 쓰고, 두 번의 대기를 합쳐 `build` 에서 시작했으면 20분, `build-hard` 에서 시작했으면 30분을 넘기지 않는다.
- 처음부터 `deep` 이었던 일, `quick` · `feature` · `think` 가 막히면 다시 보내지 않고 직접 고친다(원인이 안 보이면 `think` 로 먼저 상의).
- agy 가 실패하면(`===ERROR===` 이거나 답이 agy 실행 실패를 알리면) `git diff --stat` 으로 반쯤 한 수정이 있는지 보고 나머지를 직접 마무리한다.

### 6. 위임 한 건의 Claude 호출은 3회 이내 (다시 보내면 5회)

1. **호출 1**: 워처 확인 + 제출(`-NoWait`) + 백그라운드 대기(`-Poll <ID> -CancelOnTimeout`)를 한 메시지에서. 큰 수정 전에는 `git diff` 를 먼저 저장해 둔다.
   - 제출 출력에 `===UPDATE_AVAILABLE===`(종료 코드 5)가 나오면 아무것도 대기열에 들어가지 않은 것이다. 사용자에게 새 버전이 있음을 한 줄로 알리고 먼저 업데이트할지(출력된 PowerShell 명령 또는 뷰어 업데이트 버튼) 묻는다. 업데이트하지 않고 진행하려면 같은 브리프를 그대로 다시 보낸다(같은 버전은 24시간 동안 통과한다).
2. **호출 2**: 결과 읽기와 확인을 한 명령으로 — `-Poll` 결과 + `git diff --stat`(필요한 diff) + 시험 명령.
3. **호출 3**(필요하면): 직접 보완.
- **Claude 데스크톱 앱 사용률 수집:** `mcp__ccd_session_mgmt__get_usage` 도구가 있으면 도구를 쓰는 **모든 질문(직접 · 위임 공통)**의 첫 도구 호출과 병렬로 부른다(최대 10분에 한 번). 이어지는 다음 셸 명령 앞에 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.samjil/delegate-agy/scripts/note-claude-limits.ps1" -FiveHourPct <percentUsed> -FiveHourReset <resetsAt> -WeekPct <percentUsed> -WeekReset <resetsAt> ;` 를 붙여 `plan.windows`(5-hour limit / Weekly · all models) 값을 남긴다(뷰어 한도 추정용; 도구가 없거나 `plan` 이 비면 건너뜀).

### 7. 컨텍스트가 크면 agy 제출 절차를 서브에이전트에 맡긴다

세션 컨텍스트가 기준(기본 20만, 환경 변수 `AGY_CTX_SUBAGENT_THRESHOLD` 가 있으면 그 값)을 넘어도 **일은 그대로 agy 가 한다.** 바뀌는 것은 위임 절차(agy 제출 · 대기 · diff 검토 · 시험)를
**빈 컨텍스트의 서브에이전트 하나**가 대신 맡는다는 점뿐이다. 본 세션은 브리프 작성과 보고 확인(`git diff --stat` 한 번)만 한다. 서브에이전트는 저렴한 모델로 쓰고 보고는 5줄 이내(통과 여부, 바뀐 파일, 걱정)로 받는다.
서브에이전트가 일을 직접 하는 것은 agy 로 못 하는 일(DB · VPN · 브라우저 · 메일)뿐이고, 대화 맥락이 필요한 판단은 본 세션이 한다. Claude 데스크톱 앱에서는 서브에이전트가 `mcp__ccd_session_mgmt__get_usage` 도구를 갖고 있으면 직접 `note-claude-limits.ps1` 까지 실행하고, 없으면 본 세션이 마지막 `git diff --stat` 호출 앞에 붙여 실행한다.
서브에이전트에게 주는 지시에는 기다리는 방법을 꼭 넣는다: "백그라운드 `submit-task.ps1 -Poll <ID> -CancelOnTimeout` 하나로만 기다리고 차례를 끝낸다. 서브에이전트는 자기가 띄운 백그라운드 명령이 **모두** 끝나야 다시 깨어나므로, 출력 파일을 지켜보는 두 번째 백그라운드 명령(until/while + sleep 반복)을 띄우지 않는다. 조건이 끝내 안 맞으면 영원히 깨어나지 못한다(2026-11-23 · 24 실제로 15시간 · 8분 멈춤). 다른 것을 기다려야 하면 시간 제한을 둔 포그라운드 명령으로 기다린다."

- **질문 시점에 알린다:** 질문을 보낼 때마다 훅(UserPromptSubmit)이 Claude Code 가 넘기는 대화 기록 경로로 컨텍스트 크기를 읽어(`sub\claude-transcript.ps1` 의 `Get-ClaudeTranscriptLastUsage`),
  기준을 넘었으면 `[컨텍스트 <N>k] 기준 <M>k 를 넘었다: 이번 작업을 위임하면 samjil-delegate-agy 로 agy 에 제출한다. 제출 · 대기 · diff 검토 · 시험은 서브에이전트 하나(저렴한 모델)가 대신 맡고 ...` 한 줄을 넣는다.
  (2026-11-23: 예전 문구는 agy 가 주어로 없어 "Claude 서브에이전트에게 일 자체를 맡겨라"로 읽혀, 위임할 일이 모두 Agent 도구로 간 일이 있었다. 그래서 agy 를 주어로 다시 썼다.)
- **제출한 뒤에 알게 됐으면:** `submit-task.ps1` 도 제출할 때 같은 기준으로 stderr 에 `[컨텍스트 <N>k] 컨텍스트가 큽니다(기준 <M>k). 제출은 됐으니 이 작업의 대기 · diff 검토 · 시험은 본 세션에서 하지 말고 ...` 를 알린다.
  이미 제출된 작업이므로 다시 제출하지 말고, 본 세션에서 대기(`-Poll`)를 시작하지도 말고, 작업 ID 와 확인할 시험 명령을 서브에이전트에 넘겨 대기 · 검토를 맡긴다.
- 2026-11-18: 예전에는 제출한 뒤에만 알려서, 알림을 보고도 본 세션이 그대로 기다리고 검토하는 일이 있었다(쿠폰 프로젝트 세션). 그래서 질문 시점 알림을 더하고, 제출 뒤 알림은 그 시점에 할 일을 말하게 바꿨다.

### 8. 닫는 줄은 없다, 사유만 남긴다

- **답변 끝에 아무 줄도 붙이지 않는다.** 직접이든 위임이든 `[Agy 위임]` 줄, 예상 토큰 · 시간 줄, 수준 태그를 쓰지 않는다.
- 처리 방식(직접 · 위임) · 모델 · 소요 시간 · 토큰은 대화 기록에서 자동으로 모아 뷰어의 **실측 통계**(`http://127.0.0.1:8787/#/stats`)에 보인다. 측정된 값만 보이고 예상치는 없다.
- 사유 한 줄만 따로 남긴다. 막는 훅은 없고, 안 남기면 통계에 "기록 없음"으로 보인다.
  - **직접 처리:** 그 질문의 **첫 셸 명령 앞에 붙여** 한 번에 실행한다. **따로 부르지 않는다.** 셸 명령을 쓰지 않는 질문은 남기지 않는다.
    `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.samjil/delegate-agy/scripts/note-choice.ps1" -Mode direct -Reason "두 줄 수정이라 브리프가 더 비쌈" ; <원래 명령>`
    (데스크톱 사용률 기록도 함께 남길 때는 `note-choice.ps1 ... ; note-claude-limits.ps1 ... ; <원래 명령>` 처럼 한 명령 앞에 이어 붙인다. `noted` 한 줄만 찍고, 실패해도 종료 코드 0 이라 뒤 명령을 막지 않는다. 사유는 200자까지.)
  - **위임:** 브리프의 `@` 줄에 `@reason: <한 줄>` 을 쓴다. 기록에만 남고 agy 에는 보내지 않는다.

## 코딩 작업을 위임하기 전에 (대화당 한 번)

작업에 소스 파일 수정이 들어가면 첫 위임 전에 아래 둘을 끝낸다.

1. **`@cwd` 확인**: 수정할 프로젝트 폴더를 사용자에게 한 번 확인받는다(`AskUserQuestion` 이 있으면 선택 팝업으로. 규칙은 아래 "프로젝트 폴더 코딩 위임 (`@cwd`)"). 확인받은 폴더는 같은 대화에서 계속 유효하다.
2. **워처 상태 확인**: `ensure-agy-running.ps1 -CheckOnly -StaleThresholdSeconds 0` 으로 상태를 볼 수 있다. `DEAD` 나 `MANUAL_STOP` 이어도 묻지 않고 그대로 `submit-task.ps1` 로 제출한다(`submit-task.ps1` 이 워처를 켜거나 작업자를 직접 실행한다. 아래 "워처가 꺼져 있을 때" 참고).

## 사용자가 agy 에게 직접 시킬 때 (통로는 워처 하나)

사용자가 "agy 에게 1부터 5까지 더한 값을 물어봐 줘" 처럼 **agy 를 지목해서** 시키면, 난이도 판단 없이 그 일을 `submit-task.ps1`(아래 "실행 방법")로 위임한다.
위임 기록·사용량·세션 이어가기·git 안전장치는 모두 워처/작업자 경로를 거칠 때만 남기 때문이다.

- **`ask_antigravity` 같은 antigravity MCP 도구를 쓰지 않는다.** 도구 목록에 보여도, 이 PC 의 agy 호출 통로는 `submit-task.ps1`(워처/작업자)이다. MCP 가 실패했을 때 대신 `agy.exe` / `agy -p` 를 직접 실행하는 우회도 하지 않는다 — 답은 오지만 기록이 남지 않는다(실제 사례: MCP 경로 오류 뒤 `agy -p` 를 직접 돌려 답만 받고 뷰어에는 기록이 없었다).
- 워처가 꺼져 있어도(`DEAD` · `MANUAL_STOP`) 묻지 않고 그대로 `submit-task.ps1` 로 제출한다(`submit-task.ps1` 이 `manual_stop.flag` 를 지우고 워처를 켜며, 켜지지 않으면 작업자로 직접 실행한다). 꺼진 채 MCP 나 직접 `agy -p` 실행으로 대신하지 않는다. 사용자가 그 방식을 명시적으로 원한 경우만 예외다.
- 사용자가 모델·세션을 말하면(`@model`, `@session`) 지시문 머리에 그대로 옮긴다.

## agy 의 능력을 추측해 막지 않는다

위임 브리프에 "agy 는 ~를 못 한다 / ~를 쓰지 마라"를 **확인 없이** 적지 않는다. 틀린 가정이 브리프의 금지 조항이 되면 agy 가 할 수 있는 일까지 막고, 그 금지가 다시 "agy 는 못 한다"는 근거처럼 굳는다.
(실제 사례: 화면을 보며 맞추는 CSS 수정에서 Claude 가 "agy 는 브라우저가 없다"고 가정하고 브리프에 "브라우저를 열지 마라"고 적은 채 직접 처리했다. 사용자가 물어 agy 에게 읽기 전용으로 확인하니
`chrome-devtools-mcp` 도구군(`navigate_page` · `take_screenshot` · `take_snapshot`)이 있었고, `http://127.0.0.1:8000/…` 를 실제로 열어 제목과 화면을 읽고 스크린샷 파일까지 남겼다.)

- agy 가 할 수 있는 도구: 파일 읽기·쓰기·고치기, 명령 실행(`run_command`), 브라우저(`chrome-devtools-mcp`: 페이지 열기·스크린샷·DOM 스냅샷). 웹 검색은 쓰지 않는 것으로 보고 사실 주장은 믿지 않는다(위 3번).
- 할 수 있는지 모르겠으면 **agy 에게 읽기 전용으로 짧게 물어 확인**한다(예: "브라우저로 로컬 페이지를 열어 스크린샷을 남길 수 있는 도구가 있나? 있으면 도구 이름만 답해"). 한 번이면 되고, 확인한 결과는 이 절에 반영한다.
- 금지 조항은 **실제로 위험한 것**(커밋, 범위 밖 파일 수정 등)에만 둔다. 능력을 추측한 금지는 쓰지 않는다.
- 위임 여부를 "agy 에 그 도구가 없을 것 같다"는 짐작으로 정하지 않는다. 짐작이 근거라면 먼저 물어 확인하고, 확인 전에는 위임을 기본으로 한다.

### agy CLI 자체를 모를 때는 agy 에게 묻는다

agy 의 플래그 · 슬래시 명령 · 출력 필드 · 설정 · 파일 위치처럼 **agy CLI 사용법**을 모르면 짐작하거나 사용자에게 묻기 전에 agy 에게 직접 묻는다.

1. 먼저 로컬에서 확인할 수 있는 것을 본다: `agy --help`, `agy help <하위 명령>`, `agy models`. 이것으로 풀리면 묻지 않는다.
2. 그래도 모르면 읽기 전용으로 짧게 묻는다. 결과가 위임 기록에 남도록 위임으로 보낸다(`@model: quick`, `@cwd` 없음, "도구를 쓰지 말고 아는 것만, 모르면 모른다고, 정확한 플래그 · 필드 이름으로" 를 넣는다).
   Gemini 5시간 한도가 소진됐으면 agy 안의 Claude 모델(한도가 따로다)로 바로 물을 수 있다: `agy -p "<질문>" --model claude-sonnet-5-5-low`.
3. 답은 **확인 전에는 사실로 쓰지 않는다.** 플래그나 출력 필드는 실제로 한 번 실행해 보고, 확인된 것만 이 문서나 코드에 반영한다.
   (실제 사례: `/context` 는 대화형 전용이라 `agy -p "/context"` 는 "print mode 에서 쓸 수 없다" 오류가 난다. `--output-format stream-json` 의 init · result 이벤트에도 컨텍스트 창 크기는 없다 — 둘 다 직접 실행해 확인했다.)

## 결과 처리: 필수 검토

**agy 가 돌려준 내용은 어떤 경우에도 검토 없이 사용하거나 사용자에게 전달하지 않는다.** 기준은 "Claude 가 직접 처리했다면 냈을 수준"이다.

- 요구사항과 명세를 모두 충족했는가, 빠뜨리거나 임의로 바꾼 부분은 없는가.
- 코드는 diff 를 직접 읽고 핵심 시험 · 빌드를 다시 돌린다. 보고서의 "통과"를 믿지 않는다. `@cwd` 폴더를 직접 고친 작업은 바뀐 파일 목록과 diff 로 범위 밖의 변경이나 삭제가 없는지 본다.
- agy 는 커밋하지 않는다(워처가 git 상태가 바뀌면 응답 맨 위에 경고를 붙인다). 커밋 여부는 검토 뒤 Claude 가 정한다.
- 사실 주장(수치, 최신 정보, 인용)은 확인하거나 뺀다.
- **미달이면 다시 맡기지 않고 직접 고친다**(위 "다시 맡기지 않는다"). 사소한 오류는 바로 고친다.
- agy 가 작업 중인 저장소에는 Claude 나 서브에이전트가 같은 때에 쓰지 않는다.

## 실패 원인 개선 (세션 시작 알림 → 원인 분석 → 수정 제안 → 처리 표시)

위임이 실패 · 취소되면 원인이 자동으로 분류되어 DB(`task_failures` 표)에 남는다. 워처가 1분마다 분류하고, 세션 시작 훅 · 뷰어 · 진단 명령도 열 때마다 분류한다. 분류는 다음과 같다.

| 분류 | 뜻 | 보통의 조치 |
|---|---|---|
| `quota_exhausted` 한도 소진 | Individual quota reached · 429 | 재설정까지 부계정 · 다른 한도 묶음으로 보내거나 직접 처리. 워처는 소진 뒤 같은 묶음 폴백을 건너뛰고 표시 파일로 바로 실패한다 |
| `server_overloaded` 서버 과부하 | 503 · No capacity | 잠시 뒤 재시도. `@model` 을 모델 이름 하나로 고정하지 말고 단계로 보내 폴백을 허용 |
| `model_error` 모델 오류 · 400 | 모델 미인식 · invalid model selection · HTTP 400 | `agy models` 로 가용 목록 확인, `models.json` · `models.local.json` 단계 모델 확인 |
| `brief_problem` 브리프 문제 | 없는 `@cwd` · 쓸 수 없는 `@model` · `$` 확장된 경로 · `[NEED INFO]` | 브리프는 따옴표 있는 here-doc(`<<'EOF'`)으로 보내고 지시 줄 값을 확인 |
| `stalled` 멈춤 | 진행 없음으로 취소 · 이어 물어도 멈춤 | 작업을 더 작게 나누거나 단계를 올림. 멈춤 판정이 틀렸으면 agy-progress 수정 |
| `timeout` 시간 초과 | 대기 한도 · 2시간 상한을 넘김 | 단계 대기 한도 · 작업 크기 점검 |
| `watcher_problem` 워처 · 작업자 문제 | 작업자가 사라짐 · 시작 후 결과 없이 반복 종료 · 작업자 오류 | `watcher.log` 의 `[작업 ID]` 줄과 `작업자 오류` 줄 확인, 워처 재시작 |
| `account_problem` 계정 · 부계정 문제 | 부계정 오프라인 · 로그인 · 주 계정 폴백 꺼짐 | `switch-sub-agy.ps1` 로 부계정 로그인 확인 |
| `transient_backend` 일시 오류 | 빈 대화 ID · 인증 지연 · 스트림 끊김 | 다시 보내기. 반복되면 agy 로그인 상태 확인 |
| `content_blocked` 안전 필터 | 모델 출력이 안전 필터에 막힘 | 지시문 표현 조정 |
| `unknown` 미분류 | 위에 없음 | 답 전문과 로그를 보고 분류 규칙(`agy-failure-doctor.ps1`) 추가 검토 |

사용자 취소(`user_cancelled`)와 기능 도입 전 3일 넘은 기록은 자동으로 처리 표시된다.

**세션 시작 훅이 "처리 안 한 원인 n건"을 알리면** 다음 순서로 한다.

1. **알린다:** 사용자의 실제 요청과 함께 한 줄로 알린다. 세션을 이 일로 가로채지 않는다. 사용자가 처리를 원할 때만 이어 간다.
2. **원인 분석:** `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$S/diagnose-failures.ps1"`(처리 안 한 원인이 맨 위, `-Json` 은 상세). 뷰어에서는 실측 통계 › 실패 · 취소 진단. 분류별 예시 작업의 답(`data/tasks/outbox/<ID>.response.md`)과 `runtime/logs/watcher.log` 의 `[<ID>]` 줄을 읽고, 분류가 맞는지부터 본다(틀리면 분류 규칙도 고칠 거리다).
3. **수정 제안:** 분류마다 한 줄씩 무엇이 문제였고 무엇을 고칠지(런타임 코드 · 설정 · 브리프 습관), 또는 "외부 요인이라 고칠 것 없음"(한도 재설정 · 503)을 제안한다. 런타임 코드 수정은 보통 위임(명세 + 시험)으로 하고, 설정 · 정책 변경은 사용자에게 먼저 묻는다.
4. **처리 표시:** 분석을 마친 것만 `diagnose-failures.ps1 -Ack -Category <분류> -Note "<한 일>"`(또는 `-TaskId <ID>`, 전부면 `-All`)로 표시한다. 고친 뒤에도 같은 원인이 새로 생기면 다시 알림에 뜬다.

## 사전 조건 및 런타임 자동 확인/설치

- 이 PC 에서 명령을 실행하는 도구(Bash 또는 PowerShell)가 이 세션에 있어야 한다. 없으면 위임 없이 바로 직접 처리.
- **위임 런타임 환경 확인:**
  이 스킬의 실행 스크립트와 런타임은 사용자 홈 디렉터리의 `~/.samjil/delegate-agy/`에 위치합니다.
  작업을 수행하기 전, `~/.samjil/delegate-agy/scripts/sub/watch-agy.ps1` 또는 `start-agy.ps1`이 존재하는지 확인합니다.
  만약 존재하지 않는다면(스킬 규약만 단독 설치된 경우), 에이전트가 임의로 외부 스크립트를 내려받거나 실행하지 않고, 사용자에게 런타임 환경 구성이 필요함을 안내합니다:
  > "Antigravity 위임 워처 런타임(~/.samjil/delegate-agy/)이 감지되지 않았습니다. 저장소의 install.ps1을 실행하여 런타임을 구성해 주세요."
- **위임 런타임 폴더는 `~/.samjil/delegate-agy/runtime` 이다.** `submit-task.ps1`(아래 "실행 방법")이 스스로 찾으므로 따로 탐색하지 않는다.
  스크립트가 없거나 폴더를 못 찾으면(낡은 설치) 설치본을 갱신해 달라고 사용자에게 알리고, 이번 작업은 위임 없이 직접 처리로 폴백한다.

## 워처가 꺼져 있을 때: 묻지 않고 그대로 위임한다

`DEAD` 이든 `MANUAL_STOP`(사용자가 `stop-agy.ps1` 로 끈 상태)이든 **워처가 꺼져 있다는 이유만으로 사용자에게 묻거나 Claude 가 직접 처리하지 않는다. 그대로 `submit-task.ps1` 로 제출한다.**

- **제출 시 자동 기동 · 직접 실행 폴백:** `submit-task.ps1` 은 지시문을 inbox 에 넣은 직후(그리고 `-Poll <ID> -CancelOnTimeout` 으로 대기 중인 작업을 기다릴 때) 워처 상태를 확인한다.
  - `DEAD` 또는 `MANUAL_STOP` 이면 `manual_stop.flag` 를 지우고 워처를 창 없이 켠 뒤 최대 15초 동안 `ALIVE` 를 기다린다(성공 시 표준 오류에 `[워처] 꺼져 있어 켰습니다(PID <n>).`).
  - 그래도 워처가 켜지지 않으면 `submit-task.ps1` 이 해당 작업 하나를 워처의 작업자 모드(`agy-task-worker.ps1` → `watch-agy.ps1 -WorkerTask`)로 직접 실행한다(표준 오류에 `[워처 없음] 워처를 켜지 못해 이 작업을 작업자로 직접 실행합니다(PID <n>).`). 모델 단계 · 폴백 체인 · outbox/DB 기록 · `running\<ID>.json` 표시(`-Poll` · `-Cancel` · 뷰어)는 워처가 실행할 때와 같다.
- `stop-agy.ps1` 은 계속 `manual_stop.flag` 를 남긴다. 뷰어의 주기적 자동 재시작은 `manual_stop.flag` 를 존중하고, 위임(`submit-task.ps1`)만 이를 덮어쓰고 워처를 켠다.

**상태 확인(`ensure-agy-running.ps1 -CheckOnly`):** 하트비트 파일의 나이로는 판단하지 않고 PID 잠금 파일로 판단한다.

```bash
powershell.exe -NoProfile -File "$USERPROFILE\.samjil\delegate-agy\scripts\sub\ensure-agy-running.ps1" -CheckOnly -StaleThresholdSeconds 0
echo "exit=$?"
```

| 출력 | 종료 코드 | 뜻 | 다음 |
|---|---|---|---|
| `ALIVE` | 0 | 워처가 켜져 있다 | 그대로 `submit-task.ps1` 로 제출한다 |
| `DEAD` | 1 | 꺼져 있다 | 그대로 `submit-task.ps1` 로 제출한다(자동 기동 또는 작업자 직접 실행) |
| `MANUAL_STOP` | 2 | `stop-agy.ps1` 로 꺼 둔 상태다 | 그대로 `submit-task.ps1` 로 제출한다(`manual_stop.flag` 삭제 후 자동 기동 또는 작업자 직접 실행) |

**출력이 위 셋 중 하나가 아니면(비어 있거나 오류) 확인에 실패한 것이다 — "켜져 있다"로 읽지 않는다.** 설치본이 낡아 `-CheckOnly` 를 모를 수 있으므로, 저장소에서 `install.ps1` 을 다시 실행해 달라고 사용자에게 알린 뒤 이번 작업은 직접 처리한다.

- **콘솔 창이 뜨는 방식으로 직접 켜지 않는다.** 수동으로 창 없이 켤 때는 `ensure-agy-running.ps1 -ConfirmDelaySeconds 0 -StaleThresholdSeconds 0` 또는 `start-agy.ps1 -Hidden` 을 쓰고, 뷰어는 `ensure-viewer-running.ps1`(끄기: `-Stop`), 워처 끄기는 `stop-agy.ps1` 을 쓴다.

## 지시문과 답변은 한글로 (모든 위임 공통)

웹 뷰어는 위임 지시문(질문)과 agy 답변을 **있는 그대로** 보여 준다. 영어로 쓰면 화면 전체가 영어로 나와 사용자가 읽기 어렵다(사용자 요청).

- **지시문 본문은 한글로 쓴다.** 코드 · 파일 경로 · 명령어 · 식별자 · 에러 메시지 원문은 번역하지 않고 그대로 둔다.
- **지시문 맨 끝에 "최종 답변과 보고서는 한글로 작성한다(코드·경로·명령어·원문 에러는 그대로)" 문장을 넣는다.** 이 문장이 없으면 agy는 지시문이 영어일 때 영어로 답한다.
  단 `@cwd` 로 폴더를 여는 작업은 워처가 같은 뜻의 문장을 자동으로 붙이므로(아래 "표준 규칙 자동 추가") 생략해도 된다. **`@cwd` 가 없는 위임은 이 문장을 직접 넣는다**(번역처럼 결과 언어가 한국어가 아닌 작업만 예외).
- **테스트/스크립트 실행 시 창 깜빡임 방지**: 코딩 위임 지시문에서 테스트나 명령어 실행 시 `powershell.exe -WindowStyle Hidden -Command ...` 등으로 감싸지 말고 도구(`run_command`)의 `CommandLine`에 명령어를 직접 실행하도록 안내한다 (Windows에서 `powershell.exe`를 서브프로세스로 재호출하면 실행 순간 화면에 콘솔 창이 깜빡이는 부작용이 발생함).
- 한 줄 지시문(`Find real defects` 같은 영어 관용 표현)만 영어로 남기지 않는다.

## 프로젝트 폴더 코딩 위임 (`@cwd`)

실제 소스 파일을 agy가 읽고/쓰게 하려면 지시문 맨 위에 `@cwd: <대상 폴더 절대경로>`를 쓴다. (`@cwd`는 agy의 공식 옵션이 아니라 이 브리지의 자체 규칙 — 워처가 이 줄을 파싱해 `--add-dir`로 실행한다.)

**이름 뜻**: `cwd`는 **c**urrent **w**orking **d**irectory(현재 작업 폴더)의 약자다. 이름과 달리 agy 프로세스의 작업 폴더를 바꾸는 게 아니라(agy는 워처의 런타임 폴더에서 실행된다) 읽고 쓸 수 있게 **접근을 허용할 프로젝트 폴더**를 알려 주는 줄이다. 같은 일을 agy는 `--add-dir`이라고 부른다 — 이름은 `@cwd`로 유지하기로 했다(사용자 결정).

**폴더가 여러 개일 때 (`@cwd`를 여러 줄)**: 한 작업에 폴더가 둘 이상 필요하면(저장소 + 문서 폴더 등) `@cwd:` 줄을 폴더마다 하나씩 쓴다. 워처가 폴더마다 `--add-dir`를 한 번씩 넘긴다.

```
@cwd: C:\path\to\project
@cwd: C:\path\to\docs
@model: build
<지시문>
```

- 줄 순서는 그대로 유지되고, 같은 경로를 또 쓰면(대소문자·끝의 `\` 무시) 한 번만 쓴다. `@cwd`/`@session`/`@model` 줄은 순서 상관없이 맨 위에 모아 쓴다(본문이 시작된 뒤의 줄은 지시어가 아니다).
- **없는 폴더가 하나라도 있으면 agy를 부르지 않고 실패한다.** 오류에 없는 폴더가 모두 적힌다.
- 한 줄만 써도 예전과 똑같이 동작한다. 뷰어는 폴더 목록을 모두 보여 주고, 상대 경로 이미지는 첫 번째 폴더 기준으로 찾는다.
- 여러 폴더에는 폴더마다 위험이 따르므로(아래 "첫 확인 시에만 위험 고지") 각 폴더가 모두 되돌릴 수 있는 상태인지 확인한다.

**폴더 확인 규칙**
- 폴더를 **추측하거나 임의로 고르지 않는다.** 이 대화에서 사용자가 명시했거나 확인해준 폴더만 쓴다. 없거나 모호하면 먼저 묻는다. **이 규칙은 `@cwd` 줄(폴더)마다 적용된다** — 여러 줄을 쓸 때도 줄마다 사용자가 확인한 폴더여야 하고, 하나라도 확인되지 않은 폴더가 있으면 그 폴더만 묻는다.
- 한 번 확인된 폴더는 **같은 대화 안에서는 계속 유효**하다(폴더 하나하나가 따로 유효하다). 새 대화가 시작되면 다시 확인받는다.
- **첫 확인 시에만 위험 고지**: 워처는 `--dangerously-skip-permissions`로 동작해서 agy가 승인 없이 그 폴더의 파일을 읽고/쓰고/삭제하고 임의 명령을 실행할 수 있다. git 등으로 되돌릴 수 있는 상태인지 한 줄로 확인한다.
- 확인 후에는 그 폴더에 대한 적합한 코딩 하위작업을 **매번 묻지 않고 자동 위임**한다.

## 코딩 위임 운영 규칙 (커밋 · 크기 · 끝남 확인 · 보고)

실제 프로젝트에서 여러 번 위임해 보고 정한 규칙이다(여러 프로젝트에서 실제로 쓰며 얻은 사례). 코드 결과물은 명세가 완전하면
쓸 만하지만, 작업 운영(끝났는지, 무엇을 했는지)은 믿기 어렵다. 그래서 아래를 지킨다.

1. **agy 는 커밋하지 않는다.** `@cwd` 작업에는 워처가 "DO NOT COMMIT — git add · commit · stash · reset 등 git 상태를 바꾸는 명령을 쓰지 말고, 바꾼 내용은 작업 트리에 그대로 둔다"를
   프롬프트에 **자동으로 붙인다**(아래 "표준 규칙 자동 추가"). 지시문에 직접 쓸 필요는 없지만, 브리프(명세 문서)에 커밋 단계가 있으면 그 단계를 지시문에서 빼 둔다.
   - **워처가 감지해 알려 준다.** `@cwd` 폴더가 git 저장소면 워처가 agy 를 부르기 전후의 HEAD · 브랜치 · stash 개수를 비교해, 바뀌었으면 **응답 맨 위에**
     `> [경고: agy 가 git 상태를 바꾼 것으로 보입니다 — 저장소 …]` 배너와 복구 명령을 붙인다. **자동으로 되돌리지는 않는다**(그 사이 사용자나 Claude 의 정당한 커밋,
     같은 폴더의 다른 위임 작업이 있었을 수 있어서). 배너가 보이면 `git log` · `git diff` 로 확인한 뒤 배너의 명령 중 필요한 것만 Claude 가 직접 실행한다.
     (배너에 "다른 위임 작업이 N 개" 가 있으면 그 변화는 다른 작업의 것일 수 있다.)
   - 작업 트리에 커밋 안 한 변경이 있었으면 워처가 그 상태를 `refs/samjil/snapshots/<작업 ID>` 에 스냅샷으로 보관한다(최근 20개, 작업 트리는 건드리지 않음). agy 가 변경을 날렸을 때
     `git diff <스냅샷>` 으로 비교하고 `git stash apply <스냅샷>` 으로 되살린다. untracked 파일은 담기지 않는다. 끄려면 환경변수 `AGY_GIT_GUARD=off`(워처 재시작).
   - agy 가 이미 커밋했으면 `git reset --mixed <커밋 전>` 으로 풀어(변경은 작업 트리에 남는다) 검토한다.
   - **Claude 가 diff 를 직접 읽어 리뷰**하고, 테스트 · 빌드를 직접 다시 돌린 뒤 **커밋할지 말지 Claude 가 정해 직접 커밋**한다.
     서브에이전트 리뷰로 갈음하지 않는다(사용자 지시). 사소한 보완은 이때 Claude 가 바로 고친다.
2. **단계의 대기 한도 안에 끝날 크기로 나눈다.** build 는 8분, build-hard 는 12분, feature · think · deep 은 20분이다. 큰 작업은 늦고 검토도 어렵다.
   점검 · 분석처럼 넓은 일은 **결과 파일을 먼저 만들고 확인한 것을 그때그때 덧붙이게** 해서 중단돼도 부분 결과가 남게 한다.
3. **명령은 전경에서 끝까지 기다리게 한다.** "모든 명령을 FOREGROUND 로 실행하고 끝날 때까지 기다린다. 백그라운드
   작업 · 터미널을 남기지 않는다"도 `@cwd` 작업에는 워처가 자동으로 붙인다. 그래도 agy 가 긴 명령(npm install · gradle · 빌드)을 스스로 백그라운드로 돌릴 수 있다.
4. **"오류"로 보고돼도 agy 가 아직 돌고 있을 수 있다.** 응답에 `root agent idle; waiting ... for background task(s)` 같은 문구가
   오면 워처는 오류로 기록하지만 agy 는 계속 일해 나중에 파일을 바꾸거나 커밋까지 한다. 그 저장소를 만지기 전에 확인한다:
   - `logs/watcher.log` 에 그 작업의 `완료` 줄이 있는지, `logs/current_task.json` 이 다른 작업으로 넘어갔는지
   - 대상 저장소의 `git status` · `git log` 가 더 바뀌지 않는지(잠시 두고 두 번 본다)
   - 끝난 게 확인되면 그때 결과를 검토한다. 아직이면 같은 작업을 다시 보내지 않는다.
5. **같은 저장소에 동시에 쓰지 않는다.** agy 가 작업 중인 저장소(작업 트리 · git 인덱스)에 Claude 나 서브에이전트가 같은 때에
   파일을 고치거나 git 명령을 쓰지 않는다. 동시에 해야 하면 다른 저장소나 `git worktree` 로 나눈다.
6. **보고는 증거와 함께 받는다.** 지시문에 보고서 파일 경로를 주고, 실행한 명령과 원래 출력(시험 개수 · 실패 수 · 빌드 결과)을
   붙이게 한다. agy 의 자기 보고("통과", "concerns 없음")는 낙관적인 경우가 많고 증거 파일이 다음 실행에 덮어써질 수도 있으니,
   핵심 명령(시험 · 린트 · 빌드)은 Claude 가 다시 돌려 확인한다.
7. **대기열은 다른 세션과 같이 쓴다.** 앞 작업이 있으면 그만큼 늦어지고, 단계의 대기 한도 안에 안 끝나면 취소하고 직접 한다. 서로 다른 파일이면 병렬로(최대 5개) 보내 대기를 줄인다.
   서로 다른 파일이면 병렬로(최대 5개) 보내 대기를 줄인다.

### 표준 규칙 자동 추가 (`@cwd` 작업, `@raw` 로 끔)

`@cwd` 로 폴더를 여는 작업에는 워처가 agy 를 부르기 직전에 아래 규칙을 프롬프트 **맨 끝에 자동으로 붙인다**(`agy-rules.ps1`). 그래서 Claude 는 **작업 명세만 짧게** 쓰면 된다 —
예전처럼 영문 `Rules:` 문단을 매번 적지 않는다.

```
Rules (added automatically by the watcher):
- DO NOT COMMIT. Do not run git add / commit / stash / reset / checkout / switch or any command that changes git state. Leave all changes in the working tree.
- Run every command in the FOREGROUND and wait for it to finish. Do not leave background tasks or terminals running. Run commands directly; do not wrap them in another powershell.exe call.
- Touch only the files this task needs. Do not touch untracked files you did not create.
Write the final reply and any report in Korean (keep code, paths, commands and raw error text as is).
```

- **규칙마다 따로 본다.** 지시문에 이미 같은 뜻의 규칙(예: `DO NOT COMMIT`, `한글로 작성`)이 있으면 그 규칙만 건너뛰고 빠진 것만 붙인다. 로그(`watcher.log`)에 `표준 규칙 자동 추가:` 로 붙인 규칙이 남는다.
- **`@cwd` 가 없는 위임에는 아무것도 붙이지 않는다.** 번역 · 데이터 변환처럼 결과 언어와 형식이 지시문마다 다르기 때문이다. 이런 위임은 Claude 가 위 "지시문과 답변은 한글로"의 문장을 직접 넣는다.
- **`@raw: true`** 를 지시문 맨 위(다른 `@` 줄과 같이)에 쓰면 자동으로 붙이지 않는다. 번역처럼 표준 규칙이 어울리지 않는 작업에만 쓴다(핸드오프 펌프 지시문도 이제 표준 규칙을 붙인다).
- 붙인 규칙은 agy 에게 넘기는 프롬프트에만 들어가고, 뷰어와 위임 기록의 질문에는 Claude 가 쓴 원본이 그대로 남는다.
- **Claude 가 지시문에 계속 직접 적어야 하는 것**: 보고서 파일 경로와 보고 내용("무엇을 바꿨는지 · 실행한 명령과 원래 출력 · 걱정되는 점을 `<보고서 경로>` 에 적고, 최종 답변은 상태 · 바뀐 파일 · 시험 한 줄 요약 · 걱정되는 점만 짧게").

## 여러 작업을 이어서 위임 (`@session`)

agy는 기본적으로 매번 빈 상태로 시작한다(그래서 맥락이 많이 필요한 일은 위임하지 않는다). 하지만 **같은 큰 작업을 여러 단계로 나눠서 계속 위임**해야 할 때는 지시문
맨 위에 `@session: <이름>`을 추가하면 agy 쪽 대화가 이어진다 — 이전에 agy가 읽은
파일, 내린 판단, 만든 결정을 다시 설명 안 해도 된다.

```
@session: 결제모듈-리팩토링
@cwd: C:\project
이어서 다음 파일도 같은 방식으로 고쳐줘.
```

- **언제 쓰나**: 하나의 목표를 여러 번의 위임으로 쪼개서 진행할 때(예: "1단계: 구조
  분석해줘" → "2단계: 방금 분석한 대로 A 파일 고쳐줘" → "3단계: 이어서 B 파일도").
  각 위임이 서로 완전히 독립적이면(위 "위임 대상" 예시 대부분처럼) `@session` 없이
  매번 새로 시작하는 게 더 낫다 — 불필요하게 이전 대화를 끌고 가면 토큰만 늘어난다.
- **이름 짓기**: 그 작업을 나타내는 짧고 구체적인 이름(`결제모듈-리팩토링`처럼)을
  **같은 대화 안에서 일관되게** 쓴다. `@cwd` 폴더 확인 규칙과 마찬가지로 이름을
  임의로 짓지 말고, 새 작업 묶음을 시작할 때는 사용자에게 확인하거나 명확한 새 이름을
  쓴다.
- **`@cwd`는 세션에 고정(sticky)된다.** 폴더 목록(여러 줄이면 전부) 전체가 세션에 저장된다. 이번 호출에 `@cwd`가 **하나라도** 있으면 이번 목록만 쓰고(세션의 폴더와 **합치지 않는다**, 새 목록이 세션에 저장된다), **하나도 없으면** 세션에 저장된 목록을 그대로 쓴다. 폴더를 하나 더 열려면 기존 폴더까지 모두 다시 쓴다. 첫 호출에서만 주면 이후 같은 세션 호출에서
  생략해도 자동으로 이어서 적용된다.
- 세션이 오래돼서 agy 쪽에서 만료됐더라도 걱정할 필요 없다 — 워처가 자동으로 새
  세션을 시작하고 계속 진행한다(사용자에게 보이는 동작 차이 없음).

## 실행 방법

위임은 **`submit-task.ps1` 한 번 호출**이다. 런타임 폴더 찾기 · 작업 ID 만들기 · inbox 기록 · 결과 기다리기를 스크립트가 모두 한다 — 긴 bash 나 폴링 루프를 직접 쓰지 않는다.
지시문은 **따옴표 붙은 heredoc**(`<<'CLAUDE_TASK_EOF'`)으로 표준입력에 준다(`$` · backtick 이 셸에서 해석되지 않게).

지시문은 **아래 4단 브리프**로 쓴다. agy 는 매번 빈 상태로 시작하고 호출마다 고정 비용이 있어서, 브리프가 자기완결적이어야 첫 번에 맞아 직접 고칠 일이 줄어든다.
Claude 를 어떤 모델·Effort 로 돌리든 같은 수준의 명세가 나오게 하려는 틀이니, 항목을 빼먹지 않는다(해당 없는 항목은 "없음"으로 적는다).

```bash
powershell.exe -NoProfile -File "$USERPROFILE\.samjil\delegate-agy\scripts\submit-task.ps1" <<'CLAUDE_TASK_EOF'
@cwd: C:\path\to\project
@model: build
# @cmd: goal | swarm | run-workflow | boost | browser | plan   (선택)
# @mode: plan | accept-edits | auto                            (선택)
[1. 목표 및 작업 모드]
- 작업 목적: <1~2줄 요약 (읽기 전용 분석인지 파일 수정인지 명시)>

[2. 대상 파일 및 상세 명세]
- 대상 경로: <파일 전체를 붙여넣지 말고, 실제 존재를 확인한 파일 경로:줄번호 또는 git diff 범위만 지정>
- 구현/수정 내용: <모호한 표현 없이 구체적인 값, 함수명, AS-IS -> TO-BE 규칙 명시>

[3. 프로젝트 규칙 및 범위 제한 (Non-Goals)]
- 핵심 규칙: <CLAUDE.md / BRIEF.md 중 이 작업에 해당하는 규칙 2~3줄 요약>
- 접근 금지: <현재 Claude가 편집 중인 파일이나 이번 변경과 무관한 레거시 코드는 절대 수정·지적하지 말 것>
- 모호함: 이 명세로 정할 수 없는 것이 있으면 임의로 정하지 말고, 최종 답변 첫 줄에 [확인 필요] 와 질문을 적고 그 부분은 건드리지 말 것.

[4. 검증 및 답변 형식 (DIGEST)]
- 검증 명령: <실행할 테스트/타입체크/빌드 명령어>
  - 백신이 PowerShell 연쇄 실행을 오탐해 종료시키는 환경에서는 검증에 빠른 시험만 쓰게 하고 e2e·긴 시험은 위임 안에서 돌리지 않게 한다. 전체 시험은 위임이 끝난 뒤 Claude 가 한 번만 돌린다.
- 보고 형식: 상세 실행 로그가 길면 `<보고서 경로>`에 따로 적고, 최종 답변 본문에는 [상태 · 변경 파일:줄 · 테스트/검증 실측 1줄 요약 · 우려 사항]만 간결하게 작성할 것.
CLAUDE_TASK_EOF
```

- **보내기 직전 자동 점검**: `submit-task.ps1` 이 지시문을 훑어 검증 방법·범위 제한·대상 파일이 빠졌거나, 너무 짧거나 길거나, 파일 본문을 붙였거나, "브라우저를 열지 마라" 같은 능력 추측 금지가 있으면 표준 오류에 `[브리프 점검] …` 경고를 낸다. **경고일 뿐 위임은 그대로 진행**하니, 경고가 나오면 다음 위임부터 반영한다(재위임이 더 비싸다). `AGY_BRIEF_LINT=off` 로 끈다.
- **폴더 접근이 필요 없는 작업**(번역·글쓰기 등)은 `@cwd:` 줄을 빼고 1·2단만 짧게 써도 된다. 3·4단의 파일 범위·검증 항목은 폴더를 여는 작업에서 특히 중요하다.
- 브리프에 **agy 의 능력을 추측한 금지**(예: "브라우저를 열지 마라")를 쓰지 않는다. 금지 조항은 실제로 위험한 것(범위 밖 수정, git 상태 변경)에만 둔다.

폴더 접근이 필요 없는 작업이면 `@cwd:` 줄만 빼면 된다. 출력과 종료 코드:

| 출력 | 종료 코드 | 뜻 | 다음 |
|---|---|---|---|
| `===RESULT=== <ID>` + 본문 | 0 | 응답 파일이 생겼다(**실패 사유도 응답 본문으로 올 수 있으니 본문을 읽는다**) | 아래 "결과 처리"로 검토 |
| `===ERROR=== <ID>` + 본문 | 1 | 응답 없이 오류 로그만 있다 | 오류를 읽고 판단 |
| `===PENDING=== <ID> 진행 중 · 경과 N분 · 모델 … · 마지막 단계 …` | 2 | 170초 안에 안 끝났다. **작업은 계속 돌고 있다** | **다시 제출하지 말고** `-Poll <ID>` 로 기다린다 |
| `===CANCELLED=== <ID>` + 사유 | 4(`-CancelOnTimeout` 로 취소했을 때) | 기다리는 한도가 지나 취소했거나 `-Cancel` 로 취소했다. 기록 상태는 `CANCELLED` | 직접 처리 |
| (안내 문장) | 3 | 런타임 폴더를 못 찾음 · 지시문이 비었음 등 | 설치본 갱신을 요청하거나 직접 처리 |

- `device_bash` 한 호출은 최대 3분이라 `-Poll` 은 기본 170초만 기다리고 진행 상태를 돌려준다. **위임은 `-NoWait` 로 제출하고 같은 메시지에서 백그라운드로 한 번만 기다린다**: `-Poll <ID> -CancelOnTimeout`(단계의 대기 한도까지).
  대기 간격은 스크립트 안에서 돌아 Claude 토큰을 쓰지 않는다. 대기 한도가 지나도 작업이 진행 중이면 대기를 연장하며, 5분 동안 진행이 없거나 2시간 절대 한도가 지나면 취소하고 `===CANCELLED===`(종료 코드 4)를 돌려주니 직접 처리한다. 반복해서 확인하지 않는다.
- `===PENDING===` 줄은 `-MaxWaitSec` 만 주고 `-CancelOnTimeout` 을 안 줬을 때 볼 수 있다. 경과 시간 · 마지막 단계(`#14 PLANNER_RESPONSE DONE 도구: view_file`)가 계속 같으면 멈춘 것일 수 있다(워처가 5분 동안 새 단계가 없으면 스스로 중단한다).
  `대기열에서 기다리는 중`이면 앞선 작업을 기다리는 것이고, `워처 하트비트가 없습니다`가 같이 나오면 워처를 확인한다(아래 "워처가 꺼져 있을 때"). `접수 기록 없음`은 작업 ID 가 틀렸다는 뜻이다.
- **취소**: `submit-task.ps1 -Cancel <ID>`. 대기 중이면 inbox 의 지시 파일을 processed 로 치우고, 실행 중이면 작업자 프로세스 트리(agy 포함)를 끝낸다. 출력은 `===CANCELLED=== <ID>`(이미 끝난 작업은 `===DONE===`, 없는 작업은 `===NOTFOUND===`).

```bash
powershell.exe -NoProfile -File "$USERPROFILE\.samjil\delegate-agy\scripts\submit-task.ps1" -Poll claude_1790000000_123
```

**여러 개를 한 번에 위임**할 수도 있다(서로 독립적인 작업일 때). 먼저 `-NoWait` 로 각각 넣어 ID 만 받고(`submitted: <ID>`), 한 번에 `-Poll` 로 기다린다(쉼표나 공백으로 여러 ID).
워처가 **동시에 최대 5개**까지 돌리므로(같은 `@session`+겹치는 `@cwd`인 것만 차례로) 서로 다른 세션·폴더의 작업은 대기시간이 합산되지 않는다. 그래도 한 배치에 2~5개까지만 묶는다.
(같은 `@session` 이름을 서로 다른 폴더에서 동시에 쓰면 agy 대화는 하나라서 서로 섞일 수 있으니, 폴더가 다르면 세션 이름도 다르게 짓는 것이 안전하다.)

```bash
S="powershell.exe -NoProfile -File $USERPROFILE\.samjil\delegate-agy\scripts\submit-task.ps1"
$S -NoWait <<'EOF_A'
<작업 1>
EOF_A
$S -NoWait <<'EOF_B'
<작업 2>
EOF_B
# 위 두 호출이 출력한 submitted: <ID> 두 개로
$S -Poll <ID1>,<ID2>
```

**기다리는 한도 처리:** 단계의 대기 한도가 지나도 작업이 계속 진행 중이면 자동으로 대기를 연장하며, 5분 동안 진행이 없거나 2시간 절대 한도가 지나면 취소하고 직접 한다(같은 단계로 다시 제출하지 않는다).

## 모델 선택 (`@model:`)

지시파일 맨 위에 `@model: <단계>` 를 쓴다(`@cwd:`, `@session:`과 같은 지시어 줄이며 순서는 상관없다). **단계 이름을 권장한다.**

```
@model: build
@cwd: C:\project
<지시문>
```

| 단계 | 주 모델 → 폴백(한도 · 과부하, 또는 `-xhigh` effort 400 오류) | 대기 한도 |
|---|---|---|
| `quick` | hydrogen-low → hydrogen-medium → neon-low | 3분 |
| `build` | hydrogen-medium → hydrogen-high → neon-low | 8분 |
| `build-hard` | neon-medium → neon-high → hydrogen-xhigh → carbon-medium | 12분 |
| `feature` | orchestrator-neon → neon-high → orchestrator-carbon → hydrogen-high | 20분 |
| `feature-carbon` | orchestrator-carbon → carbon-high → orchestrator-neon → neon-high | 20분 |
| `think` | neon-high → neon-medium → carbon-high → hydrogen-high | 20분 |
| `think-carbon` | carbon-high → carbon-medium → neon-high → neon-xhigh | 20분 |
| `deep` | neon-xhigh(Extra) → neon-high → carbon-high → hydrogen-xhigh | 20분 |

- 필요 시 `@cmd: goal | swarm | run-workflow | boost | browser | plan` 과 `@mode: plan | accept-edits | auto` 를 지시어 줄에 함께 적을 수 있다(2-2절 및 `references/brief-and-commands.md` 참고).

- 정식 모델 이름: `gemini-4-hydrogen-low|medium|high|xhigh`, `gemini-4-neon-low|medium|high|xhigh`, `gemini-4-carbon-low|medium|high`, `gemini-pro-orchestrator-neon`, `gemini-pro-orchestrator`(Orchestrator Carbon).
- **모델 이름으로 지정하면** 그 모델 **하나**만 쓰고 폴백하지 않는다. 막히면 실패로 돌려준다(`... [@model 로 지정한 모델이라 다른 모델로 자동 전환하지 않았습니다]`). 다른 모델로 몰래 다시 보내지 말고 단계 이름으로 보내거나 직접 처리한다.
- 옛 별칭도 받는다: `low` = `quick`, `medium` = `build`, `high` = `build-hard`, `think-argon` = `think-carbon`, `feature-argon` = `feature-carbon`.
- **자동 선택은 `quick` · `build` 만 고른다.** `@model:` 을 생략하면 워처가 요청 내용으로 고른다(`agy-autotier.ps1`, 규칙 기반이라 틀릴 수 있다).
  판정 이유는 `watcher.log` 의 `모델 자동 선택:` 줄에 남는다. 자동 선택을 하지 않는 경우: `@model:` 로 직접 골랐을 때, `@session` 으로 대화를 이어갈 때(대화는 시작할 때의 모델을 유지한다), `AGY_AUTO_MODEL=off` 일 때(이때는 `build`).
- 단계 · 모델 · 대기 한도는 설정 파일 `~/.samjil/delegate-agy/config/models.json`(저장소 `runtime/delegate-agy/config/models.json`)에 있다. 동기화 · 설치가 항상 덮어쓰므로 이 PC 에서만 바꿀 값은 같은 폴더의 `models.local.json` 에 그 단계 · 그 항목만 쓴다(예: `{ "tiers": { "build": { "wait_sec": 600 } } }`). 워처는 작업마다 설정을 다시 읽는다.
- 워처는 켜질 때 `agy models` 를 한 번(20초 제한) 불러 설정의 모델이 실제로 있는지 본다. 없는 모델은 `watcher.log` 에 경고하고 그 단계의 다음 모델로 대신한다. 확인에 실패해도 워처는 뜬다.
- Gemini 계열만 허용한다(`agy models`에는 claude·gpt-oss도 보이지만 이 스킬의 목적이 Claude quota 절약이라 쓰지 않는다).
- **사용자가 모델을 말하면 그대로 따른다**(예: "Extra 로 해 줘" → `@model: deep`).
- **이어가는 세션(`@session`)은 시작할 때의 모델을 유지한다.** 이어가는 호출에서 다른 모델을 쓰면 워처가 오류로 돌려준다(단계를 적었으면 그 단계의 순서 안의 모델은 같은 것으로 본다). 원래 대화(`conversation_id`)를 지키려는 것이다.
  모델을 바꿔 새 대화로 옮기려면 `@upgrade: true`(이전 질문·답 2쌍을 글로 붙인다).
- `지정한 @model 을 쓸 수 없습니다` 오류는 값이 단계 이름도 허용 모델도 아니라는 뜻이다(워처는 agy를 부르지 않는다). 오류에 적힌 목록으로 고쳐 다시 보낸다.
- **성능 · 한도 특성**: Carbon(`high` AA 60, ~56 tok/s, 첫 토큰 ~73초, 기준 100%, $4/$20), Neon(`high` 60 / `xhigh` 61, AA Coding Agent 1위 58.64, ~101–110 tok/s, 첫 토큰 ~41초, 한도 ~30–32% 절감, $3/$15), Hydrogen(`high` 51 / `xhigh` 54, ~165–170 tok/s, 첫 토큰 ~20초, 한도 50%+ 절감, $1.50/$7.50). `Orchestrator (Carbon)` 은 단독 Carbon 대비 한도 ~24% 절감 · 완료 속도 ~19% 빠르다.
- **멈춤 확인 · 이어서 묻기 (`AGY_STALL_SECONDS` / `AGY_STALL_GRACE_SECONDS`):** 새 단계가 `AGY_STALL_SECONDS`(기본 300초) 동안 없어도 바로 끊지 않고 `확인 중(checking)`으로 전환해 `cli-*.log`의 진행 중인 모델 요청(`생각 중`)과 도구 자식 프로세스(MCP node 서버 제외)의 최근 60초 CPU 활동(`명령 실행 중`)을 60초마다 확인한다(생각 중은 `AGY_THINK_MAX_SECONDS` 기본 1200초=20분, 명령 실행 중은 `AGY_TOOL_MAX_SECONDS` 기본 1800초=30분 상한까지 계속 대기하며 전체 작업은 2시간 절대 상한을 따름). 활성 신호 없이 유예 시간 `AGY_STALL_GRACE_SECONDS`(기본 300초)가 더 지나면 실행을 중단한 뒤 같은 대화(`agy --conversation <대화 ID>`)에 진행 상황을 이어서 묻는다(작업당 최대 2회). 이어서 받은 답변이 정상이면 최종 답변으로 채택되고, 첫 줄이 `[진행 불가]`이면 실패로 기록하되 답변을 보존하며, 2회 질문 뒤에도 유예 시간을 넘기면 기존과 같이 멈춤 실패로 끝낸다. `submit-task.ps1 -Poll -CancelOnTimeout` 도 실행 표시의 `probe_state`가 `checking` · `thinking` · `tool running` · `asked`인 동안은 진행 중으로 보아 취소하지 않는다(2시간 절대 한도는 유지).
- **"멈춤 판정" 오류가 나도 결과가 남아 있을 수 있다.** agy 가 최종 응답을 대화 기록에 남겼는데 프로세스만 끝나지 않으면, 워처는 끊기 직전에
  그 응답을 **자동으로 회수해 성공(OK)으로 기록한다**(`data/tasks/outbox/<id>.error.log` 에 회수했다는 안내가 남는다). 그래도 "멈춤 판정" 오류로 끝났다면
  최종 응답이 없던 것이니, 직접 처리로 넘기기 전에 `logs/watcher.log` 의 마지막 단계 줄과 `~/.gemini/antigravity-cli/brain/<대화 ID>/.system_generated/logs/transcript_full.jsonl`
  에 쓸 만한 결과가 남았는지 본다.

## agy 모델과 로그

`watch-agy.ps1`이 `--model`을 직접 지정해 호출한다. 단계면 설정의 순서대로(한도 · 과부하 오류일 때만 다음 모델), 모델 이름이면 그 모델 하나만 쓴다. 결과는 `~/.samjil/delegate-agy/data/delegate.db`(SQLite, 작업별 사용량·질문·답·과정)에 자동 기록된다(모델 칸에는 실제로 쓴 모델, 시도한 모델 칸에는 시도한 순서가 들어간다). CSV 가 필요하면 `tools\export-usage-csv.ps1` 로 만든다. 이 위임 기록은 통합 대시보드(`~/.samjil/viewer/serve-viewer.ps1` / http://127.0.0.1:8787)에서 브라우저 탭으로 실시간 확인할 수 있다.

## 멀티 계정 부계정 풀 (`sub_accounts`, 선택 사항)

- `models.local.json` 에 `sub_accounts.enabled = true` 를 넣지 않으면(또는 `false` 이면) **기존 단일 계정 동작과 100% 동일**하게 본계정 하나만 사용한다.
- **초기 구성 (관리자 PowerShell 최초 1회):** `setup-sub-accounts.ps1 -Slots sub1,sub2` 로 로컬 Windows 부계정(`agy-sub1`, `agy-sub2`), 비비밀 `settings.json`(`mcp_config.json` 은 복사하지 않음), 스킬 읽기 전용 정션(`.agents\skills` · `.gemini\config\rules`), `C:\ProgramData\samjil\sub-bridge` 브리지 및 `C:\ProgramData\samjil\delegate-agy` 공용 스크립트, `LogonType=Password` 스케줄 작업(`samjil-agy-sub-*` -> `sub-supervisor.ps1`)을 구성한다. 구성 뒤 각 슬롯에서 `switch-sub-agy.ps1 -Slot <slot>` 으로 최초 `agy` Google 로그인을 마친다.
- **자동 라우팅 및 폴백:**
  - `model_pattern` (기본 `^gemini-4-hydrogen-`) 과 일치하는 작업(예: `quick` / `build` / `gemini-4-hydrogen-*`)만 부계정 슬롯(`running` 가장 적고 쿨다운이 없는 슬롯)으로 전달한다. `@cmd: browser` 및 MCP가 필요한 작업(`primary_only_cmds`)은 항상 본계정이 맡는다.
  - 한도 초과(`quota_exceeded`) 또는 ACK 타임아웃이 나면 해당 슬롯을 `cooldown_sec`(기본 60초, `models.local.json` 으로 조정 가능) 동안 쿨다운하고 **남은 건강한 부계정 -> 모두 소진되면 본계정** 순으로 자동 폴백한다. 폴백이 일어나면 결과 stderr 에 `[계정 폴백 경고]` 를 출력한다.
- **한도 · 뷰어 격리:** 부계정 작업의 사후 `/usage` 는 `sub_quota` 와 `usage-history.jsonl` (`src = "agy-sub:<slot>"`) 에 별도로 쌓이며 본계정 Gemini 한도 추정과 `limits_at.gemini` 를 오염시키지 않는다.
- **수명주기 및 계정 전환:**
  - `stop-agy.ps1` / `start-agy.ps1` 는 각 슬롯의 `pause.flag` 를 세우고 지워 관리자 권한 없이도 `sub-supervisor.ps1` 이 부계정 워처를 일시 정지·재개한다.
  - `sync-installed.ps1` 은 `sub_accounts.enabled = true` 일 때만 공용 스크립트 폴더(`shared_delegate_dir`)도 함께 동기화하고 `-RestartWatcher` 시 `restart.signal` 을 기록한다.
  - 한도가 소진된 부계정을 다른 Google 계정으로 바꿀 때는 `switch-sub-agy.ps1 [-Slot sub1]` 로 다시 로그인한 뒤 확인 Enter 를 누른다(완료 시 `refresh.signal` 생성 및 쿨다운 즉시 해제).

## 구현 상세 (시행착오 기록 - 재발견 방지용)

- 지시문은 반드시 `<<'CLAUDE_TASK_EOF'` 처럼 **따옴표 붙은 heredoc**으로 써서 `$`, backtick이 셸에서 해석되지 않게 한다.
- agy 응답 JSON 스키마(2026-09 확인): `{conversation_id, status, response, duration_seconds, num_turns, usage:{input_tokens, output_tokens, thinking_tokens, cache_read_tokens, total_tokens}}`. model/cost 필드는 없어서 워처가 `--model`을 직접 지정하는 방식으로 모델명을 기록한다.
- `--cwd` 플래그는 agy.exe에 존재하지 않는다. 대상 폴더는 `--add-dir`로 추가한다(워처가 처리).
- `-p`는 값을 직접 받아야 한다(stdin 단독 사용 불가). 프롬프트의 큰따옴표는 워처가 호출 직전에 `\"`로 자동 이스케이프한다.
- 응답 파일 맨 앞에 UTF-8 BOM(`\ufeff`)이 붙어 있을 수 있으니 그대로 사용자에게 옮기기 전에 신경 쓴다.

## 독립 실행 및 다른 브리지와의 구분

이 스킬은 Antigravity CLI(agy) 전용 위임 스킬이며, 외부 브리지 도구 없이 스킬 내의 `scripts/start-agy.ps1`을 실행하여 독립적으로 워처를 가동할 수 있다. 목적이 quota 분산이므로 Claude Code CLI로 위임하는 것은 의미가 없다.
