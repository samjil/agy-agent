// prompt-hook.js
// Claude Code UserPromptSubmit · PreToolUse 훅(Node 판). 자주 돌기 때문에 빠르게(PowerShell 판은 약 0.6초, 이 판은 약 0.1초).
// session-start-hook.ps1 -Event UserPromptSubmit / -Event PreToolUse 와 같은 일을 한다:
//   - 기본(UserPromptSubmit): 컨텍스트가 기준(AGY_CTX_SUBAGENT_THRESHOLD, 없으면 200k)을 넘으면 "위임하면 agy 제출을 서브에이전트에" 한 줄.
//     크기는 표준 입력 JSON 의 transcript_path(대화 기록) 끝에서 마지막 응답의 usage 로 읽는다.
//   - --event PreToolUse: Agent/Task 도구 호출 시 세션마다 처음 한 번 agy 위임 관문(deny), 두 번째부터는 참고 안내(additionalContext).
// 어떤 오류에도 종료 코드 0.
// 사용: node prompt-hook.js [--transcript <대화 기록>] [--event PreToolUse]   (Node 가 없으면 등록기가 PowerShell 판을 건다)
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");

const GATE_DENY_MSG = "[samjil-delegate-agy] Agent 도구 관문(세션마다 처음 한 번): 코드 · 문서 · 설정 파일 · xlsx/pptx 를 고치거나 만드는 일은 samjil-delegate-agy 규칙상 agy 위임이 먼저다. agy 대상이면 samjil-delegate-agy 스킬을 불러와 submit-task 로 제출한다(컨텍스트가 크면 서브에이전트에게 agy 제출 · 대기 · 검토를 맡긴다). agy 로 못 하는 일(DB 조회 · VPN · 브라우저 · 메일 · 대화 맥락 판단)이거나 agy 가 실패 · 시간 초과했으면 같은 Agent 호출을 다시 하면 통과한다.";
const GATE_NOTE_MSG = "[samjil-delegate-agy] 참고: 파일을 고치거나 만드는 일은 Agent 도구보다 agy 위임(samjil-delegate-agy)이 먼저다. Agent 도구는 agy 로 못 하는 일이거나 agy 가 실패 · 시간 초과했을 때만 쓴다.";
const READONLY_SUBAGENTS = new Set(["explore", "plan", "claude-code-guide", "web-fetch", "statusline-setup"]);

function arg(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : "";
}

// 표준 입력(Claude Code 가 주는 JSON)을 읽는다. 입력이 터미널이면(손으로 실행) 읽지 않는다.
function readStdin() {
  try {
    if (process.stdin.isTTY) return "";
    return fs.readFileSync(0, "utf8");
  } catch (e) { return ""; }
}

// 대화 기록 끝에서 마지막 Claude 응답의 컨텍스트 크기(입력 + 캐시 쓰기 + 캐시 읽기 + 출력). 끝 64KB, 없으면 512KB 까지.
function lastContextTokens(file) {
  let fd;
  try {
    fd = fs.openSync(file, "r");
    const len = fs.fstatSync(fd).size;
    for (const tail of [65536, 524288]) {
      const n = Math.min(len, tail);
      const buf = Buffer.alloc(n);
      fs.readSync(fd, buf, 0, n, len - n);
      const lines = buf.toString("utf8").split(/\r?\n/);
      for (let i = lines.length - 1; i >= 0; i--) {
        const ln = lines[i];
        if (!ln || ln.indexOf('"usage"') < 0 || ln.indexOf('"assistant"') < 0) continue;
        let o;
        try { o = JSON.parse(ln); } catch (e) { continue; }
        const msg = o && o.message;
        if (!o || o.type !== "assistant" || !msg || !msg.usage || !msg.model || msg.model === "<synthetic>") continue;
        const u = msg.usage;
        return (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0) + (u.output_tokens || 0);
      }
      if (n >= len) break;
    }
  } catch (e) { /* 없음 */ } finally { if (fd !== undefined) try { fs.closeSync(fd); } catch (e) {} }
  return 0;
}

