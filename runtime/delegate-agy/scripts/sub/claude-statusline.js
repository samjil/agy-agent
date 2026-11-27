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
  const tmpPath = targetPath + "." + process.pid + "." + Date.now() + "." + Math.random().toString(36).slice(2, 8) + ".tmp";
  try {
    fs.writeFileSync(tmpPath, text, "utf8");
    try {
      fs.renameSync(tmpPath, targetPath);
    } catch (renameErr) {
      fs.copyFileSync(tmpPath, targetPath);
    }
  } catch (e) {
  } finally {
    try { fs.unlinkSync(tmpPath); } catch (e2) {}
  }
}

function acquireHistoryLock(histPath) {
  const lockPath = histPath + ".lock";
  const deadline = Date.now() + 1500;
  while (true) {
    try {
      const fd = fs.openSync(lockPath, "wx");
      try { fs.writeSync(fd, String(process.pid) + "\n"); } catch (e) {}
      try { fs.closeSync(fd); } catch (e2) {}
      return lockPath;
    } catch (err) {
      try {
        const st = fs.statSync(lockPath);
        if (Date.now() - st.mtimeMs > 10000) {
          fs.unlinkSync(lockPath);
        }
      } catch (e3) {}
      if (Date.now() >= deadline) return "";
      const waitUntil = Date.now() + 25;
      while (Date.now() < waitUntil) {}
    }
  }
}

function releaseHistoryLock(lockPath) {
  if (!lockPath) return;
  try { fs.unlinkSync(lockPath); } catch (e) {}
}

function normalizeIsoSec(iso) {
  return String(iso || "").replace(/\.\d{3}Z$/, "Z");
}

function findLastClaudeHistory(histPath) {
  if (!fs.existsSync(histPath)) return null;
  const stat = fs.statSync(histPath);
  const len = stat.size;
  if (len <= 0) return null;

  const tailSize = Math.min(len, 65536);
  const offset = len - tailSize;
  const buf = Buffer.alloc(tailSize);
  const fd = fs.openSync(histPath, "r");
  let readBytes = 0;
  try {
    readBytes = fs.readSync(fd, buf, 0, tailSize, offset);
  } finally {
    try { fs.closeSync(fd); } catch (e) {}
  }

  let lines = buf.toString("utf8", 0, readBytes).replace(/^\uFEFF/, "").split(/\r?\n/).filter(Boolean);
  if (offset > 0 && lines.length > 0) lines = lines.slice(1);
  for (let i = lines.length - 1; i >= 0; i--) {
    try {
      const o = JSON.parse(lines[i]);
      if (o && o.src === "claude") return o;
    } catch (e) {}
  }

  if (offset > 0) {
    const allLines = fs.readFileSync(histPath, "utf8").replace(/^\uFEFF/, "").split(/\r?\n/).filter(Boolean);
    for (let i = allLines.length - 1; i >= 0; i--) {
      try {
        const o = JSON.parse(allLines[i]);
        if (o && o.src === "claude") return o;
      } catch (e) {}
    }
  }
  return null;
}

function appendUsageHistory(runtimeDir, checkedAtIso, five, seven) {
  if (!runtimeDir || !five || !seven) return;
  if (typeof five.used_pct !== "number" || !isFinite(five.used_pct) || five.used_pct < 0 || five.used_pct > 100) return;
  if (typeof seven.used_pct !== "number" || !isFinite(seven.used_pct) || seven.used_pct < 0 || seven.used_pct > 100) return;
  if (!five.resets_at || !seven.resets_at) return;

  const fiveInt = Math.round(five.used_pct);
  const weekInt = Math.round(seven.used_pct);
  const fiveReset = normalizeIsoSec(five.resets_at);
  const weekReset = normalizeIsoSec(seven.resets_at);
  const atIso = normalizeIsoSec(checkedAtIso);

  const histPath = path.join(runtimeDir, "usage-history.jsonl");
  fs.mkdirSync(runtimeDir, { recursive: true });
  const lockPath = acquireHistoryLock(histPath);
  try {
    const last = findLastClaudeHistory(histPath);
    if (last) {
      if (last.five === fiveInt && last.week === weekInt &&
          normalizeIsoSec(last.five_reset) === fiveReset &&
          normalizeIsoSec(last.week_reset) === weekReset) {
        return;
      }
    }

    const line = JSON.stringify({
      src: "claude",
      at: atIso,
      five: fiveInt,
      five_reset: fiveReset,
      week: weekInt,
      week_reset: weekReset
    });
    fs.appendFileSync(histPath, line + "\n", "utf8");

    if (fs.statSync(histPath).size > 1048576) {
      const cutoffMs = Date.parse(atIso) - 60 * 86400 * 1000;
      const allLines = fs.readFileSync(histPath, "utf8").replace(/^\uFEFF/, "").split(/\r?\n/).filter(Boolean);
      const kept = [];
      for (let i = 0; i < allLines.length; i++) {
        try {
          const o = JSON.parse(allLines[i]);
          if (!o || !o.at) continue;
          const ms = Date.parse(o.at);
          if (!isNaN(ms) && ms >= cutoffMs) kept.push(allLines[i]);
        } catch (e) {}
      }
      const finalKept = kept.length > 6000 ? kept.slice(-6000) : kept;
      writeAtomic(histPath, finalKept.length > 0 ? finalKept.join("\n") + "\n" : "");
    }
  } finally {
    releaseHistoryLock(lockPath);
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
  try { appendUsageHistory(runtimeDir, payload.checked_at, five, seven); } catch (e) {}

  const parts = [];
  if (five) parts.push("5h " + Math.round(five.used_pct) + "%");
  if (seven) parts.push("7d " + Math.round(seven.used_pct) + "%");
  if (parts.length > 0) process.stdout.write(parts.join(" · "));
}

try { main(); } catch (e) {}
process.exitCode = 0;
