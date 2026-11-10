// extract-questions.js
// 예상이 비어 있는 과거 질문(행)의 "질문 원문"을 대화 기록(jsonl)에서 찾아 낸다. 일 처리 결과(도구 호출 · 토큰 · 시간)는 읽지 않는다 — 예상을 원문만 보고 채우려고.
//   node extract-questions.js <rows.json> <out-items.json>
// rows.json : [{ id, file, turn_ts, ... }]  (token_turns 에서 예상이 없는 행)
// 출력      : [{ id, text, prev }]  text = 질문 원문(앞 600자), prev = 바로 앞 질문 원문(앞 150자, 맥락용). 원문을 못 찾은 행은 빠진다.
"use strict";
const fs = require("fs");

const rows = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const outPath = process.argv[3];

function textOf(content) {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  if (content.some((b) => b && b.type === "tool_result")) return "";
  return content.filter((b) => b && b.type === "text" && typeof b.text === "string").map((b) => b.text).join(" ");
}
function isRealPrompt(t) {
  const s = t.trim();
  if (!s) return false;
  return !(s.startsWith("<system-reminder") || s.startsWith("<command-") || s.startsWith("<local-command") || s.startsWith("[SYSTEM NOTIFICATION"));
}

const byFile = new Map();
for (const r of rows) {
  if (!byFile.has(r.file)) byFile.set(r.file, []);
  byFile.get(r.file).push(r);
}

const items = [];
let missing = 0;
for (const [file, frs] of byFile) {
  if (!fs.existsSync(file)) { missing += frs.length; continue; }
  // 시각 -> 질문 원문(사용자가 직접 입력한 프롬프트 · 대기열 메시지(attachment 시각과 enqueue 시각 둘 다))
  const byTs = new Map();
  const order = [];            // [{ ts, text }] 도착 순서(맥락용)
  const enqueued = [];         // 아직 짝이 없는 enqueue { ts, text }
  for (const line of fs.readFileSync(file, "utf8").split("\n")) {
    if (!line) continue;
    let o;
    try { o = JSON.parse(line); } catch { continue; }
    if (o.isSidechain || o.isMeta) continue;
    if (o.type === "queue-operation" && o.operation === "enqueue" && typeof o.content === "string") {
      enqueued.push({ ts: o.timestamp, text: o.content });
    } else if (o.type === "user" && o.message) {
      const t = textOf(o.message.content);
      if (isRealPrompt(t) && !t.trimStart().startsWith("This session is being continued")) { byTs.set(o.timestamp, t); order.push({ ts: o.timestamp, text: t }); }
    } else if (o.type === "attachment" && o.attachment && o.attachment.type === "queued_command" && o.attachment.origin && o.attachment.origin.kind === "human") {
      const p = o.attachment.prompt;
      const t = typeof p === "string" ? p : textOf(p);
      if (!t.trim()) continue;
      byTs.set(o.timestamp, t);
      const i = enqueued.findIndex((e) => e.text === t);
      if (i >= 0) { byTs.set(enqueued[i].ts, t); enqueued.splice(i, 1); }
      order.push({ ts: o.timestamp, text: t });
    }
  }
  order.sort((a, b) => (a.ts < b.ts ? -1 : 1));
  for (const r of frs) {
    const t = byTs.get(r.turn_ts);
    if (!t) { missing++; continue; }
    let prev = "";
    for (let i = order.length - 1; i >= 0; i--) { if (order[i].ts < r.turn_ts) { prev = order[i].text; break; } }
    items.push({ id: r.id, text: t.replace(/\s+/g, " ").trim().slice(0, 600), prev: prev.replace(/\s+/g, " ").trim().slice(0, 150) });
  }
}
fs.writeFileSync(outPath, JSON.stringify(items));
console.log(`질문 원문 ${items.length}건, 원문을 못 찾은 행 ${missing}건`);