function writeJsonLine(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

function handlePreToolUse() {
  const mode = String(process.env.AGY_AGENT_GATE || "").trim().toLowerCase();
  if (mode === "off") return;
  const raw = readStdin().replace(/^\uFEFF/, "").trim();
  if (!raw) return;
  let j;
  try { j = JSON.parse(raw); } catch (e) { return; }
  if (!j || typeof j !== "object") return;
  const tool = String(j.tool_name || "");
  if (tool !== "Agent" && tool !== "Task") return;
  const ti = j.tool_input && typeof j.tool_input === "object" ? j.tool_input : {};
  const sub = String(ti.subagent_type || "").trim();
  if (sub && (READONLY_SUBAGENTS.has(sub.toLowerCase()) || /(explor|review|analyz|guide)/i.test(sub))) return;
  const prompt = String(ti.prompt || "");
  const desc = String(ti.description || "");
  const passRe = /(submit-task|samjil-delegate-agy|\bagy\b)/i;
  if (passRe.test(prompt) || passRe.test(desc)) return;

  const noteOut = { hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: GATE_NOTE_MSG } };
  if (mode === "note") {
    writeJsonLine(noteOut);
    return;
  }
  const sid = String(j.session_id || "").replace(/[^A-Za-z0-9_-]/g, "");
  if (!sid) {
    writeJsonLine(noteOut);
    return;
  }
  const dir = process.env.AGY_AGENT_GATE_DIR || path.join(os.tmpdir(), "samjil-agent-gate");
  const marker = path.join(dir, sid);
  if (fs.existsSync(marker)) {
    writeJsonLine(noteOut);
    return;
  }
  try {
    fs.mkdirSync(dir, { recursive: true });
    const cutoff = Date.now() - 7 * 86400 * 1000;
    for (const f of fs.readdirSync(dir)) {
      const p = path.join(dir, f);
      try {
        const st = fs.statSync(p);
        if (st.isFile() && st.mtimeMs < cutoff) fs.unlinkSync(p);
      } catch (e) {}
    }
    fs.writeFileSync(marker, "");
  } catch (e) {}
  writeJsonLine({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: GATE_DENY_MSG
    }
  });
}

function main() {
  if (arg("--event") === "PreToolUse") {
    handlePreToolUse();
    return;
  }
  let transcript = arg("--transcript");
  if (!transcript) {
    // 입력 앞에 BOM 이 붙어 오는 경우가 있어(Windows 의 일부 파이프) 떼고 읽는다
    try { const j = JSON.parse(readStdin().replace(/^﻿/, "").trim() || "{}"); transcript = j.transcript_path || ""; } catch (e) { transcript = ""; }
  }
  if (!transcript) return;
  let threshold = 200000;
  const envTh = process.env.AGY_CTX_SUBAGENT_THRESHOLD;
  if (envTh && /^\d+$/.test(envTh)) threshold = parseInt(envTh, 10);
  const ctx = lastContextTokens(transcript);
  if (ctx > threshold) {
    process.stdout.write("[컨텍스트 " + Math.round(ctx / 1000) + "k] 기준 " + Math.floor(threshold / 1000) + "k 를 넘었다: 이번 작업을 위임하면 samjil-delegate-agy 로 agy 에 제출한다. 제출 · 대기 · diff 검토 · 시험은 서브에이전트 하나(저렴한 모델)가 대신 맡고, 본 세션은 5줄 보고(통과 여부 · 바뀐 파일 · 걱정)만 받는다. agy 로 못 하는 일(DB · VPN · 브라우저 · 메일)만 서브에이전트가 직접 하고, 대화 맥락이 필요한 판단은 본 세션이 한다.\n");
  }
}

try { main(); } catch (e) { /* 훅 오류가 질문을 막으면 안 된다 */ }
process.exitCode = 0;
