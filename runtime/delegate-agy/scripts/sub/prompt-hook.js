// prompt-hook.js
// Claude Code UserPromptSubmit 훅(Node 판). 질문을 보낼 때마다 돌기 때문에 빠르게(PowerShell 판은 약 0.6초, 이 판은 약 0.1초).
// session-start-hook.ps1 -Event UserPromptSubmit 과 같은 일을 한다:
//   컨텍스트가 기준(AGY_CTX_SUBAGENT_THRESHOLD, 없으면 200k)을 넘으면 "위임하면 처음부터 서브에이전트에" 한 줄.
//   크기는 표준 입력 JSON 의 transcript_path(대화 기록) 끝에서 마지막 응답의 usage 로 읽는다.
// 어떤 오류에도 종료 코드 0.
// 사용: node prompt-hook.js [--transcript <대화 기록>]   (Node 가 없으면 등록기가 PowerShell 판을 건다)
"use strict";
const fs = require("fs");

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

function main() {
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
    process.stdout.write("[컨텍스트 " + Math.round(ctx / 1000) + "k] 기준 " + Math.floor(threshold / 1000) + "k 를 넘었다: 이번 질문에서 위임하게 되면 처음부터 서브에이전트 하나(저렴한 모델)에 브리프를 넘겨 제출 · 대기 · diff 검토 · 시험까지 맡기고, 본 세션은 5줄 보고(통과 여부 · 바뀐 파일 · 걱정)만 받는다.\n");
  }
}

try { main(); } catch (e) { /* 훅 오류가 질문을 막으면 안 된다 */ }
process.exitCode = 0;
