// claude-statusline.js
// Claude Code statusLine 표준 입력(JSON)에서 rate_limits(5시간·주간 사용 비율 및 리셋 시각)만 읽어
// runtime/claude-limits.json 에 원자적으로 저장하고, 짧은 상태 줄을 출력한다. (의존성 없음, 예외 금지)
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");

function readStdin() {
  try {
    if (process.stdin.isTTY) return "";
    return fs.readFileSync(0, "utf8");
  } catch (e) {
    return "";
  }
}

function toIsoReset(val) {
  if (typeof val === "number" && isFinite(val) && val > 0) {
    const ms = val > 1e12 ? val : val * 1000;
    const d = new Date(ms);
    if (!isNaN(d.getTime())) return d.toISOString();
  }
  if (typeof val === "string" && val.trim()) {
    const d = new Date(val.trim());
    if (!isNaN(d.getTime())) return d.toISOString();
  }
  return "";
}

function extractLimit(entry) {
  if (!entry || typeof entry !== "object") return null;
  const pct = entry.used_percentage;
  if (typeof pct !== "number" || !isFinite(pct) || pct < 0) return null;
  const out = { used_pct: pct };
  const resetIso = toIsoReset(entry.resets_at);
  if (resetIso) out.resets_at = resetIso;
  return out;
}

function writeAtomic(targetPath, text) {
  const dir = path.dirname(targetPath);
  fs.mkdirSync(dir, { recursive: true });
  const tmpPath = targetPath + "." + process.pid + ".tmp";
  try {
    fs.writeFileSync(tmpPath, text, "utf8");
    try {
      fs.renameSync(tmpPath, targetPath);
    } catch (renameErr) {
      try { fs.unlinkSync(targetPath); } catch (e) {}
      fs.renameSync(tmpPath, targetPath);
    }
  } catch (e) {
    try { fs.unlinkSync(tmpPath); } catch (e2) {}
  }
}

function main() {
  const raw = readStdin().replace(/^\uFEFF/, "").trim();
  if (!raw) return;
  let data;
  try { data = JSON.parse(raw); } catch (e) { return; }
  if (!data || typeof data !== "object") return;
  const rl = data.rate_limits;
  if (!rl || typeof rl !== "object") return;

  const five = extractLimit(rl.five_hour);
  const seven = extractLimit(rl.seven_day);
  if (!five && !seven) return;

  const payload = { checked_at: new Date().toISOString() };
  if (five) payload.five_hour = five;
  if (seven) payload.seven_day = seven;
  payload.source = "statusline";

  const runtimeDir = process.env.AGY_DELEGATE_RUNTIME || path.join(os.homedir(), ".samjil", "delegate-agy", "runtime");
  const targetFile = path.join(runtimeDir, "claude-limits.json");
  writeAtomic(targetFile, JSON.stringify(payload));

  const parts = [];
  if (five) parts.push("5h " + Math.round(five.used_pct) + "%");
  if (seven) parts.push("7d " + Math.round(seven.used_pct) + "%");
  if (parts.length > 0) process.stdout.write(parts.join(" · "));
}

try { main(); } catch (e) {}
process.exitCode = 0;
