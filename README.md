# Agy Agent

[![skills.sh](https://img.shields.io/badge/skills.sh-compatible-blue)](https://skills.sh)

Claude Code 와 Antigravity(agy) 를 함께 쓰기 위한 스킬 모음과 부속 도구입니다. Claude 는 설계와 가장 어려운 일을, 나머지는 agy 가 맡아 Claude 사용량을 아끼고, 두 에이전트가 파일로 대화하며, 그 기록을 로컬 웹 대시보드에서 봅니다.
[skills.sh](https://skills.sh) 에이전트 스킬 규약(Agent Skills Specification)을 따릅니다. **Windows(PowerShell 5.1) 전용**입니다.

## Quick start (English)

Hand routine coding work from Claude Code to the Antigravity CLI (`agy`) and save Claude quota. Claude designs and reviews; agy does the rest. **Windows 10/11 only** (Windows PowerShell 5.1, included in Windows).

1. Install the Antigravity CLI and sign in once: open a terminal and run `agy`.
2. Unzip this pack (or clone the repo) and **double-click `Install.cmd`**. It copies the skills to `~/.claude/skills`, the tools to `~/.samjil`, checks `agy`, and starts the background watcher.
3. In Claude Code say: `ask agy to say hello`.

- Delegation happens when you ask. For delegation in every session run `Install.cmd -AlwaysOn`.
- agy answers in the language of your Windows region setting (Settings > Time & language > Region, "Regional format"; `auto`). To fix a language instead, write its English name (for example `English`) into `~/.samjil/delegate-agy/reply-language.txt`, or install with `-ReplyLanguage English`.
- Remove with `Uninstall.cmd`. It removes the skills, tools and hooks; your delegated-task history and handoff chats are kept on purpose (see "제거" below). To delete those too, remove `~/.samjil` by hand afterwards.
- The default install copies files only into `~/.claude/skills` and `~/.samjil`. It also tidies leftovers of older samjil installs if it finds them (an old Antigravity plugin entry in `~/.gemini/config`, old folders under `~/.samjil`); on a fresh PC there is nothing to tidy. `-AlwaysOn` adds one SessionStart hook entry to `~/.claude/settings.json` (backed up first). `-Full` is the author's complete setup (junction `~/.claude/skills` -> `~/.agents/skills`, Antigravity `skills.json`).

**What the installer does and why** (so a careful reader or a scanner is not surprised):
`powershell -ExecutionPolicy Bypass` because Windows blocks unsigned scripts by default and every script here is readable text (applies to these runs only, machine policy is unchanged) · `Unblock-File` clears the "downloaded from the internet" mark on copied files · a hidden background process is the watcher that runs agy for you (stop it with `stop-agy.ps1` or `Uninstall.cmd`) · installing from the unzipped pack (`Install.cmd`) makes no network calls (agy talks to Google with your own sign-in). Only the optional web one-liner (`irm ... | iex`, see "설치") downloads the repository from GitHub; skip it if you want a fully offline install.

The optional dashboard (`~/.samjil/viewer`, `http://127.0.0.1:8787`, off until you start it) shows delegated tasks and also reads the Claude Code session and usage records under `~/.claude/projects` on this PC. It listens on `127.0.0.1` only and sends nothing anywhere.

License: MIT (see [LICENSE](LICENSE)). Not affiliated with Anthropic or Google.

Skills installed together: `samjil-delegate-agy` (this is the English, short one; details in its `references/`), `samjil-handoff` (agy message channel) and `samjil-git-commit` (asks before every commit/push). The last two are Korean and activate on their own trigger phrases; delete their folders under `~/.claude/skills` if you only want delegation.

---
## 구성

| 스킬 | 하는 일 |
|---|---|
| [`samjil-delegate-agy`](samjil-delegate-agy/) | 난이도별 분담 기준(설계·가장 어려운 일은 Claude 직접, 나머지는 agy 위임)과 위임 규약. agy 결과는 반드시 검토하고 미달이면 다시 위임합니다. |
| [`samjil-handoff`](samjil-handoff/) | Claude ↔ agy 가 메시지 파일로 주고받는 비동기 대화 채널 규약(개설·상태 전이·자동 이어가기). |
| [`samjil-git-commit`](samjil-git-commit/) | 커밋·푸시 전 사용자 승인, 한글 커밋 메시지, 단계별 푸시 확인 절차. |

| 부속 도구 | 위치(설치 후) | 하는 일 |
|---|---|---|
| 위임 워처 | `~/.samjil/delegate-agy/` | inbox 의 지시문을 agy CLI 로 처리하고 결과를 돌려줍니다. 폴더는 `scripts`(도구) · `runtime`(대기 큐 · 실행 상태 · 로그) · `data`(위임 기록 DB `delegate.db` · 처리한 지시와 답 · 스크린샷 · 캐시 · 백업)로 나뉩니다. |
| 핸드오프 도구 | `~/.samjil/handoff/` | `scripts`(공용 함수 · Claude Stop 훅) · `templates` · `data\handoff.db`(원장과 자동 이어가기 상태 DB) · `channels\<프로젝트>\`(협의 메시지 원문과 BRIEF.md). |
| 웹 뷰어 | `~/.samjil/viewer/` | 위임·협의 기록과 워처 상태를 보는 대시보드(`http://127.0.0.1:8787`, 이 PC 에서만 접속). |

## 설치

스킬 정의(`SKILL.md`)만 에이전트 폴더에 두고, 실행 도구는 `~/.samjil/` 에 따로 둡니다.

- `~/.agents/skills/<스킬>/SKILL.md` 가 공용 위치입니다. Antigravity 는 `~/.gemini/config/skills.json` 에 이 폴더를 등록해 읽고, Claude Code 의 `~/.claude/skills` 는 이 폴더로 가는 정션 하나입니다(Cursor/Windsurf/Cline 도 `~/.agents/skills` 를 씁니다).
- 저장소 자체는 에이전트에 연결하지 않습니다(소스·설치 패키지 전용).

```powershell
# 1. 원클릭 웹 설치 (git/npm 불필요)
irm https://raw.githubusercontent.com/samjil/agy-agent/main/install.ps1 | iex

# 2. 로컬 저장소에서
.\install.ps1

# 3. skills.sh CLI (Node.js) — 스킬만 설치되고, 부속 도구는 첫 작업 때 AI 가 `~/.samjil/` 에 구성합니다
npx skills add samjil/agy-agent -g
npx skills add samjil/agy-agent -g --skill samjil-handoff
```

설치 스크립트는 여러 번 돌려도 같은 결과이며, 예전 이름의 스킬·플러그인 등록은 정리합니다. 옵션:

- **세션 시작 훅(`-AlwaysOn` 또는 `-Full` 일 때만)** — 기본 설치는 훅을 등록하지 않고, 위임은 사용자가 요청할 때만 합니다. `.\install.ps1 -AlwaysOn`(압축 팩은 `Install.cmd -AlwaysOn`)을 주면 `~/.claude/settings.json` 에 SessionStart 훅을 등록합니다(이미 등록돼 있으면 재설치 때 경로를 새로 고칩니다). 새 Claude 세션이 열릴 때 agy 워처를 창 없이 켜고(`stop-agy` 로 일부러 끈 상태면 켜지 않음), `samjil-delegate-agy` 스킬을 먼저 따르라는 문맥을 넣습니다. 바꾸기 전에 `settings.json.bak-*` 로 백업하고 `uninstall.ps1` 이 이 항목만 뺍니다.
- `.\install.ps1 -HandoffAutoHook` — Claude 쪽 핸드오프 자동 이어가기 Stop 훅을 `~/.claude/settings.json` 에 등록합니다(옵트인). 바꾸기 전에 `settings.json.bak-*` 로 백업하고 다른 설정·훅은 건드리지 않으며, JSON 이 깨져 있으면 손대지 않습니다. `irm | iex` 로 받을 때는 `$env:SAMJIL_HANDOFF_AUTO_HOOK = "1"` 을 먼저 지정합니다.
- 그 밖의 옵션: `-NoStart`(워처를 켜지 않음), `-SkipChecks`(`agy` 점검 생략), `-ReplyLanguage <언어>`(agy 답변 언어, 기본 `auto` = Windows 지역 설정을 따름), `-Full`(작성자 전체 구성). 설치 위치는 고정(`~/.claude/skills`, `~/.samjil`)이라 바꿀 수 없습니다.

## 제거

```powershell
irm https://raw.githubusercontent.com/samjil/agy-agent/main/uninstall.ps1 | iex   # 웹
.\uninstall.ps1                                                                  # 로컬 (= .\install.ps1 -Uninstall)
```

스킬·정션·Antigravity 등록·Stop 훅·뷰어와 실행 도구를 지웁니다. `~/.samjil/handoff/` 의 대화 기록과, 위임하면서 생긴 파일(`~/.samjil/delegate-agy/` 의 `runtime` · `data`: 큐 · 위임 기록 DB `delegate.db` · 로그 · 스크린샷)은 지우지 않습니다. `data` 의 위임 정보(DB 행 포함)는 워처가 켜질 때 3개월이 지난 것부터 알아서 지웁니다.

## 위임 워처

```powershell
~\.samjil\delegate-agy\scripts\start-agy.ps1            # 시작/재시작 (콘솔 창이 뜸)
~\.samjil\delegate-agy\scripts\start-agy.ps1 -Hidden    # 창 없이
~\.samjil\delegate-agy\scripts\stop-agy.ps1             # 안전 중지: 처리 중인 작업이 끝난 뒤 종료, 새 작업은 받지 않음
~\.samjil\delegate-agy\scripts\sub\ensure-agy-running.ps1 -CheckOnly -StaleThresholdSeconds 0   # ALIVE(0) / DEAD(1) / MANUAL_STOP(2)
```

이미 떠 있는 워처에 `start-agy.ps1` 를 다시 실행하면 처리 중인 작업이 끝나기를 기다린 뒤 교체합니다(기본 30초 대기, `-WaitSeconds` 로 늘림). 켜짐/꺼짐은 하트비트가 아니라 시작할 때 적는 PID 잠금 파일로 판단합니다(워처는 agy 응답을 기다리는 동안 하트비트를 쓰지 않습니다).

### 위임 호출: `submit-task.ps1`

Claude 는 위임할 때 이 도구 한 번으로 지시문 넣기·결과 기다리기를 합니다. 지시문은 표준입력(또는 `-File`)으로 받습니다.

```powershell
powershell.exe -NoProfile -File "$env:USERPROFILE\.samjil\delegate-agy\scripts\submit-task.ps1" <<'EOF'
@cwd: C:\project
<지시문>
EOF
```

- 기본으로 170초까지 기다리고, 안 끝나면 `===PENDING=== <ID> …` 로 진행 상태(경과·모델·마지막 단계)를 알려 줍니다. 작업은 계속 돌고 있으니 다시 제출하지 말고 `-Poll <ID>` 로 이어 확인합니다.
- `-NoWait` 로 여러 개를 넣고 `-Poll id1,id2` 로 한 번에 기다릴 수 있습니다.
- 종료 코드: 0 결과 있음 / 1 오류 / 2 진행 중 / 3 입력·환경 오류.
- 보내기 직전에 지시문을 점검해, 검증 방법·범위 제한·대상 파일이 없거나 너무 짧거나 길면 표준 오류에 `[브리프 점검]` 경고를 냅니다(경고일 뿐 위임은 그대로 진행, `AGY_BRIEF_LINT=off` 로 끔).

### 지시문 지시어

지시문 맨 위의 `@이름: 값` 줄입니다(순서 무관, `@` 가 아닌 첫 줄부터가 질문).

| 지시어 | 뜻 |
|---|---|
| `@cwd: <폴더>` | agy 가 읽고 쓸 폴더를 허용합니다(agy 의 `--add-dir`). agy 의 작업 폴더를 바꾸지는 않습니다. 폴더마다 한 줄씩 여러 줄 가능하고, 없는 폴더가 있으면 agy 를 부르지 않고 실패합니다. `@session` 으로 이어갈 때는 생략하면 세션에 저장된 목록을 씁니다. |
| `@session: <이름>` | 같은 이름으로 다시 보내면 agy 의 이전 대화를 이어갑니다. |
| `@model: <ID>` | 이번 호출에 쓸 모델(`gemini-3.8-flash-high\|medium\|low` 등). 쓰지 않으면 요청 내용으로 단계를 자동 선택합니다. 고른 모델이 쿼터 초과·사용 불가면 다른 모델로 넘어가지 않고 실패로 기록하며, 이어가는 세션에 다른 모델을 지정하면 오류입니다. |
| `@upgrade: true` | 이어가던 세션의 모델을 올릴 때 함께 씁니다. 새 대화를 시작하며 직전 질문·답 2쌍을 지시문 위에 붙입니다(이전에 읽은 파일·도구 기록은 이어지지 않음). |
| `@raw: true` | 아래 표준 규칙을 자동으로 붙이지 않습니다(번역처럼 규칙이 어울리지 않는 작업용). 핸드오프 펌프 지시문에도 표준 규칙이 붙습니다. |

### 동작 규칙

- **동시 실행**: 지시파일마다 작업자 프로세스를 따로 띄워 최대 5개(`-MaxParallel` 또는 `AGY_MAX_PARALLEL`)를 함께 돌립니다. 같은 `@session` 이면서 폴더(`@cwd`)가 겹치는 작업끼리만 차례로 합니다. 같은 세션 이름을 다른 폴더에서 동시에 쓰면 agy 대화가 섞일 수 있어 워처 로그에 주의가 남습니다.
- **마감과 멈춤**: agy 호출 하나는 최대 1800초(`AGY_TIMEOUT_SECONDS`)까지 기다리되, 대화 기록에 새 단계가 300초(`AGY_STALL_SECONDS`) 없으면 멈춘 것으로 보고 끊습니다. 백그라운드 명령을 기다리는 동안과, 마감을 넘겼어도 단계·도구 로그·CPU 중 하나가 살아 있으면 최대 7200초(`AGY_HARD_TIMEOUT_SECONDS`)까지 기다립니다. 끊기 직전에 대화 기록의 마지막이 도구 호출 없는 최종 응답이면 실패로 두지 않고 그 응답을 답으로 회수합니다.
- **지시문 전달**: 짧은 지시문은 agy 호출 인자로 직접 넘기고, 긴 것(8000자 초과)이나 파일 참조(`@파일`)가 필요하면 파일로 넘깁니다.
- **표준 규칙 자동 추가**: `@cwd` 작업에는 `DO NOT COMMIT` · 포그라운드 실행 · 필요한 파일만 수정 · 한글 답변 규칙을 프롬프트 끝에 붙입니다(이미 있는 규칙은 건너뜀, 위임 기록의 질문에는 원본만 남음).
- **git 안전장치**: `@cwd` 가 git 저장소면 agy 호출 전후의 HEAD·브랜치·stash 를 비교해 바뀌었으면 응답 맨 위에 경고와 복구 명령을 붙입니다(자동으로 되돌리지는 않음). 커밋하지 않은 변경은 `refs/samjil/snapshots/<작업 ID>` 에 보관합니다(최근 20개, 추적 파일만). `AGY_GIT_GUARD=off` 로 끕니다.
- **모델 단계 자동 선택**: 모델·`@session` 을 지정하지 않은 위임과 핸드오프 메시지는 요청 내용(키워드·길이·폴더 접근)으로 `low`/`medium`/`high` 를 규칙 기반으로 고릅니다. 분명히 쉬운 일만 낮추고 애매하면 `high` 이며, 폴더의 작은 수정(고치는 말뿐·500자 이하·파일 1개 이하)만 `medium` 입니다. 이유는 `watcher.log` 의 `모델 자동 선택:` 줄에 남고, `AGY_AUTO_MODEL=off` 로 끕니다.
- **위임 기록**: 사용량·질문·답·과정(도구 호출 목록)·agy 세션은 `~/.samjil/delegate-agy/data/delegate.db` 하나에 쌓입니다(Windows 의 `winsqlite3.dll` 을 쓰므로 설치할 것이 없고, 여러 프로세스가 동시에 써도 됩니다). 로그(`watcher.log` 등 진짜 런타임 로그만)는 `runtime/logs/` 에 있습니다. 하트비트·잠금·정지 표시는 `runtime/` 바로 아래에 있습니다.

## 핸드오프 (Claude ↔ agy 대화)

채널은 저장소 폴더 이름과 같은 이름의 폴더(`~/.samjil/handoff/channels/<채널>/`)이고, `BRIEF.md`(배경·저장소 경로), `msg/NNNN-<방향>-….md`(메시지 원문), `INDEX.md`(원장 보기)로 이루어집니다. 원장(번호·시각·방향·제목·상태)과 자동 이어가기 상태(위임 기록·멈춤·훅이 막은 횟수)는 `~/.samjil/handoff/data/handoff.db` 에 있고, `INDEX.md` 는 그 DB 에서 다시 만드는 보기입니다(줄을 손으로 고쳐도 다음에 읽을 때 DB 에 반영됩니다). 메시지와 원장·상태는 **3개월**이 지나면 워처가 켜질 때 지웁니다(번호는 다시 쓰지 않습니다). 방향은 `c2a`(Claude→agy) / `a2c`(agy→Claude), 상태는 `보냄 → 읽음 → 처리됨`(받은 쪽이 직접 반영) 또는 `확인함`(검증만) 이고 `보류` 가 있습니다. 규약의 세부는 [`samjil-handoff/SKILL.md`](samjil-handoff/SKILL.md) 입니다.

회신은 사용자가 "메시지 확인해줘"라고 말하지 않아도 자동으로 이어집니다.

| 방향 | 동작 |
|---|---|
| Claude → agy | 워처의 핸드오프 펌프가 5초마다 채널을 봅니다. Claude 가 보낸 새 메시지(`보냄`, 최근 2시간 이내)를 agy 에게 위임하고(`@session: handoff-<채널>`, `@cwd` 는 채널 폴더 + `BRIEF.md` 의 저장소 경로), agy 의 최종 답을 `a2c` 회신으로 기록하고 원래 메시지를 `처리됨` 으로 바꿉니다. 실패하면 `보류` + 실패 알림 회신입니다. |
| agy → Claude | Claude Code **Stop 훅**이 턴이 끝날 때 채널을 봅니다. 회신이 와 있으면 턴을 끝내지 않고 이어서 처리하게 하고, 방금 보낸 메시지의 회신을 기다리는 중이면 올 때까지(기본 30분) 기다렸다가 같은 세션에서 이어 갑니다. |

- **훅 켜기·끄기**: `install.ps1 -HandoffAutoHook`(위 설치 절)으로 켜고, `uninstall.ps1` 또는 `~\.samjil\handoff\scripts\register-handoff-hook.ps1 -Remove` 로 뺍니다. agy 쪽은 워처가 켜져 있으면 별도 설정 없이 동작합니다.
- **세션 구분**: 같은 채널을 Claude 세션 여럿이 쓸 수 있어서, 훅이 Claude 가 쓴 `c2a` 머리말에 `세션:`(세션 ID)을 적고 회신은 그 메시지를 쓴 세션에게만 알립니다(주인 세션의 기록이 1시간 넘게 멈췄거나 표시가 없는 옛 메시지는 아무 세션이나 받음). 뷰어도 회신을 질문을 보낸 세션에 붙입니다.
- **한도·안전장치**: 한 대화 줄기의 자동 왕복은 최근 60분에 6회(`AGY_HANDOFF_MAX_ROUNDS`)이고, 넘으면 멈춰서 뷰어에 "사용자 확인 필요"로 뜹니다(**한도 초기화** 버튼). 한 채널에서는 한 번에 하나만 위임하고, 2시간(`AGY_HANDOFF_MAX_AGE_HOURS`)보다 오래된 `보냄` 메시지는 위임하지 않습니다(뷰어에 "자동 위임 안 됨"으로 표시). 채널 폴더에 `AUTO.off` 파일을 두거나 뷰어의 **끄기** 버튼으로 끌 수 있고, 워처가 꺼져 있으면 훅은 회신을 기다리지 않고 그렇게 알립니다.
- 메시지를 쓰는 스크립트에는 `모델:` 을 직접 적지 말고 비워 두세요. Stop 훅이 대화 기록의 실제 모델과 노력 단계를 채웁니다.
- `c2a` 머리말에 `위임모델: low|medium|high`(또는 `gemini-3.8-flash-<단계>`)를 적으면 자동 단계 선택 대신 그 단계로 위임합니다(AS-IS/TO-BE 가 정해진 구현 명세를 `medium` 으로 보낼 때).
- 채널 루트는 `~/.samjil/handoff/channels/`(환경변수 `AGENT_HANDOFF_ROOT` 로 바꿈), DB 는 그 옆 `data/`(환경변수 `AGENT_HANDOFF_DATA`)입니다. 옛 배치(`~/.samjil/handoff/<채널>/`)는 처음 열 때 `channels/` 로 옮기고, 옛 `AUTO.json` 은 DB 로 옮깁니다.

## 웹 뷰어

```powershell
~\.samjil\viewer\serve-viewer.ps1            # 콘솔 창 + 브라우저 탭 (창을 닫으면 꺼짐)
~\.samjil\viewer\ensure-viewer-running.ps1   # 창·탭 없이 켜기: STARTED / ALIVE (-CheckOnly, -Stop, -Port 9000)
~\.samjil\viewer\start-viewer-hidden.vbs     # 더블클릭·시작 프로그램용(깜빡임 없이 숨김 실행)
```

`http://127.0.0.1:8787`(이 PC 전용)을 열고 5초마다 자동 갱신합니다. 뷰어는 시작할 때 꺼져 있는 워처도 함께 켜고(`-NoAgent` 로 끔), 60초마다(`-WatcherCheckSeconds`, 0 이면 끔) 워처를 점검해 꺼져 있으면 창 없이 다시 켭니다. `stop-agy.ps1` 로 일부러 끈 상태(수동 정지)는 켜지 않고 화면에 "수동 정지"로 보이며, 사이드바 하단의 **켜기** 버튼으로는 켤 수 있습니다.

**화면**
- **대시보드**: agy 의 현재 상태(작업 중·대기·워처 꺼짐), 최근 위임 결과 띠, **확인 필요**(처리 대기 중인 메시지·최근 24시간의 실패), 위임과 협의를 합친 최근 활동, 누적 통계·모델 분포·**Claude 토큰 절약(예상)**.
- **에이전트 위임**: 질문·답변 카드(모델·상태 필터, 검색). 진행 중인 카드는 지금 하는 일, 최근 생각, 실시간 토큰, 상태(진행 중·조용함·멈춤)를 보입니다. 긴 질문·답변은 일반적인 길이까지만 보이고 **전체 보기**(렌더링/Raw)로 원본을 엽니다.
- **에이전트 협의**: 채널별 메시지 타임라인, 방향·상태 필터(보냄→읽음→처리됨→확인함 진행 표시), `BRIEF.md` 열람, 채널 상단의 자동 이어가기 상태와 켜기/끄기/한도 초기화. 방향은 메시지 머리말의 모델로 `Claude Sonnet 5.5 (Medium) → Gemini 3.8 Flash (High)` 처럼 보입니다.
- 사이드바는 **Claude Desktop 의 프로젝트 그룹 → 대화 세션** 트리이고(정렬 선택·펼침 상태 기억), 라이트/다크/시스템 테마를 고를 수 있습니다. 색은 보낸 쪽을 뜻합니다: Claude 는 황토, agy 는 청록, 초록/빨강은 성공/실패에만 씁니다.

**과정 창**: 카드의 **과정 N** 버튼을 누르면 agy 가 질문과 답변 사이에 한 일(도구 호출 목록: 번호·시각·한글 설명·대상·생각·진행 설명)이 열립니다. 진행 중에는 새 단계가 이어 붙습니다. 영어로 나온 생각·설명은 **agy 로 번역**(서버가 agy 에게 읽기 전용으로 시켜 캐시, 사용량을 씀)과 **브라우저로 번역**(Chrome 계열의 내장 번역, 무료·품질 낮을 수 있음)으로 한글로 볼 수 있습니다. 과정은 워처가 작업을 마칠 때 `agy.db` 에 저장하고, 예전 기록은 창을 열 때만 agy 대화 기록에서 읽어 옵니다.

**토큰 표시**
- 카드의 토큰 줄은 `총 토큰 = 누적 입력 + 누적 출력` 이고, 입력에는 캐시에서 읽은 양(`캐시`), 출력에는 `응답 · 사고` 가 덧붙고, `현재 컨텍스트`(마지막 턴이 모델에 보낸 입력 크기)가 따로 있습니다. 진행 중과 끝난 뒤가 같은 기준입니다. 이어 쓰는 세션은 대화 누적값이라 앞 호출과의 차이를 "이번 호출이 쓴 양"으로 봅니다.
- **Claude 토큰 절약(예상)**: 이 도구는 Claude 가 쓴 토큰을 직접 잴 수 없어서, agy 가 남긴 과정(읽은 파일 크기·쓴 파일·고친 곳·명령·생각)에서 "같은 일을 Claude 가 직접 했다면" 쓸 분량을 어림하고 위임하느라 쓴 질문 분량을 뺀 예상값을 카드·세션 칩·대시보드에 보입니다(성공한 위임만).
- 협의 카드의 Claude 쪽 사용량은 해당 Claude 세션의 기록(`~/.claude/projects/*/<세션>.jsonl`)에서 읽는 근사치입니다.

**세션 찾기**: 위임 기록·협의 메시지에는 Claude 세션 ID 가 없어서, 뷰어가 Claude 대화 기록에서 위임 작업 ID(`claude_…`)와 메시지 파일 이름이 처음 나온 세션을 주인으로 봅니다. 대화 기록은 매우 클 수 있어 `scan-claude-links.ps1` 이 창 없는 별도 프로세스로 색인을 늘려 갑니다. 모든 읽기는 읽기 전용이며, 쓰기·실행 API(켜기, 번역 시작, 자동 이어가기 제어 등)는 전용 헤더가 있는 POST 만 받아 다른 웹 페이지가 호출하지 못하게 합니다.


## 지원 에이전트

- **Claude Code**: `~/.claude/skills/`(→ `~/.agents/skills` 정션)에서 자동 감지
- **Google Antigravity**: `~/.gemini/config/skills.json` 에 등록된 `~/.agents/skills` 에서 자동 감지
- **Cursor / Windsurf / Cline**: `~/.agents/skills` 또는 `npx skills add` 로 지원
