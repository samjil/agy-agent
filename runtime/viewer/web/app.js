// app.js
// samjil 에이전트 통합 대시보드 & 뷰어
// 2단 사이드바 레이아웃: 대시보드(Home), 세션별 에이전트 위임(QA), 프로젝트별 인수인계(Handoff)
(function () {
  "use strict";

  var PAGE_SIZE = 50;
  var AUTO_REFRESH_MS = 5000;

  // DOM 엘리먼트 참조
  var els = {
    appContainer:         document.getElementById("app-container"),
    appSidebar:           document.getElementById("app-sidebar"),
    sidebarBrand:         document.getElementById("sidebar-brand"),
    sidebarCollapseBtn:   document.getElementById("sidebar-collapse-btn"),
    topbarMenuToggle:     document.getElementById("topbar-menu-toggle"),

    // 1차 네비게이션
    navBtnDashboard:      document.getElementById("nav-btn-dashboard"),
    navBtnQa:             document.getElementById("nav-btn-qa"),
    navBtnHandoff:        document.getElementById("nav-btn-handoff"),
    navBtnStats:          document.getElementById("nav-btn-stats"),

    // 2차 서브 패널
    subDashboard:         document.getElementById("sidebar-sub-dashboard"),
    subQa:                document.getElementById("sidebar-sub-qa"),
    subHandoff:           document.getElementById("sidebar-sub-handoff"),

    // 대시보드 서브 패널: 최근 세션 바로가기
    quickSessionsList:    document.getElementById("quick-sessions-list"),

    // QA 세션 사이드바
    qaSessionCount:       document.getElementById("qa-session-count"),
    qaSessionSearch:      document.getElementById("qa-session-search"),
    qaSessionList:        document.getElementById("qa-session-list"),
    qaSourceTabs:         document.getElementById("qa-source-tabs"),
    qaTreeSort:           document.getElementById("qa-tree-sort"),
    modelFilter:          document.getElementById("modelfilter"),
    statusFilter:         document.getElementById("statusfilter"),
    sidebarBackdrop:      document.getElementById("sidebar-backdrop"),

    // Handoff 프로젝트 사이드바
    handoffProjectCount:  document.getElementById("handoff-project-count"),
    handoffProjectSearch: document.getElementById("handoff-project-search"),
    handoffProjectList:   document.getElementById("handoff-project-list"),
    handoffTreeSort:      document.getElementById("handoff-tree-sort"),
    handoffDirFilter:     document.getElementById("handoff-dir-filter"),
    handoffStatusFilter:  document.getElementById("handoff-status-filter"),
    handoffLegendClaude:  document.getElementById("handoff-legend-claude"),
    handoffLegendAgy:     document.getElementById("handoff-legend-agy"),
    handoffAutoBar:       document.getElementById("handoff-auto-bar"),

    // 사이드바 푸터 & 컨트롤
    sidebarQuotas:        document.getElementById("sidebar-quotas"),
    watcherPulseDot:      document.getElementById("watcher-pulse-dot"),
    watcherStatusText:    document.getElementById("watcher-status-text"),
    watcherStartBtn:      document.getElementById("watcher-start"),
    watcherStartMsg:      document.getElementById("watcher-start-msg"),
    updateNotice:         document.getElementById("update-notice"),
    updateNoticeText:     document.getElementById("update-notice-text"),
    updateRunBtn:         document.getElementById("update-run-btn"),
    updateRunMsg:         document.getElementById("update-run-msg"),
    autoRefresh:          document.getElementById("autorefresh"),
    refreshBtn:           document.getElementById("refresh"),

    // 상단 탑바
    topbarCategory:       document.getElementById("topbar-category"),
    topbarCurrent:        document.getElementById("topbar-current"),
    topbarCount:          document.getElementById("topbar-count"),
    topbarUpdated:        document.getElementById("topbar-updated"),

    // 메인 뷰 패널들
    viewDashboard:        document.getElementById("view-dashboard"),
    viewQa:               document.getElementById("view-qa"),
    viewHandoff:          document.getElementById("view-handoff"),
    viewStats:            document.getElementById("view-stats"),
    statsQuotasBlock:     document.getElementById("stats-quotas-block"),
    statsQuotasMeta:      document.getElementById("stats-quotas-meta"),
    statsQuotasRefresh:   document.getElementById("stats-quotas-refresh"),
    statsQuotasGrid:      document.getElementById("stats-quotas-grid"),
    usageUpdated:         document.getElementById("usage-updated"),
    usageClientFilter:    document.getElementById("usage-client-filter"),
    usageRefresh:         document.getElementById("usage-refresh"),
    usageMessage:         document.getElementById("usage-message"),
    usageCount:           document.getElementById("usage-count"),
    usageSummary:         document.getElementById("usage-summary"),
    usageModes:           document.getElementById("usage-modes"),
    usageDiagnosticsSection: document.getElementById("usage-diagnostics-section"),
    usageDiagSummary:     document.getElementById("usage-diag-summary"),
    usageDiagUnacked:     document.getElementById("usage-diag-unacked"),
    usageDiagBriefToggle: document.getElementById("usage-diag-brief-toggle"),
    usageDiagCopy:        document.getElementById("usage-diag-copy"),
    usageDiagCounts:      document.getElementById("usage-diag-counts"),
    usageDiagBrief:       document.getElementById("usage-diag-brief"),
    usageDiagGroups:      document.getElementById("usage-diag-groups"),
    usageDiagHandled:     document.getElementById("usage-diag-handled"),
    usageModels:          document.getElementById("usage-models"),
    usageDaily:           document.getElementById("usage-daily"),
    usageRowsCount:       document.getElementById("usage-rows-count"),
    usageLimitsBanner:    document.getElementById("usage-limits-banner"),
    usageRows:            document.getElementById("usage-rows"),
    usageLoadmore:        document.getElementById("usage-loadmore"),
    usageLoadmore50:      document.getElementById("usage-loadmore-50"),
    usageLoadmoreAll:     document.getElementById("usage-loadmore-all"),
    usageLoadmoreInfo:    document.getElementById("usage-loadmore-info"),
    mainScroll:           document.getElementById("main-content-scroll"),

    // 대시보드 내부 엘리먼트
    dashNow:              document.getElementById("dash-now"),
    dashQuotasBlock:      document.getElementById("dash-quotas-block"),
    dashQuotasMeta:       document.getElementById("dash-quotas-meta"),
    dashQuotasRefresh:    document.getElementById("dash-quotas-refresh"),
    dashQuotasGrid:       document.getElementById("dash-quotas-grid"),
    nowStatusText:        document.getElementById("now-status-text"),
    nowAside:             document.getElementById("now-aside"),
    nowTitle:             document.getElementById("now-title"),
    nowMeta:              document.getElementById("now-meta"),
    outcomeStrip:         document.getElementById("outcome-strip"),
    dashAttention:        document.getElementById("dash-attention"),
    dashAttentionCount:   document.getElementById("dash-attention-count"),
    dashTimeline:         document.getElementById("dash-timeline"),
    dashStats:            document.getElementById("dash-stats"),
    btnViewAllQa:         document.getElementById("btn-view-all-qa"),
    btnViewAllHandoff:    document.getElementById("btn-view-all-handoff"),
    modelBarsContainer:   document.getElementById("model-bars-container"),

    // QA 메인 뷰 내부
    qaCurrentSessionTitle: document.getElementById("qa-current-session-title"),
    qaCurrentSessionCount: document.getElementById("qa-current-session-count"),
    qaSearch:             document.getElementById("search"),
    qaSessionChips:       document.getElementById("qa-session-chips"),
    chipQaModels:         document.getElementById("chip-qa-models"),
    chipQaStatus:         document.getElementById("chip-qa-status"),
    chipQaTime:           document.getElementById("chip-qa-time"),
    qaDiagChip:           document.getElementById("qa-diag-chip"),
    cards:                document.getElementById("cards"),
    loadMoreBtn:          document.getElementById("loadmore"),

    // Handoff 메인 뷰 내부
    handoffCurrentProjectTitle: document.getElementById("handoff-current-project-title"),
    handoffCurrentProjectCount: document.getElementById("handoff-current-project-count"),
    handoffSearch:        document.getElementById("handoff-search"),
    handoffBriefCard:    document.getElementById("handoff-brief-card"),
    briefProjectName:     document.getElementById("brief-project-name"),
    handoffBriefContent:  document.getElementById("handoff-brief-content"),
    handoffCards:         document.getElementById("handoff-cards"),
  };

  // 애플리케이션 상태
  var currentNav = "dashboard"; // "dashboard" | "qa" | "handoff" | "stats"
  var usageDays = 7;            // 실측 통계의 기간(7 · 30 · 90일)
  var usageData = null;         // /api/usage-stats 의 마지막 응답
  var usageError = "";
  var usageTimer = null;
  var USAGE_PAGE_SIZE = 50;
  var usageRowsVisibleCount = USAGE_PAGE_SIZE;
  var usageClientFilter = "";
  var usageDiagnosticsData = null;
  var accountQuotasData = null;
  var quotaPollTimer = null;
  var quotaPollCount = 0;
  var quotaRefreshingReq = false;
  var lastQuotaLoadAt = 0;
  var qaSource = "all";         // "all" | "claude" | "agy"
  var currentQaSession = "";    // ""(프로젝트 전체) | 세션 노드 id
  var currentQaProject = "";    // ""(전체 프로젝트) | 프로젝트 노드 id
  var qaChipsExpanded = false;   // agy 세션 칩: 접힌 세션까지 모두 펼쳤는지
  var QA_CHIP_VISIBLE = 8;       // 접은 상태에서 늘 보이는 최근 세션 칩 수(진행 중·선택된 세션은 더 보인다)
  var currentQaAgy = "";        // ""(범위 안의 모든 agy 세션) | "__none__"(@session 없는 단발성) | agy 세션 이름
  var claudeTree = null;        // 마지막으로 받은 /api/claude/tree 응답
  var currentHandoffProject = ""; // ""(전체 프로젝트) | 프로젝트 노드 id
  var currentHandoffSession = ""; // ""(프로젝트 전체) | 세션 노드 id
  var handoffChannels = {};     // 채널 이름 -> /api/handoff/project 응답 ({name, brief, files, messages})

  var allItems = [];            // 전체 완료 QA 레코드
  var pendingItems = [];        // inbox 대기/진행 작업
  var handoffProjects = [];     // 인수인계 프로젝트 목록
  var currentHandoffData = null;// 선택된 프로젝트 상세
  var handoffMessageCache = {}; // 메시지 본문 캐시
  var openHandoffNums = {};     // 열려 있는 메시지 번호
  var expandedMeta = {};        // 식별 줄을 펼친 카드 키(task_id 또는 data-key)
  var metaMoreSeq = 0;          // aria-controls 연결용 고유 id 번호

  var filteredQa = [];          // 필터 적용된 완료 QA
  var filteredPending = [];     // 필터 적용된 pending
  var shownQaCount = 0;         // 현재 렌더링된 카드 수
  var qaSeq = 0;                // 위임 기록 API 에서 마지막으로 받은 갱신 번호
  var lastPendingKey = "";      // pending 변경 감지 키
  var refreshTimer = null;
  var watcherStarting = false;   // 켜기 요청 후 켜질 때까지 true
  var updateStarting = false;    // 업데이트 시작 요청 진행 중
  var updatePollTimer = null;    // 업데이트 진행 중 3초마다 /api/status 확인
  var lastUpdateLatest = "";     // 마지막으로 본 새 버전 문자열(confirm 문구용)
  var isServerOnline = false;
  var hasLoadedStatusOnce = false;
  var systemStatus = null;      // 마지막 /api/status 응답
  var nowTicker = null;         // "지금" 패널 경과 시간 1초 갱신 타이머

  // ==========================================================================
  // HTTP Fetch & Utility
  // ==========================================================================

  function fetchText(url) {
    return fetch(url, { cache: "no-store" }).then(function (res) {
      if (!res.ok) { throw new Error(url + " -> HTTP " + res.status); }
      return res.text();
    });
  }

  function fetchJson(url) {
    return fetchText(url).then(function (t) {
      if (!t) { return null; }
      if (t.charCodeAt(0) === 0xFEFF) { t = t.slice(1); }
      return JSON.parse(t);
    });
  }


  function escapeHtml(str) {
    if (!str) return "";
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function shortClaudeModel(name) {
    if (!name) return "";
    var s = String(name).trim();
    if (s.indexOf("claude-") === 0) {
      return s.slice(7);
    }
    return s;
  }

  // agy 모델 이름을 짧게(전체 이름은 툴팁에): gemini-4-hydrogen-medium -> hydrogen-medium, gemini-4-hydrogen-xhigh -> hydrogen-extra,
  // gemini-4-neon-high -> neon-high, gemini-4-neon-xhigh -> neon-extra, gemini-4-carbon-high -> carbon-high,
  // gemini-pro-orchestrator-neon -> orchestrator-neon, gemini-pro-orchestrator -> orchestrator-carbon,
  // gemini-pro-orchestrator-argon -> orchestrator-argon (예전 g1-pro -> orchestrator, 3.8-flash-medium -> flash-medium).
  // "a -> b" 처럼 시도한 모델을 이은 글은 하나씩 줄인다. 모르는 이름은 그대로.
  function shortAgyModel(name) {
    if (!name) return "";
    var s = String(name).trim();
    if (s.indexOf("->") >= 0) {
      return s.split("->").map(function (x) { return shortAgyModel(x); }).filter(Boolean).join(" → ");
    }
    var mx = s.match(/^gemini-4-(hydrogen|neon|carbon)(?:-tiered)?-xhigh$/i);
    if (mx) return mx[1].toLowerCase() + "-extra";
    var m = s.match(/^gemini-4-(hydrogen|argon|neon|carbon)(?:-tiered)?-(\w+)$/i);
    if (m) return m[1].toLowerCase() + "-" + m[2].toLowerCase();
    if (/^gemini-pro-orchestrator-neon$/i.test(s)) return "orchestrator-neon";
    if (/^gemini-pro-orchestrator$/i.test(s)) return "orchestrator-carbon";
    if (/^gemini-pro-orchestrator-argon$/i.test(s)) return "orchestrator-argon";
    if (/^gemini-pro-orchestrator/i.test(s)) return "orchestrator";
    m = s.match(/^gemini-\d+(?:\.\d+)?-(flash|pro|lite)-(\w+)$/i);
    if (m) return m[1].toLowerCase() + "-" + m[2].toLowerCase();
    return s;
  }

  // agy 모델 없이 호출자 쪽(Claude · Antigravity · 서브에이전트) 모델만 그린다. 뒤에 붙던 "→" 는 없다.
  function claudeOnlyModelHtml(claudeModel, claudeEffort, subAgent, srcInfo) {
    var parts = [];
    if (claudeModel) {
      var cShort = escapeHtml(shortClaudeModel(claudeModel) + (claudeEffort ? " (" + String(claudeEffort).toLowerCase() + ")" : ""));
      var cTitle = "이 위임을 보낸 Claude 모델: " + claudeModel + (claudeEffort ? " (effort " + claudeEffort + ")" : "");
      parts.push('<span class="dim" title="' + escapeHtml(cTitle) + '">' + cShort + '</span>');
    } else if (srcInfo && (srcInfo.model || srcInfo.client)) {
      var sModelOnly = srcInfo.model ? String(srcInfo.model) : "";
      var sEffortOnly = srcInfo.effort ? String(srcInfo.effort) : "";
      var sClientOnly = srcInfo.client ? String(srcInfo.client) : "";
      var sClientDispOnly = sClientOnly.toLowerCase() === "antigravity" ? "Antigravity" : sClientOnly;
      if (sModelOnly) {
        var sBaseOnly = /^claude-/i.test(sModelOnly) ? shortClaudeModel(sModelOnly) : shortAgyModel(sModelOnly);
        var sShortOnly = escapeHtml(sBaseOnly + (sEffortOnly ? " (" + sEffortOnly.toLowerCase() + ")" : ""));
        var sTitleOnly = "이 위임을 보낸 " + (sClientDispOnly || "호출") + " 모델: " + sModelOnly + (sEffortOnly ? " (effort " + sEffortOnly + ")" : "");
        parts.push('<span class="dim" title="' + escapeHtml(sTitleOnly) + '">' + sShortOnly + '</span>');
      } else if (sClientDispOnly) {
        parts.push('<span class="dim" title="' + escapeHtml("이 위임을 보낸 클라이언트: " + sClientDispOnly) + '">' + escapeHtml(sClientDispOnly) + '</span>');
      }
    }
    var aModel = subAgent && subAgent.model ? String(subAgent.model) : "";
    if (aModel) {
      var aEffort = subAgent.effort ? String(subAgent.effort) : "";
      var aType = subAgent.type ? String(subAgent.type) : "";
      var aDesc = subAgent.desc ? String(subAgent.desc) : "";
      var aShort = escapeHtml(shortClaudeModel(aModel) + (aEffort ? " (" + aEffort.toLowerCase() + ")" : ""));
      var aParts = [aModel + (aEffort ? " (effort " + aEffort + ")" : "")];
      if (aType) aParts.push(aType);
      if (aDesc) aParts.push(aDesc);
      parts.push('<span class="dim" title="' + escapeHtml("위임을 보낸 서브에이전트: " + aParts.join(" · ")) + '">서브 ' + aShort + '</span>');
    }
    return parts.join(' › ');
  }

  function cardModelHtml(agyModel, claudeModel, claudeEffort, fellBack, subAgent, triedModels, isOk, models, srcInfo) {
    var aModelEarly = subAgent && subAgent.model ? String(subAgent.model) : "";
    var hasSrcEarly = Boolean(!claudeModel && srcInfo && (srcInfo.model || srcInfo.client));
    // agy 모델이 비어 있는 기록(옛 취소 기록 등)도 호출자 쪽 모델이 있으면 그 부분만 보여 준다.
    if (!agyModel && !claudeModel && !aModelEarly && !hasSrcEarly) return "";
    if (!agyModel) return claudeOnlyModelHtml(claudeModel, claudeEffort, subAgent, srcInfo);
    var full = String(agyModel);
    var agyStr = '<span title="' + escapeHtml(full) + '">' + escapeHtml(shortAgyModel(full)) + '</span>';
    // 실제로 돈 모델별 분배: 모델이 2개 이상이거나, 단일 모델의 짧은 이름이 표시된 agy 모델과 다를 때(오케스트레이터·폴백 등)만 덧붙인다.
    // 모델 줄에는 짧은 이름만 토큰 내림차순으로 두고, 모델별 세부 숫자는 툴팁과 토큰 블록에 둔다.
    var splitStr = "";
    if (Array.isArray(models) && models.length > 0) {
      var validModels = models.filter(function (m) { return m && m.model; }).slice();
      validModels.sort(function (a, b) {
        var diff = (Number(b.total) || 0) - (Number(a.total) || 0);
        return diff !== 0 ? diff : String(a.model).localeCompare(String(b.model));
      });
      var shownShort = shortAgyModel(full);
      var showSplit = validModels.length >= 2 || (validModels.length === 1 && shortAgyModel(validModels[0].model) !== shownShort);
      if (showSplit) {
        var fmtNum = function (v) { return Number(v || 0).toLocaleString("en-US"); };
        var splitParts = validModels.map(function (m) {
          return shortAgyModel(m.model);
        });
        var titleLines = ["실제로 돈 모델별 토큰(입력+출력, agy 대화 기록 기준)"];
        validModels.forEach(function (m) {
          var thk = Number(m.thinking) || 0;
          titleLines.push(
            String(m.model) + ": 입력 " + fmtNum(m.input) + " · 캐시 " + fmtNum(m.cache) +
            " · 출력 " + fmtNum(m.output) + (thk > 0 ? " (사고 " + fmtNum(thk) + ")" : "") + " · 단계 " + fmtNum(m.steps)
          );
        });
        splitStr = ' <span class="model-split dim" title="' + escapeHtml(titleLines.join("\n")) + '">(' + escapeHtml(splitParts.join(" · ")) + ')</span>';
      }
    }
    var chainStr = "";
    if (isOk !== false && triedModels) {
      var rawChain = String(triedModels).split("->").map(function (s) { return s.trim(); }).filter(Boolean);
      if (rawChain.length > 1) {
        var usedIdx = rawChain.indexOf(full);
        if (usedIdx < 0) {
          var shortFull = shortAgyModel(full);
          for (var ci = 0; ci < rawChain.length; ci++) {
            if (shortAgyModel(rawChain[ci]) === shortFull) { usedIdx = ci; break; }
          }
        }
        var failedList = (usedIdx >= 0) ? rawChain.slice(0, usedIdx) : rawChain.slice(0, -1);
        chainStr = failedList.map(function (m) {
          var title = "한도 · 과부하로 실패해 다음 모델로 넘어갔습니다: " + m;
          return '<span class="agy-failed" title="' + escapeHtml(title) + '">' + escapeHtml(shortAgyModel(m)) + ' ✕</span> → ';
        }).join("");
      }
    }
    var aModel = subAgent && subAgent.model ? String(subAgent.model) : "";
    var hasSrc = Boolean(!claudeModel && srcInfo && (srcInfo.model || srcInfo.client));
    if (!claudeModel && !aModel && !hasSrc) return chainStr + agyStr + splitStr;
    var prefix = "";
    if (claudeModel) {
      var cShort = escapeHtml(shortClaudeModel(claudeModel) + (claudeEffort ? " (" + String(claudeEffort).toLowerCase() + ")" : ""));
      var cTitle = "이 위임을 보낸 Claude 모델: " + claudeModel + (claudeEffort ? " (effort " + claudeEffort + ")" : "");
      prefix += '<span class="dim" title="' + escapeHtml(cTitle) + '">' + cShort + (aModel ? ' › ' : ' → ') + '</span>';
    } else if (hasSrc) {
      var sModel = srcInfo.model ? String(srcInfo.model) : "";
      var sEffort = srcInfo.effort ? String(srcInfo.effort) : "";
      var sClient = srcInfo.client ? String(srcInfo.client) : "";
      var sClientDisp = sClient.toLowerCase() === "antigravity" ? "Antigravity" : sClient;
      if (sModel) {
        var sBase = /^claude-/i.test(sModel) ? shortClaudeModel(sModel) : shortAgyModel(sModel);
        var sShort = escapeHtml(sBase + (sEffort ? " (" + sEffort.toLowerCase() + ")" : ""));
        var sTitle = "이 위임을 보낸 " + (sClientDisp || "호출") + " 모델: " + sModel + (sEffort ? " (effort " + sEffort + ")" : "");
        prefix += '<span class="dim" title="' + escapeHtml(sTitle) + '">' + sShort + (aModel ? ' › ' : ' → ') + '</span>';
      } else if (sClientDisp) {
        prefix += '<span class="dim" title="' + escapeHtml("이 위임을 보낸 클라이언트: " + sClientDisp) + '">' + escapeHtml(sClientDisp) + (aModel ? ' › ' : ' → ') + '</span>';
      }
    }
    if (aModel) {
      var aEffort = subAgent.effort ? String(subAgent.effort) : "";
      var aType = subAgent.type ? String(subAgent.type) : "";
      var aDesc = subAgent.desc ? String(subAgent.desc) : "";
      var aShort = escapeHtml(shortClaudeModel(aModel) + (aEffort ? " (" + aEffort.toLowerCase() + ")" : ""));
      var aParts = [aModel + (aEffort ? " (effort " + aEffort + ")" : "")];
      if (aType) aParts.push(aType);
      if (aDesc) aParts.push(aDesc);
      var aTitle = "위임을 보낸 서브에이전트: " + aParts.join(" · ");
      prefix += '<span class="dim" title="' + escapeHtml(aTitle) + '">서브 ' + aShort + ' → </span>';
    }
    return prefix + chainStr + agyStr + splitStr;
  }

  function buildCardModelMeta(agyModel, claudeModel, claudeEffort, fellBack, subAgent, triedModels, isOk, models, srcInfo) {
    var item = labeledMeta("", "", "model", "모델");
    var mv = item.querySelector(".mv");
    if (mv) {
      mv.innerHTML = cardModelHtml(agyModel, claudeModel, claudeEffort, fellBack, subAgent, triedModels, isOk, models, srcInfo);
    }
    return item;
  }

  // index.html 의 <symbol id="i-..."> 아이콘을 참조하는 SVG 마크업
  function icon(name) {
    return '<svg class="icon" aria-hidden="true"><use href="#i-' + name + '"/></svg>';
  }

  // 클릭으로만 동작하던 div 항목을 키보드(Tab, Enter, Space)로도 쓸 수 있게 한다.
  function makeActivatable(el, label) {
    el.tabIndex = 0;
    el.setAttribute("role", "button");
    if (label) el.setAttribute("aria-label", label);
  }

  function parseLocalTime(dateStr) {
    if (!dateStr) return null;
    var d = new Date(String(dateStr).replace(/-/g, "/"));
    return isNaN(d.getTime()) ? null : d;
  }

  function pad2(n) { return (n < 10 ? "0" : "") + n; }

  // 오늘이면 "14:05", 아니면 "09-22"
  function formatClock(dateStr) {
    var d = parseLocalTime(dateStr);
    if (!d) return "";
    var now = new Date();
    if (d.toDateString() === now.toDateString()) {
      return pad2(d.getHours()) + ":" + pad2(d.getMinutes());
    }
    return pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
  }

  function formatDuration(sec) {
    sec = Math.max(0, Math.floor(sec));
    if (sec < 60) return sec + "초";
    var m = Math.floor(sec / 60);
    var s = sec % 60;
    if (m < 60) return m + "분 " + pad2(s) + "초";
    return Math.floor(m / 60) + "시간 " + pad2(m % 60) + "분";
  }

  function localDateKey(d) {
    return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
  }

  // 기록의 모델명. 실패 기록은 model 이 빈 문자열이라, 시도한 모델(tried_models)로 대신한다.
  function recordModel(r) {
    if (!r) return "";
    var m = r.model ? String(r.model).trim() : "";
    if (m && m !== "(session)") return m;
    return r.tried_models ? String(r.tried_models).trim() : "";
  }

  // 위임 결과 상태가 성공인가. 기록(객체)이나 상태 글자를 받는다. OK · success · 성공(앞뒤 공백, 대소문자 무시)을 성공으로 본다.
  function isOkStatus(s) {
    if (s == null) return false;
    var raw = (typeof s === "object" && "status" in s) ? s.status : s;
    if (raw == null) return false;
    var str = String(raw).trim();
    if (str === "성공") return true;
    var lower = str.toLowerCase();
    return lower === "ok" || lower === "success";
  }


  function pendingKeyOf(list) {
    if (!list || !list.length) { return ""; }
    return list.map(function (p) {
      var pg = p.progress || {};
      var tok = (pg.tokens && pg.tokens.total) ? pg.tokens.total : 0;
      var cu = p.claude_usage || {};
      var cuM = (cu.main && cu.main.total) ? cu.main.total : 0;
      var cuS = (cu.sub && cu.sub.total) ? cu.sub.total : 0;
      return [
        p.task_id || "",
        p.state || "",
        p.model || "",
        p.started_at || "",
        pg.step != null ? pg.step : "",
        pg.last_activity_ms || "",
        tok,
        cuM,
        cuS,
        p.probe_state || "",
        p.ask_count || 0,
        p.interrupted ? 1 : 0
      ].join(":");
    }).join(",");
  }

  // nowMs 는 시험에서 기준 시각을 고정하려는 선택 인자다(없으면 지금).
  function formatRelativeTime(dateStr, nowMs) {
    if (!dateStr) return "-";
    try {
      var d = new Date(dateStr.replace(/-/g, "/"));
      if (isNaN(d.getTime())) return dateStr;
      var nowTime = (nowMs == null) ? Date.now() : nowMs;
      var diffSec = Math.floor((nowTime - d.getTime()) / 1000);
      if (diffSec < 60) return "방금 전";
      if (diffSec < 3600) return Math.floor(diffSec / 60) + "분 전";
      if (diffSec < 86400) return Math.floor(diffSec / 3600) + "시간 전";
      return Math.floor(diffSec / 86400) + "일 전";
    } catch (e) {
      return dateStr;
    }
  }

  // ==========================================================================
  // Router & Navigation Logic
  // ==========================================================================

  // 화면 이동(메뉴·프로젝트·세션 선택)은 브라우저 기록에 쌓아 뒤로가기가 이전 화면으로 가게 한다.
  // 뒤로/앞으로를 처리하는 동안에는 기록을 더 쌓지 않고 현재 항목만 고친다(앞으로 기록을 지우지 않으려고).
  var hashRouting = false;

  // 브라우저 기본 스크롤 복원 끄기 (화면별 복원 로직과 충돌 방지)
  try {
    if (typeof history !== "undefined" && "scrollRestoration" in history) {
      history.scrollRestoration = "manual";
    }
  } catch (e) {}

  // 화면별 스크롤 위치 저장 맵 (해시 기준) 및 복원 상태
  var scrollPositions = {};
  var lastKnownHash = (typeof window !== "undefined" && window.location && window.location.hash) ? window.location.hash : "#/dashboard";
  var lastHandledHash = lastKnownHash;
  var activeRestore = null;
  var isProgrammaticScroll = false;
  var programmaticScrollTimer = null;

  function getScrollContainer() {
    if (typeof els !== "undefined" && els && els.mainScroll) {
      return els.mainScroll;
    }
    if (typeof document !== "undefined" && document.getElementById) {
      var el = document.getElementById("main-content-scroll");
      if (el) return el;
    }
    if (typeof window !== "undefined") {
      return window;
    }
    return null;
  }

  function getScrollTop(container) {
    var c = container || getScrollContainer();
    if (!c) return 0;
    if (typeof c.scrollTop === "number") return c.scrollTop;
    if (typeof c.scrollY === "number") return c.scrollY;
    if (typeof c.pageYOffset === "number") return c.pageYOffset;
    if (c.document && c.document.documentElement && typeof c.document.documentElement.scrollTop === "number") {
      return c.document.documentElement.scrollTop;
    }
    return 0;
  }

  function setScrollTop(pos, container) {
    var c = container || getScrollContainer();
    if (!c) return;
    var top = Math.max(0, Math.floor(pos || 0));
    if (typeof c.scrollTop === "number") {
      c.scrollTop = top;
    }
    if (typeof c.scrollTo === "function") {
      try {
        c.scrollTo(0, top);
      } catch (e) {
        try { c.scrollTo({ top: top, behavior: "auto" }); } catch (e2) {}
      }
    } else if (typeof c.scrollY === "number") {
      c.scrollY = top;
    }
    if (c.document && c.document.documentElement && typeof c.document.documentElement.scrollTop === "number") {
      c.document.documentElement.scrollTop = top;
    }
  }

  function normalizeHash(h) {
    if (!h || typeof h !== "string") return "#/dashboard";
    var idx = h.indexOf("#");
    if (idx < 0) return "#/dashboard";
    var sub = h.slice(idx);
    return sub || "#/dashboard";
  }

  function saveCurrentScroll(explicitHash, explicitPos) {
    var h = explicitHash || lastKnownHash;
    if (!h && typeof window !== "undefined" && window.location) {
      h = window.location.hash;
    }
    var key = normalizeHash(h);
    var top = (typeof explicitPos === "number") ? explicitPos : getScrollTop();
    scrollPositions[key] = top;
    try {
      if (typeof sessionStorage !== "undefined") {
        sessionStorage.setItem("samjil_scroll_" + key, String(top));
      }
    } catch (e) {}
    try {
      if (typeof history !== "undefined" && history.replaceState) {
        var st = (history.state && typeof history.state === "object") ? history.state : {};
        st.scrollTop = top;
        st.scrollHash = key;
        history.replaceState(st, "");
      }
    } catch (e) {}
    return top;
  }

  function getSavedScroll(hash) {
    var key = normalizeHash(hash);
    if (typeof scrollPositions[key] === "number") {
      return scrollPositions[key];
    }
    try {
      if (typeof sessionStorage !== "undefined") {
        var val = sessionStorage.getItem("samjil_scroll_" + key);
        if (val !== null) {
          var num = parseInt(val, 10);
          if (!isNaN(num)) return num;
        }
      }
    } catch (e) {}
    try {
      if (typeof history !== "undefined" && history.state && typeof history.state === "object") {
        if (history.state.scrollHash === key && typeof history.state.scrollTop === "number") {
          return history.state.scrollTop;
        }
      }
    } catch (e) {}
    return 0;
  }

  function cancelPendingRestore() {
    if (activeRestore) {
      if (activeRestore.rafId && typeof cancelAnimationFrame === "function") {
        cancelAnimationFrame(activeRestore.rafId);
      }
      if (activeRestore.timerId) {
        clearTimeout(activeRestore.timerId);
      }
      activeRestore = null;
    }
  }

  function handleUserScrollAttempt() {
    if (activeRestore) {
      cancelPendingRestore();
    }
  }

  function restoreScrollForHash(hash, container) {
    cancelPendingRestore();
    var c = container || getScrollContainer();
    if (!c) return;

    var targetTop = getSavedScroll(hash);
    if (!targetTop || targetTop <= 0) {
      setScrollTop(0, c);
      return;
    }

    var startTime = Date.now();
    var maxDuration = 2000;

    activeRestore = {
      hash: normalizeHash(hash),
      target: targetTop,
      container: c,
      startTime: startTime,
      rafId: null,
      timerId: null
    };

    function markProgrammatic() {
      isProgrammaticScroll = true;
      if (programmaticScrollTimer) {
        clearTimeout(programmaticScrollTimer);
      }
      programmaticScrollTimer = setTimeout(function () {
        isProgrammaticScroll = false;
        programmaticScrollTimer = null;
      }, 50);
    }

    function attempt() {
      if (!activeRestore || activeRestore.container !== c) return;

      markProgrammatic();
      setScrollTop(targetTop, c);

      var cur = getScrollTop(c);
      if (Math.abs(cur - targetTop) <= 1) {
        activeRestore = null;
        return;
      }

      if (Date.now() - startTime >= maxDuration) {
        activeRestore = null;
        return;
      }

      if (typeof requestAnimationFrame === "function") {
        activeRestore.rafId = requestAnimationFrame(attempt);
      } else {
        activeRestore.timerId = setTimeout(attempt, 25);
      }
    }

    attempt();
  }

  function parseHash() {
    var hash = window.location.hash || "#/dashboard";
    var qIdx = hash.indexOf("?");
    var path = qIdx >= 0 ? hash.slice(0, qIdx) : hash;
    var qs = qIdx >= 0 ? hash.slice(qIdx + 1) : "";
    var params = {};
    if (qs) {
      qs.split("&").forEach(function (part) {
        if (!part) return;
        var eqIdx = part.indexOf("=");
        var k = eqIdx >= 0 ? part.slice(0, eqIdx) : part;
        var v = eqIdx >= 0 ? part.slice(eqIdx + 1) : "";
        try {
          params[decodeURIComponent(k)] = decodeURIComponent(v);
        } catch (e) {
          params[k] = v;
        }
      });
    }

    if (path === "#/qa") {
      return { nav: "qa", session: params.session || "", project: params.project || "", agy: params.agy || "", task: params.task || "" };
    }
    if (path === "#/stats") {
      return { nav: "stats", session: "", project: "" };
    }
    return { nav: "dashboard", session: "", project: "" };
  }

  function updateHash(replace) {
    var newHash = "#/" + currentNav;
    if (currentNav === "qa") {
      var parts = [];
      if (currentQaProject) {
        parts.push("project=" + encodeURIComponent(currentQaProject));
      }
      if (currentQaSession) {
        parts.push("session=" + encodeURIComponent(currentQaSession));
      }
      if (currentQaAgy) {
        parts.push("agy=" + encodeURIComponent(currentQaAgy));
      }
      if (parts.length > 0) {
        newHash += "?" + parts.join("&");
      }
    }
    if (window.location.hash !== newHash) {
      if (typeof saveCurrentScroll === "function") {
        saveCurrentScroll(lastKnownHash);
      }
      if (typeof lastKnownHash !== "undefined") {
        lastKnownHash = newHash;
      }
      if (typeof lastHandledHash !== "undefined") {
        lastHandledHash = newHash;
      }
      if (replace === true || hashRouting) {
        history.replaceState(null, "", newHash);
      } else {
        history.pushState(null, "", newHash);
        if (typeof cancelPendingRestore === "function") {
          cancelPendingRestore();
        }
        if (typeof setScrollTop === "function") {
          setScrollTop(0);
        }
      }
    }
  }

  function switchNav(nav, updateUrl) {
    if (nav !== "dashboard" && nav !== "qa" && nav !== "stats") {
      nav = "dashboard";
    }

    if (!hashRouting && updateUrl !== false && typeof saveCurrentScroll === "function") {
      saveCurrentScroll(lastKnownHash);
    }

    currentNav = nav;

    // 1차 네비게이션 버튼 활성화
    [els.navBtnDashboard, els.navBtnQa, els.navBtnStats].forEach(function (btn) {
      if (btn) {
        var isActive = (btn.dataset.nav === nav);
        btn.classList.toggle("active", isActive);
        btn.setAttribute("aria-selected", isActive ? "true" : "false");
      }
    });

    // 2차 서브 패널 전환
    if (els.subDashboard) els.subDashboard.style.display = ((nav === "dashboard" || nav === "stats") ? "flex" : "none");
    if (els.subQa) els.subQa.style.display = (nav === "qa" ? "flex" : "none");

    // 메인 뷰 전환
    if (els.viewDashboard) els.viewDashboard.style.display = (nav === "dashboard" ? "block" : "none");
    if (els.viewQa) els.viewQa.style.display = (nav === "qa" ? "block" : "none");
    if (els.viewStats) els.viewStats.style.display = (nav === "stats" ? "block" : "none");

    // 상단 브레드크럼 및 상태 갱신
    updateBreadcrumbs();
    updateTopbarMeta();

    if (updateUrl !== false) {
      updateHash();
      if (typeof cancelPendingRestore === "function") {
        cancelPendingRestore();
      }
      if (typeof setScrollTop === "function") {
        setScrollTop(0);
      }
    }

    try {
      localStorage.setItem("samjil_active_nav", nav);
    } catch (e) {}

    // 모바일에서 메뉴 선택 시 사이드바 닫기
    if (window.innerWidth <= 768 && els.appSidebar) {
      els.appSidebar.classList.remove("open");
    }

    // 뷰 전환에 따른 렌더링 호출
    if (nav !== "dashboard") { stopNowTicker(); }
    if (nav === "dashboard") {
      renderDashboard();
    } else if (nav === "qa") {
      applyQaFilters();
    }
    if (typeof enterOrLeaveUsageStats === "function") {
      enterOrLeaveUsageStats(nav === "stats");
    }
  }

  function updateBreadcrumbs() {
    if (!els.topbarCategory || !els.topbarCurrent) return;

    if (currentNav === "dashboard") {
      els.topbarCategory.textContent = "홈";
      els.topbarCurrent.textContent = "대시보드";
    } else if (currentNav === "qa") {
      els.topbarCategory.textContent = "에이전트 위임";
      if (!currentQaProject) {
        els.topbarCurrent.textContent = "전체 프로젝트 피드";
      } else {
        var tree = buildQaTree(allItems, pendingItems, claudeTree);
        var titles = findQaNodeTitles(tree, currentQaProject, currentQaSession);
        if (!currentQaSession) {
          els.topbarCurrent.textContent = titles.projectName;
        } else {
          els.topbarCurrent.textContent = titles.projectName + " / " + titles.sessionTitle;
        }
      }
    } else if (currentNav === "stats") {
      els.topbarCategory.textContent = "실측 통계";
      els.topbarCurrent.textContent = "최근 " + usageDays + "일";
    }
  }

  function updateTopbarMeta() {
    if (!els.topbarCount || !els.topbarUpdated) return;

    if (currentNav === "dashboard") {
      els.topbarCount.textContent = "총 " + allItems.length + "건 위임";
    } else if (currentNav === "qa") {
      var count = filteredQa.length + filteredPending.length;
      var srcTotal = qaSource === "all"
        ? allItems.length
        : allItems.filter(function (r) { return qaSource === "agy" ? qaIsAgyItem(r) : !qaIsAgyItem(r); }).length;
      var srcLabel = qaSource === "agy" ? "Antigravity " : (qaSource === "claude" ? "Claude " : "");
      els.topbarCount.textContent = srcLabel + count + "건 표시 중 (전체 " + srcTotal + "건)";
    } else if (currentNav === "stats") {
      els.topbarCount.textContent = "질문 " + ((usageData && usageData.summary) ? usageData.summary.total : 0) + "건";
    }

    var t = new Date();
    els.topbarUpdated.textContent = pad2(t.getHours()) + ":" + pad2(t.getMinutes()) + ":" + pad2(t.getSeconds()) + " 갱신";
  }

  // ==========================================================================
  // Data Loaders
  // ==========================================================================

  // 시스템 런타임 상태 로드 (/api/status)
  function loadSystemStatus() {
    return fetchJson("/api/status")
      .then(function (status) {
        hasLoadedStatusOnce = true;
        isServerOnline = true;
        systemStatus = status;
        if (status) {
          var isWatcherAlive = Boolean(status.watcherAlive);
          if (els.watcherPulseDot) {
            els.watcherPulseDot.classList.toggle("offline", !isWatcherAlive);
          }
          if (els.watcherStatusText) {
            els.watcherStatusText.textContent = isWatcherAlive
              ? "agy 워처 켜짐"
              : (status.manualStop ? "agy 워처 꺼짐 (수동 정지)" : "agy 워처 꺼짐");
          }
        }
        updateWatcherStartButton(status);
        updateVersionNotice(status);
        return status;
      })
      .catch(function () {
        hasLoadedStatusOnce = true;
        isServerOnline = false;
        systemStatus = null;
        if (els.watcherPulseDot) els.watcherPulseDot.classList.add("offline");
        if (els.watcherStatusText) {
          els.watcherStatusText.textContent = "뷰어 서버 연결 끊김";
        }
        updateWatcherStartButton(null);
        updateVersionNotice(null);
        return null;
      });
  }

  function showUpdateRunMsg(text, isError) {
    if (!els.updateRunMsg) return;
    els.updateRunMsg.textContent = text || "";
    els.updateRunMsg.classList.toggle("is-error", Boolean(isError));
    els.updateRunMsg.hidden = !text;
  }

  function syncUpdatePoll(isRunning) {
    if (isRunning) {
      if (!updatePollTimer) {
        updatePollTimer = setTimeout(function () {
          updatePollTimer = null;
          loadSystemStatus();
        }, 3000);
      }
    } else if (updatePollTimer) {
      clearTimeout(updatePollTimer);
      updatePollTimer = null;
    }
  }

  function updateVersionNotice(status) {
    if (!els.updateNotice) return;
    var u = status && status.update;
    var run = u && u.run ? u.run : null;
    var runState = run && run.state ? String(run.state) : "";
    var runMessage = run && run.message ? String(run.message) : "";
    var isRunning = (runState === "running") || updateStarting;
    if (u && u.latest) {
      lastUpdateLatest = String(u.latest);
    }

    var showNotice = Boolean((u && u.available && (u.latest || isRunning)) || isRunning);
    var textTarget = els.updateNoticeText || els.updateNotice;
    if (showNotice) {
      var labelLatest = (u && u.latest) ? String(u.latest) : lastUpdateLatest;
      textTarget.textContent = labelLatest ? ("새 버전 " + labelLatest + " 설치 가능") : "새 버전 업데이트 진행 중";
      var tip = "설치본 " + ((u && u.installed) || "");
      textTarget.title = tip;
      els.updateNotice.title = tip;
      els.updateNotice.hidden = false;
      if (els.updateRunBtn) {
        if (isRunning) {
          els.updateRunBtn.disabled = true;
          els.updateRunBtn.textContent = "업데이트 중…";
          els.updateRunBtn.setAttribute("aria-busy", "true");
        } else {
          els.updateRunBtn.disabled = false;
          els.updateRunBtn.textContent = "업데이트";
          els.updateRunBtn.removeAttribute("aria-busy");
        }
      }
    } else {
      textTarget.textContent = "";
      textTarget.title = "";
      els.updateNotice.title = "";
      els.updateNotice.hidden = true;
      if (els.updateRunBtn) {
        els.updateRunBtn.disabled = false;
        els.updateRunBtn.textContent = "업데이트";
        els.updateRunBtn.removeAttribute("aria-busy");
      }
    }

    if (runState === "running") {
      showUpdateRunMsg(runMessage || "업데이트를 진행하고 있습니다…", false);
    } else if (runState === "done") {
      showUpdateRunMsg("업데이트 완료. 뷰어 서버를 다시 시작하면 새 코드가 적용됩니다", false);
    } else if (runState === "failed") {
      var failText = (runMessage ? (runMessage + " · ") : "") + "로그: ~/.samjil/cache/update-run.log";
      showUpdateRunMsg(failText, true);
    }

    syncUpdatePoll(runState === "running");
  }

  function startUpdate() {
    if (updateStarting) return;
    var u = systemStatus && systemStatus.update;
    var latest = (u && u.latest) ? String(u.latest) : lastUpdateLatest;
    var confirmText = "새 버전 " + (latest || "") + " 로 업데이트합니다. 위임 워처가 다시 시작될 수 있습니다. 진행할까요?";
    if (typeof window !== "undefined" && typeof window.confirm === "function") {
      if (!window.confirm(confirmText)) return;
    }
    updateStarting = true;
    showUpdateRunMsg("", false);
    if (els.updateRunBtn) {
      els.updateRunBtn.disabled = true;
      els.updateRunBtn.textContent = "업데이트 중…";
      els.updateRunBtn.setAttribute("aria-busy", "true");
    }
    fetch("/api/update/start", { method: "POST", headers: { "X-Samjil-Viewer": "1" } })
      .then(function (r) {
        return r.json().then(function (body) { return { ok: r.ok, body: body }; });
      })
      .then(function (res) {
        updateStarting = false;
        if (!res.ok || !res.body) { throw new Error("서버가 요청을 받지 않았습니다"); }
        var result = res.body.result;
        var msg = res.body.message || "";
        if (result === "started" || result === "running") {
          showUpdateRunMsg(msg || "업데이트를 시작했습니다.", false);
          syncUpdatePoll(true);
          loadSystemStatus();
          return;
        }
        if (result === "none") {
          showUpdateRunMsg(msg || "업데이트할 새 버전이 없습니다", false);
          updateVersionNotice(systemStatus);
          return;
        }
        showUpdateRunMsg((msg || "업데이트를 시작하지 못했습니다.") + " · 로그: ~/.samjil/cache/update-run.log", true);
        updateVersionNotice(systemStatus);
      })
      .catch(function (err) {
        updateStarting = false;
        showUpdateRunMsg("업데이트를 시작하지 못했습니다: " + err.message, true);
        updateVersionNotice(systemStatus);
      });
  }

  // 켜기 버튼: 워처가 꺼져 있고 서버가 켜 줄 수 있을 때만 보인다. 켜는 중에는 켜질 때까지 남겨 둔다.
  function updateWatcherStartButton(status) {
    if (!els.watcherStartBtn) return;
    var canShow = Boolean(status) && !status.watcherAlive && status.canStart === true;
    els.watcherStartBtn.hidden = !(canShow || watcherStarting);
  }

  function showWatcherStartMsg(text, isError) {
    if (!els.watcherStartMsg) return;
    els.watcherStartMsg.textContent = text || "";
    els.watcherStartMsg.classList.toggle("is-error", Boolean(isError));
    els.watcherStartMsg.hidden = !text;
  }

  function finishWatcherStart() {
    watcherStarting = false;
    if (els.watcherStartBtn) {
      els.watcherStartBtn.disabled = false;
      els.watcherStartBtn.textContent = "켜기";
      els.watcherStartBtn.removeAttribute("aria-busy");
    }
    updateWatcherStartButton(systemStatus);
  }

  // 켜졌는지 2초마다 확인한다. 워처가 PID 잠금 파일을 쓰기까지 몇 초 걸린다.
  function waitForWatcherAlive() {
    var deadline = Date.now() + 30000;
    return new Promise(function (resolve) {
      (function poll() {
        loadSystemStatus().then(function (st) {
          if (st && st.watcherAlive) { finishWatcherStart(); refresh(false); resolve(); return; }
          if (Date.now() > deadline) {
            showWatcherStartMsg("30초 안에 켜지지 않았습니다. runtime/logs/watcher.log를 확인하세요.", true);
            finishWatcherStart();
            resolve();
            return;
          }
          setTimeout(poll, 2000);
        });
      })();
    });
  }

  function startWatcher() {
    if (watcherStarting) return;
    watcherStarting = true;
    showWatcherStartMsg("", false);
    if (els.watcherStartBtn) {
      els.watcherStartBtn.disabled = true;
      els.watcherStartBtn.textContent = "켜는 중…";
      els.watcherStartBtn.setAttribute("aria-busy", "true");
    }
    // 전용 헤더가 있어야 서버가 받는다(다른 웹 페이지의 몰래 요청 차단)
    fetch("/api/watcher/start", { method: "POST", headers: { "X-Samjil-Viewer": "1" } })
      .then(function (r) {
        return r.json().then(function (body) { return { ok: r.ok, body: body }; });
      })
      .then(function (res) {
        if (!res.ok || !res.body) { throw new Error("서버가 요청을 받지 않았습니다"); }
        var result = res.body.result;
        if (result === "no-script" || result === "failed") {
          showWatcherStartMsg(res.body.message, true);
          finishWatcherStart();
          return null;
        }
        if (result === "already-running") { finishWatcherStart(); refresh(false); return null; }
        return waitForWatcherAlive();   // started, busy
      })
      .catch(function (err) {
        showWatcherStartMsg("켜지 못했습니다: " + err.message, true);
        finishWatcherStart();
      });
  }

  // 위임 inbox 대기열 목록 로드
  function loadPending() {
    return fetchJson("/api/delegate/pending")
      .then(function (data) {
        return Array.isArray(data) ? data : [];
      })
      .catch(function () {
        return [];
      });
  }

  // 위임 완료 레코드 로드: 뷰어 API(/api/qa/records)에서 마지막으로 받은 갱신 번호(qaSeq) 이후의 기록만 받아 합친다.
  // 처음(또는 강제 새로고침)에는 since=0 으로 전부 받는다. 받은 건수가 서버의 전체 건수와 어긋나면(오래된 기록이 지워짐 등) 처음부터 다시 받는다.
  // task_id 가 같은 기록은 새것으로 바꿔 합친 새 배열을 돌려준다(원본은 바꾸지 않는다).
  function mergeQaRecords(base, incoming) {
    var byId = {};
    var order = [];
    base.forEach(function (r) {
      if (!Object.prototype.hasOwnProperty.call(byId, r.task_id)) { order.push(r.task_id); }
      byId[r.task_id] = r;
    });
    incoming.forEach(function (r) {
      if (!Object.prototype.hasOwnProperty.call(byId, r.task_id)) { order.push(r.task_id); }
      byId[r.task_id] = r;
    });
    return order.map(function (id) { return byId[id]; });
  }

  function loadAllQa(force) {
    var since = (force || allItems.length === 0) ? 0 : qaSeq;
    return fetchJson("/api/qa/records?since=" + since).then(function (res) {
      var recs = (res && Array.isArray(res.records)) ? res.records : [];
      var total = (res && typeof res.total === "number") ? res.total : recs.length;
      var incomingLimits = (res && res.limits && typeof res.limits === "object") ? res.limits : null;
      var limitsChanged = false;
      if (incomingLimits || (since === 0 && windowLimits !== null)) {
        limitsChanged = JSON.stringify(incomingLimits) !== JSON.stringify(windowLimits);
        windowLimits = incomingLimits;
      }
      var items = (since === 0) ? recs : mergeQaRecords(allItems, recs);

      if (since > 0 && items.length !== total) {
        qaSeq = 0;
        return loadAllQa(true);
      }
      var changed = Boolean(force) || recs.length > 0 || items.length !== allItems.length || limitsChanged;
      if (!changed) { return { changed: false }; }

      items.sort(function (a, b) {
        return String((b && b.timestamp) || "").localeCompare(String((a && a.timestamp) || ""));
      });
      allItems = items;
      qaSeq = (res && typeof res.seq === "number") ? res.seq : qaSeq;
      requestRecordContexts(items).then(function (got) { if (got) { refreshModelMetas(); } });
      return { changed: true };
    });
  }

  // 인수인계 채널 목록 및 모든 채널 상세 로드
  function loadHandoffProjects(force) {
    return fetchJson("/api/handoff/projects").then(function (projects) {
      if (!Array.isArray(projects)) { projects = []; }
      handoffProjects = projects;

      var loaders = projects.map(function (p) {
        var cName = p.name;
        var cached = handoffChannels[cName];
        if (!force && cached && cached.updated === p.updated && Array.isArray(cached.messages) && cached.messages.length === (p.msgCount || 0)) {
          return Promise.resolve(cached);
        }
        return fetchJson("/api/handoff/project?name=" + encodeURIComponent(cName))
          .then(function (data) {
            if (data && typeof data === "object") {
              handoffChannels[cName] = data;
              return data;
            }
            return cached || { name: cName, brief: "", files: [], messages: [] };
          })
          .catch(function (err) {
            console.warn("Handoff channel load error (" + cName + "):", err);
            return cached || { name: cName, brief: "", files: [], messages: [] };
          });
      });

      return Promise.all(loaders).then(function () {
        var validMap = {};
        projects.forEach(function (p) { validMap[p.name] = true; });
        for (var k in handoffChannels) {
          if (!validMap[k]) delete handoffChannels[k];
        }
        if (currentHandoffProject && !currentHandoffSession && handoffChannels[currentHandoffProject]) {
          var treeCheck = buildHandoffTree(handoffChannels, claudeTree);
          var matchProj = treeCheck.some(function (p) { return p.id === currentHandoffProject; });
          if (!matchProj) {
            currentHandoffSession = "c:" + currentHandoffProject;
            currentHandoffProject = QA_UNLINKED;
          }
        }

        renderHandoffTree();
        if (currentNav === "handoff") {
          renderHandoffView();
        }
        return projects;
      });
    }).catch(function (err) {
      console.warn("Handoff projects load error:", err);
      return [];
    });
  }

  // ==========================================================================
  // Session Grouping & QA Side-Panel List
  // ==========================================================================

  function groupQaSessions() {
    var map = {};
    // 1. pending 목록 집계
    pendingItems.forEach(function (p) {
      var sKey = p.session || "__none__";
      if (!map[sKey]) {
        map[sKey] = { name: sKey, total: 0, pending: 0, errors: 0, latestTime: p.created || "", models: {} };
      }
      map[sKey].pending++;
      if (p.created && (!map[sKey].latestTime || p.created > map[sKey].latestTime)) {
        map[sKey].latestTime = p.created;
      }
    });

    // 2. 완료 기록 집계
    allItems.forEach(function (r) {
      var sKey = r.session || "__none__";
      if (!map[sKey]) {
        map[sKey] = { name: sKey, total: 0, pending: 0, errors: 0, latestTime: r.timestamp || "", models: {} };
      }
      map[sKey].total++;
      if (r.status && !isOkStatus(r)) {
        map[sKey].errors++;
      }
      if (recordModel(r)) {
        map[sKey].models[recordModel(r)] = true;
      }
      if (r.timestamp && (!map[sKey].latestTime || r.timestamp > map[sKey].latestTime)) {
        map[sKey].latestTime = r.timestamp;
      }
    });

    var list = Object.keys(map).map(function (k) { return map[k]; });
    // 최신 시간순 정렬
    list.sort(function (a, b) {
      return String(b.latestTime || "").localeCompare(String(a.latestTime || ""));
    });

    return list;
  }

  var QA_UNGROUPED = "__ungrouped__";
  var QA_UNLINKED = "__unlinked__";
  var QA_AGY_UNLINKED = "__agy_unlinked__";

  function qaIsAgyItem(item) {
    if (!item || typeof item !== "object") return false;
    var sc = String(item.src_client || "").trim().toLowerCase();
    var src = String(item.source || "").trim().toLowerCase();
    return sc === "antigravity" || sc === "agy" || src === "agy";
  }

  // 폴더 경로 비교용 키(대소문자·슬래시 방향·끝의 구분자 무시)
  function qaCwdKey(p) {
    return String(p == null ? "" : p).trim().replace(/\//g, "\\").replace(/\\+$/, "").toLowerCase();
  }

  // 아직 대화 기록에 작업 ID 가 남지 않은 대기·진행 중 작업의 세션을 작업 폴더로 짐작한다.
  // (Claude 가 위임을 보내고 같은 명령 안에서 결과를 기다리면, 그 명령이 끝날 때까지 작업 ID 가 대화 기록에 안 남아서 연결할 수 없다.)
  // 작업 폴더(@cwd)가 Desktop 세션의 폴더와 같은 세션 중 가장 최근에 쓴 보관 안 된 세션을 고른다. 없으면 null.
  function qaGuessSessionByCwd(item, tree) {
    if (!item || !tree) return null;
    var raw = item.cwd;
    var cwds = Array.isArray(raw) ? raw : (raw ? [raw] : []);
    var keys = {};
    var any = false;
    for (var i = 0; i < cwds.length; i++) {
      var k = qaCwdKey(cwds[i]);
      if (k) { keys[k] = true; any = true; }
    }
    if (!any) return null;
    var best = null;
    function consider(sess, projectId, projectName) {
      if (!sess || sess.archived || !keys[qaCwdKey(sess.cwd)]) return;
      if (!best || String(sess.lastActivity || "") > String(best.sess.lastActivity || "")) {
        best = { sess: sess, projectId: projectId, projectName: projectName };
      }
    }
    var projects = Array.isArray(tree.projects) ? tree.projects : [];
    for (var a = 0; a < projects.length; a++) {
      var sessions = projects[a] && Array.isArray(projects[a].sessions) ? projects[a].sessions : [];
      for (var b = 0; b < sessions.length; b++) { consider(sessions[b], projects[a].id, projects[a].name); }
    }
    var ungrouped = Array.isArray(tree.ungrouped) ? tree.ungrouped : [];
    for (var c = 0; c < ungrouped.length; c++) { consider(ungrouped[c], QA_UNGROUPED, "그룹 없음"); }
    if (!best) return null;
    return {
      projectId: best.projectId,
      projectName: best.projectName,
      sessionId: best.sess.id,
      sessionTitle: best.sess.title ? best.sess.title : String(best.sess.id).slice(0, 8)
    };
  }

  function qaNodeOf(item, tree) {
    var agyUnlinkedId = (typeof QA_AGY_UNLINKED !== "undefined") ? QA_AGY_UNLINKED : "__agy_unlinked__";
    var link = (tree && tree.taskLinks && item && item.task_id) ? tree.taskLinks[item.task_id] : null;
    if (link) {
      if (tree && Array.isArray(tree.projects)) {
        for (var i = 0; i < tree.projects.length; i++) {
          var p = tree.projects[i];
          if (p && Array.isArray(p.sessions)) {
            for (var j = 0; j < p.sessions.length; j++) {
              var s = p.sessions[j];
              if (s && s.id === link) {
                return {
                  projectId: p.id,
                  projectName: p.name,
                  sessionId: link,
                  sessionTitle: s.title ? s.title : link.slice(0, 8)
                };
              }
            }
          }
        }
      }
      if (tree && Array.isArray(tree.ungrouped)) {
        for (var k = 0; k < tree.ungrouped.length; k++) {
          var us = tree.ungrouped[k];
          if (us && us.id === link) {
            return {
              projectId: QA_UNGROUPED,
              projectName: "그룹 없음",
              sessionId: link,
              sessionTitle: us.title ? us.title : link.slice(0, 8)
            };
          }
        }
      }
      if (tree && Array.isArray(tree.agyProjects)) {
        for (var ai = 0; ai < tree.agyProjects.length; ai++) {
          var ap = tree.agyProjects[ai];
          if (ap && Array.isArray(ap.sessions)) {
            for (var aj = 0; aj < ap.sessions.length; aj++) {
              var as = ap.sessions[aj];
              if (as && as.id === link) {
                return {
                  projectId: ap.id,
                  projectName: ap.name,
                  sessionId: link,
                  sessionTitle: as.title ? as.title : link.slice(0, 8),
                  source: "agy"
                };
              }
            }
          }
        }
      }
    }
    var srcSess = (item && item.src_session) ? String(item.src_session).trim() : "";
    var mappedSess = (!srcSess && tree && tree.agyParentMap && item && item.task_id) ? tree.agyParentMap[item.task_id] : srcSess;
    if (mappedSess && tree && Array.isArray(tree.agyProjects)) {
      for (var api = 0; api < tree.agyProjects.length; api++) {
        var ap2 = tree.agyProjects[api];
        if (ap2 && Array.isArray(ap2.sessions)) {
          for (var apj = 0; apj < ap2.sessions.length; apj++) {
            var as2 = ap2.sessions[apj];
            if (as2 && as2.id === mappedSess) {
              return {
                projectId: ap2.id,
                projectName: ap2.name,
                sessionId: mappedSess,
                sessionTitle: as2.title ? as2.title : mappedSess.slice(0, 8),
                source: "agy"
              };
            }
          }
        }
      }
    }
    // 대기·진행 중인 작업(완료 기록과 달리 timestamp 가 없고 state 가 있다)은 작업 폴더로 세션을 짐작해 본다
    if (item && item.state && !item.timestamp) {
      var guessed = qaGuessSessionByCwd(item, tree);
      if (guessed) return guessed;
    }
    var isAgy = Boolean(item && (String(item.src_client || "").trim().toLowerCase() === "antigravity" || String(item.src_client || "").trim().toLowerCase() === "agy" || String(item.source || "").trim().toLowerCase() === "agy"));
    var sName = (item && item.session != null && String(item.session).trim() !== "") ? String(item.session) : "";
    if (isAgy) {
      return {
        projectId: agyUnlinkedId,
        projectName: "Antigravity (연결 안 됨)",
        sessionId: "u:" + (sName ? sName : "__none__"),
        sessionTitle: sName ? sName : "단발성 (세션 없음)",
        source: "agy"
      };
    }
    return {
      projectId: QA_UNLINKED,
      projectName: "연결 안 됨",
      sessionId: "u:" + (sName ? sName : "__none__"),
      sessionTitle: sName ? sName : "단발성 (세션 없음)"
    };
  }

  function buildQaTree(records, pendings, tree, opts) {
    var recs = Array.isArray(records) ? records : [];
    var pends = Array.isArray(pendings) ? pendings : [];
    var sourceFilter = (opts && opts.source) ? String(opts.source) : "all";
    var agyUnlinkedId = (typeof QA_AGY_UNLINKED !== "undefined") ? QA_AGY_UNLINKED : "__agy_unlinked__";

    var projectList = [];
    var agyProjectList = [];
    var sessionLookup = {};

    if (sourceFilter !== "agy" && tree && Array.isArray(tree.projects)) {
      for (var i = 0; i < tree.projects.length; i++) {
        var p = tree.projects[i];
        if (!p) continue;
        var pNode = {
          id: p.id,
          name: p.name || "",
          source: "claude",
          total: 0,
          pending: 0,
          errors: 0,
          latestTime: "",
          sessions: []
        };
        if (Array.isArray(p.sessions)) {
          for (var j = 0; j < p.sessions.length; j++) {
            var s = p.sessions[j];
            if (!s) continue;
            var sNode = {
              id: s.id,
              title: s.title ? s.title : String(s.id || "").slice(0, 8),
              cwd: s.cwd || "",
              total: 0,
              pending: 0,
              errors: 0,
              latestTime: "",
              archived: Boolean(s.archived),
              forkOf: s.forkOf || "",
              lastActivity: s.lastActivity || ""
            };
            pNode.sessions.push(sNode);
            sessionLookup[s.id] = sNode;
          }
        }
        projectList.push(pNode);
      }
    }

    if (sourceFilter !== "claude" && tree && Array.isArray(tree.agyProjects)) {
      for (var ai = 0; ai < tree.agyProjects.length; ai++) {
        var ap = tree.agyProjects[ai];
        if (!ap) continue;
        var apNode = {
          id: ap.id,
          name: ap.name || "",
          source: "agy",
          total: 0,
          pending: 0,
          errors: 0,
          latestTime: "",
          sessions: []
        };
        if (Array.isArray(ap.sessions)) {
          for (var aj = 0; aj < ap.sessions.length; aj++) {
            var as = ap.sessions[aj];
            if (!as) continue;
            var asNode = {
              id: as.id,
              title: as.title ? as.title : String(as.id || "").slice(0, 8),
              cwd: as.cwd || "",
              total: 0,
              pending: 0,
              errors: 0,
              latestTime: "",
              archived: Boolean(as.archived),
              forkOf: as.forkOf || "",
              lastActivity: as.lastActivity || ""
            };
            apNode.sessions.push(asNode);
            sessionLookup[as.id] = asNode;
          }
        }
        agyProjectList.push(apNode);
      }
    }

    var ungroupedNode = null;
    if (sourceFilter !== "agy" && tree && Array.isArray(tree.ungrouped) && tree.ungrouped.length > 0) {
      ungroupedNode = {
        id: QA_UNGROUPED,
        name: "그룹 없음",
        source: "claude",
        total: 0,
        pending: 0,
        errors: 0,
        latestTime: "",
        sessions: []
      };
      for (var u = 0; u < tree.ungrouped.length; u++) {
        var us = tree.ungrouped[u];
        if (!us) continue;
        var usNode = {
          id: us.id,
          title: us.title ? us.title : String(us.id || "").slice(0, 8),
          cwd: us.cwd || "",
          total: 0,
          pending: 0,
          errors: 0,
          latestTime: "",
          archived: Boolean(us.archived),
          lastActivity: us.lastActivity || ""
        };
        ungroupedNode.sessions.push(usNode);
        sessionLookup[us.id] = usNode;
      }
    }

    var unlinkedNode = {
      id: QA_UNLINKED,
      name: "연결 안 됨",
      source: "claude",
      total: 0,
      pending: 0,
      errors: 0,
      latestTime: "",
      sessions: []
    };
    var unlinkedSessionMap = {};

    var agyUnlinkedNode = {
      id: agyUnlinkedId,
      name: "Antigravity (연결 안 됨)",
      source: "agy",
      total: 0,
      pending: 0,
      errors: 0,
      latestTime: "",
      sessions: []
    };
    var agyUnlinkedSessionMap = {};

    function processItem(item, isPending) {
      if (!item || typeof item !== "object") return;
      var nodeInfo = qaNodeOf(item, tree);
      var itemIsAgy = (nodeInfo.source === "agy") || (nodeInfo.projectId === agyUnlinkedId);
      if (sourceFilter === "agy" && !itemIsAgy) return;
      if (sourceFilter === "claude" && itemIsAgy) return;

      var time = isPending ? (item.created || "") : (item.timestamp || "");
      var isErr = !isPending && item.status && !isOkStatus(item);

      var targetSession = null;
      if (nodeInfo.projectId === QA_UNLINKED) {
        targetSession = unlinkedSessionMap[nodeInfo.sessionId];
        if (!targetSession) {
          targetSession = {
            id: nodeInfo.sessionId,
            title: nodeInfo.sessionTitle,
            cwd: "",
            total: 0,
            pending: 0,
            errors: 0,
            latestTime: "",
            archived: false,
            lastActivity: ""
          };
          unlinkedSessionMap[nodeInfo.sessionId] = targetSession;
          unlinkedNode.sessions.push(targetSession);
        }
      } else if (nodeInfo.projectId === agyUnlinkedId) {
        targetSession = agyUnlinkedSessionMap[nodeInfo.sessionId];
        if (!targetSession) {
          targetSession = {
            id: nodeInfo.sessionId,
            title: nodeInfo.sessionTitle,
            cwd: "",
            total: 0,
            pending: 0,
            errors: 0,
            latestTime: "",
            archived: false,
            lastActivity: ""
          };
          agyUnlinkedSessionMap[nodeInfo.sessionId] = targetSession;
          agyUnlinkedNode.sessions.push(targetSession);
        }
      } else {
        targetSession = sessionLookup[nodeInfo.sessionId];
      }

      if (targetSession) {
        if (isPending) {
          targetSession.pending++;
        } else {
          targetSession.total++;
          if (isErr) {
            targetSession.errors++;
          }
        }
        if (time && (!targetSession.latestTime || time > targetSession.latestTime)) {
          targetSession.latestTime = time;
        }
        // 완료 시각: 끝난 기록의 시각만(진행·대기 중인 작업은 뺀다). 사이드바 행에 보이는 시간이다.
        if (!isPending && time && (!targetSession.latestDone || time > targetSession.latestDone)) {
          targetSession.latestDone = time;
        }
      }
    }

    for (var rIdx = 0; rIdx < recs.length; rIdx++) {
      processItem(recs[rIdx], false);
    }
    for (var pIdx = 0; pIdx < pends.length; pIdx++) {
      processItem(pends[pIdx], true);
    }

    function finalizeProject(p) {
      var validSessions = [];
      for (var i = 0; i < p.sessions.length; i++) {
        var s = p.sessions[i];
        if (s.archived && (s.total + s.pending === 0)) {
          continue;
        }
        validSessions.push(s);
      }

      validSessions.sort(function (a, b) {
        var aTime = a.latestTime || "";
        if (a.lastActivity && (!aTime || a.lastActivity > aTime)) {
          aTime = a.lastActivity;
        }
        var bTime = b.latestTime || "";
        if (b.lastActivity && (!bTime || b.lastActivity > bTime)) {
          bTime = b.lastActivity;
        }
        if (bTime !== aTime) {
          return bTime > aTime ? 1 : -1;
        }
        return (a.title || "").localeCompare(b.title || "");
      });

      var pTotal = 0;
      var pPending = 0;
      var pErrors = 0;
      var pLatest = "";
      var pDone = "";

      for (var j = 0; j < validSessions.length; j++) {
        var vs = validSessions[j];
        pTotal += vs.total;
        pPending += vs.pending;
        pErrors += vs.errors;
        if (vs.latestTime && (!pLatest || vs.latestTime > pLatest)) {
          pLatest = vs.latestTime;
        }
        if (vs.latestDone && (!pDone || vs.latestDone > pDone)) {
          pDone = vs.latestDone;
        }
      }

      p.sessions = validSessions;
      p.total = pTotal;
      p.pending = pPending;
      p.errors = pErrors;
      p.latestTime = pLatest;
      p.latestDone = pDone;
    }

    var result = [];

    for (var pI = 0; pI < projectList.length; pI++) {
      finalizeProject(projectList[pI]);
      result.push(projectList[pI]);
    }

    for (var aI = 0; aI < agyProjectList.length; aI++) {
      finalizeProject(agyProjectList[aI]);
      result.push(agyProjectList[aI]);
    }

    if (ungroupedNode) {
      finalizeProject(ungroupedNode);
      if (ungroupedNode.sessions.length > 0) {
        result.push(ungroupedNode);
      }
    }

    if (sourceFilter !== "agy") {
      finalizeProject(unlinkedNode);
      if (unlinkedNode.sessions.length > 0 && (unlinkedNode.total + unlinkedNode.pending > 0)) {
        result.push(unlinkedNode);
      }
    }

    if (sourceFilter !== "claude") {
      finalizeProject(agyUnlinkedNode);
      if (agyUnlinkedNode.sessions.length > 0 && (agyUnlinkedNode.total + agyUnlinkedNode.pending > 0)) {
        result.push(agyUnlinkedNode);
      }
    }

    return result;
  }

  function qaFilterTree(nodes, query) {
    if (!Array.isArray(nodes)) return [];
    var q = (query == null ? "" : String(query)).trim().toLowerCase();
    if (!q) {
      return nodes.slice();
    }
    var result = [];
    for (var i = 0; i < nodes.length; i++) {
      var p = nodes[i];
      if (!p) continue;
      var pName = (p.name || "").toLowerCase();
      if (pName.indexOf(q) !== -1) {
        result.push({
          id: p.id,
          name: p.name,
          total: p.total,
          pending: p.pending,
          errors: p.errors,
          latestTime: p.latestTime,
          sessions: Array.isArray(p.sessions) ? p.sessions.slice() : []
        });
      } else {
        var matchingSessions = [];
        if (Array.isArray(p.sessions)) {
          for (var j = 0; j < p.sessions.length; j++) {
            var s = p.sessions[j];
            if (s && (s.title || "").toLowerCase().indexOf(q) !== -1) {
              matchingSessions.push(s);
            }
          }
        }
        if (matchingSessions.length > 0) {
          result.push({
            id: p.id,
            name: p.name,
            total: p.total,
            pending: p.pending,
            errors: p.errors,
            latestTime: p.latestTime,
            sessions: matchingSessions
          });
        }
      }
    }
    return result;
  }

  function qaItemMatchesSelection(item, tree, projectId, sessionId, sourceFilter) {
    var node = qaNodeOf(item, tree);
    if (sourceFilter === "agy" && node.source !== "agy") return false;
    if (sourceFilter === "claude" && node.source === "agy") return false;
    if (!projectId) return true;
    if (node.projectId !== projectId) return false;
    if (sessionId && node.sessionId !== sessionId) return false;
    return true;
  }

  function qaItemMatchesAgy(item, agy) {
    if (!agy) return true;
    var s = (item && item.session != null) ? String(item.session).trim() : "";
    if (agy === "__none__") {
      return s === "";
    }
    return s === agy;
  }

  function qaAgySessionsOf(records, pendings, tree, projectId, sessionId) {
    var recs = Array.isArray(records) ? records : [];
    var pends = Array.isArray(pendings) ? pendings : [];
    var map = {};

    function processItem(item, isPending) {
      if (!item || typeof item !== "object") return;
      if (!qaItemMatchesSelection(item, tree, projectId, sessionId)) return;

      var rawS = (item.session != null) ? String(item.session).trim() : "";
      var sKey = rawS ? rawS : "__none__";

      if (!map[sKey]) {
        map[sKey] = {
          name: sKey,
          total: 0,
          pending: 0,
          errors: 0,
          latestTime: ""
        };
      }

      var entry = map[sKey];
      var time = isPending ? (item.created || "") : (item.timestamp || "");
      if (isPending) {
        entry.pending++;
      } else {
        entry.total++;
        if (item.status && !isOkStatus(item)) {
          entry.errors++;
        }
      }
      if (time && (!entry.latestTime || time > entry.latestTime)) {
        entry.latestTime = time;
      }
    }

    for (var r = 0; r < recs.length; r++) {
      processItem(recs[r], false);
    }
    for (var p = 0; p < pends.length; p++) {
      processItem(pends[p], true);
    }

    var list = [];
    for (var k in map) {
      if (Object.prototype.hasOwnProperty.call(map, k)) {
        list.push(map[k]);
      }
    }

    list.sort(function (a, b) {
      var tA = a.latestTime || "";
      var tB = b.latestTime || "";
      if (tA !== tB) {
        return tB > tA ? 1 : -1;
      }
      if (a.name !== b.name) {
        return a.name < b.name ? -1 : 1;
      }
      return 0;
    });

    return list;
  }

  // agy 세션 칩을 보일 것과 접을 것으로 나눈다. sessions 는 최근순. 진행 중(pending)인 것과 지금 고른 것은 늘 보인다.
  // 접을 것이 2개 이하이면 접지 않는다(버튼 하나가 칩 두 개보다 더 자리를 차지한다). 반환: { shown, hidden, hiddenErrors }
  function qaChipSplit(sessions, activeName, limit) {
    var list = Array.isArray(sessions) ? sessions : [];
    var max = (limit > 0) ? limit : 8;
    if (list.length <= max + 2) { return { shown: list.slice(), hidden: [], hiddenErrors: 0 }; }
    var shown = [];
    var hidden = [];
    var hiddenErrors = 0;
    for (var i = 0; i < list.length; i++) {
      var s = list[i];
      if (i < max || s.pending > 0 || s.name === activeName) { shown.push(s); }
      else { hidden.push(s); hiddenErrors += s.errors || 0; }
    }
    if (hidden.length <= 2) { return { shown: list.slice(), hidden: [], hiddenErrors: 0 }; }
    return { shown: shown, hidden: hidden, hiddenErrors: hiddenErrors };
  }

  var TREE_SORT_MODES = [{"value":"recent-desc","label":"날짜 최신순"},{"value":"recent-asc","label":"날짜 오래된순"},{"value":"name-asc","label":"이름순 (가나다)"},{"value":"name-desc","label":"이름 역순"},{"value":"desktop","label":"Desktop 순서"}];
  var TREE_SORT_DEFAULT = "recent-desc";

  function normalizeTreeSortMode(v) {
    if (!v || typeof v !== "string") return TREE_SORT_DEFAULT;
    for (var i = 0; i < TREE_SORT_MODES.length; i++) {
      if (TREE_SORT_MODES[i].value === v) return v;
    }
    return TREE_SORT_DEFAULT;
  }

  // 프로젝트 행의 부제에 보일 "최근 시각": 기록의 최근 시각과 Desktop 세션의 최근 활동 중 늦은 것(기록이 없는 프로젝트도 "-" 대신 시각이 보인다)
  function treeNodeLatest(node) {
    var best = String((node && node.latestTime) || "");
    var list = (node && Array.isArray(node.sessions)) ? node.sessions : [];
    for (var i = 0; i < list.length; i++) {
      var t = String(list[i].latestTime || "");
      var a = String(list[i].lastActivity || "");
      if (t > best) { best = t; }
      if (a > best) { best = a; }
    }
    return best;
  }

  // opts.dateSource === "records" 이면 날짜 정렬이 위임 기록(agy 작업)의 최근 완료 시각만 본다(Desktop 세션의 최근 활동은 무시하고,
  // 시각이 같거나 기록이 없을 때만 보조 기준으로 쓴다). 기본은 기록과 Desktop 활동 중 늦은 쪽.
  function sortTreeNodes(nodes, mode, opts) {
    if (!Array.isArray(nodes)) return [];
    var sortMode = normalizeTreeSortMode(mode);
    var recordsOnly = Boolean(opts && opts.dateSource === "records");

    function maxTime(t1, t2) {
      var s1 = t1 || "";
      var s2 = t2 || "";
      if (!s1) return s2;
      if (!s2) return s1;
      return s1 > s2 ? s1 : s2;
    }

    // records 모드의 기록 시각: 완료 시각(latestDone)이 있으면 그것, 없으면(옛 데이터) latestTime.
    // 단 진행·대기 중인 작업이 있으면(pending > 0) 그 작업의 시작 시각(latestTime 에 들어 있다)이 더 늦을 때 그것을 쓴다 —
    // 지금 도는 작업이 있는 프로젝트·세션이 마지막 완료가 오래전이라고 아래로 밀리지 않게 한다. 사이드바 행에 보이는 위임 시각은 그대로 완료 시각이다.
    function recordTimeOf(x) {
      if (!x) return "";
      var done = (x.latestDone != null ? x.latestDone : x.latestTime) || "";
      if (x.pending > 0 && x.latestTime && String(x.latestTime) > String(done)) { return String(x.latestTime); }
      return done;
    }

    function sessionDateKey(s) {
      if (!s) return "";
      return recordsOnly ? recordTimeOf(s) : maxTime(s.latestTime, s.lastActivity);
    }

    // 보조 기준(records 모드): Desktop 에서 마지막으로 쓴 시각
    function sessionActivityKey(s) {
      return (s && s.lastActivity) ? String(s.lastActivity) : "";
    }
    function projectActivityKey(p) {
      var best = "";
      if (p && Array.isArray(p.sessions)) {
        for (var i = 0; i < p.sessions.length; i++) { best = maxTime(best, sessionActivityKey(p.sessions[i])); }
      }
      return best;
    }

    function projectDateKey(p) {
      if (!p) return "";
      var maxT = recordsOnly ? recordTimeOf(p) : (p.latestTime || "");
      if (Array.isArray(p.sessions)) {
        for (var i = 0; i < p.sessions.length; i++) {
          var s = p.sessions[i];
          if (!s) continue;
          maxT = maxTime(maxT, recordsOnly ? recordTimeOf(s) : s.latestTime);
          if (!recordsOnly) { maxT = maxTime(maxT, s.lastActivity); }
        }
      }
      return maxT;
    }

    function compareDates(tA, tB, isDesc) {
      var sA = tA || "";
      var sB = tB || "";
      if (sA === sB) return 0;
      if (!sA) return isDesc ? 1 : -1;
      if (!sB) return isDesc ? -1 : 1;
      if (isDesc) {
        return sB > sA ? 1 : -1;
      } else {
        return sA > sB ? 1 : -1;
      }
    }

    function sortSessions(sessions, sm) {
      if (!Array.isArray(sessions)) return [];
      var sMode = (sm === "desktop") ? "recent-desc" : sm;
      var list = sessions.map(function (s, idx) {
        return { s: s, idx: idx };
      });

      list.sort(function (itemA, itemB) {
        var a = itemA.s;
        var b = itemB.s;
        if (sMode === "recent-desc" || sMode === "recent-asc") {
          var isDesc = (sMode === "recent-desc");
          var tA = sessionDateKey(a);
          var tB = sessionDateKey(b);
          var dDiff = compareDates(tA, tB, isDesc);
          if (dDiff !== 0) return dDiff;
          if (recordsOnly) {
            var aDiffS = compareDates(sessionActivityKey(a), sessionActivityKey(b), isDesc);
            if (aDiffS !== 0) return aDiffS;
          }
          var titleA = (a && a.title != null) ? String(a.title) : "";
          var titleB = (b && b.title != null) ? String(b.title) : "";
          var nameDiff = titleA.localeCompare(titleB, "ko", { numeric: true, sensitivity: "base" });
          if (nameDiff !== 0) return nameDiff;
          var idA = (a && a.id != null) ? String(a.id) : "";
          var idB = (b && b.id != null) ? String(b.id) : "";
          if (idA !== idB) return idA < idB ? -1 : 1;
          return itemA.idx - itemB.idx;
        } else if (sMode === "name-asc") {
          var tA1 = (a && a.title != null) ? String(a.title) : "";
          var tB1 = (b && b.title != null) ? String(b.title) : "";
          var diff1 = tA1.localeCompare(tB1, "ko", { numeric: true, sensitivity: "base" });
          if (diff1 !== 0) return diff1;
          var idA1 = (a && a.id != null) ? String(a.id) : "";
          var idB1 = (b && b.id != null) ? String(b.id) : "";
          if (idA1 !== idB1) return idA1 < idB1 ? -1 : 1;
          return itemA.idx - itemB.idx;
        } else if (sMode === "name-desc") {
          var tA2 = (a && a.title != null) ? String(a.title) : "";
          var tB2 = (b && b.title != null) ? String(b.title) : "";
          var diff2 = tB2.localeCompare(tA2, "ko", { numeric: true, sensitivity: "base" });
          if (diff2 !== 0) return diff2;
          var idA2 = (a && a.id != null) ? String(a.id) : "";
          var idB2 = (b && b.id != null) ? String(b.id) : "";
          if (idA2 !== idB2) return idA2 < idB2 ? -1 : 1;
          return itemA.idx - itemB.idx;
        }
        return itemA.idx - itemB.idx;
      });

      var copies = list.map(function (it) {
        var copy = {};
        for (var k in it.s) {
          if (Object.prototype.hasOwnProperty.call(it.s, k)) {
            copy[k] = it.s[k];
          }
        }
        return copy;
      });
      // 포크한 세션은 같은 목록에 원본이 있으면 원본 바로 밑으로 묶는다(Claude Desktop 과 같은 모양). 원본이 목록에 없으면 제자리.
      var present = {};
      copies.forEach(function (c) { present[c.id] = true; });
      var kids = {};
      var roots = [];
      copies.forEach(function (c) {
        if (c.forkOf && c.forkOf !== c.id && present[c.forkOf]) { (kids[c.forkOf] = kids[c.forkOf] || []).push(c); }
        else { roots.push(c); }
      });
      var ordered = [];
      var seen = {};
      var place = function (c, depth) {
        if (seen[c.id]) return;
        seen[c.id] = true;
        c.forkDepth = depth;
        ordered.push(c);
        (kids[c.id] || []).forEach(function (k) { place(k, depth + 1); });
      };
      roots.forEach(function (c) { place(c, 0); });
      copies.forEach(function (c) { place(c, 0); });   // 고리(서로가 서로의 원본)로 빠진 것이 있어도 잃지 않는다
      return ordered;
    }

    function cloneNode(p, sm) {
      if (!p) return p;
      var copy = {};
      for (var k in p) {
        if (Object.prototype.hasOwnProperty.call(p, k)) {
          copy[k] = p[k];
        }
      }
      copy.sessions = sortSessions(p.sessions, sm);
      return copy;
    }

    var normalList = [];
    var ungroupedNode = null;
    var unlinkedNode = null;

    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      if (!node) continue;
      if (node.id === QA_UNGROUPED) {
        ungroupedNode = node;
      } else if (node.id === QA_UNLINKED) {
        unlinkedNode = node;
      } else {
        normalList.push({ node: node, idx: i });
      }
    }

    if (sortMode !== "desktop") {
      normalList.sort(function (itemA, itemB) {
        var a = itemA.node;
        var b = itemB.node;
        if (sortMode === "recent-desc" || sortMode === "recent-asc") {
          var isDesc = (sortMode === "recent-desc");
          var tA = projectDateKey(a);
          var tB = projectDateKey(b);
          var dDiff = compareDates(tA, tB, isDesc);
          if (dDiff !== 0) return dDiff;
          if (recordsOnly) {
            var aDiffP = compareDates(projectActivityKey(a), projectActivityKey(b), isDesc);
            if (aDiffP !== 0) return aDiffP;
          }
          var nameA = (a && a.name != null) ? String(a.name) : "";
          var nameB = (b && b.name != null) ? String(b.name) : "";
          var nDiff = nameA.localeCompare(nameB, "ko", { numeric: true, sensitivity: "base" });
          if (nDiff !== 0) return nDiff;
          var idA = (a && a.id != null) ? String(a.id) : "";
          var idB = (b && b.id != null) ? String(b.id) : "";
          if (idA !== idB) return idA < idB ? -1 : 1;
          return itemA.idx - itemB.idx;
        } else if (sortMode === "name-asc") {
          var nA1 = (a && a.name != null) ? String(a.name) : "";
          var nB1 = (b && b.name != null) ? String(b.name) : "";
          var diff1 = nA1.localeCompare(nB1, "ko", { numeric: true, sensitivity: "base" });
          if (diff1 !== 0) return diff1;
          var idA1 = (a && a.id != null) ? String(a.id) : "";
          var idB1 = (b && b.id != null) ? String(b.id) : "";
          if (idA1 !== idB1) return idA1 < idB1 ? -1 : 1;
          return itemA.idx - itemB.idx;
        } else if (sortMode === "name-desc") {
          var nA2 = (a && a.name != null) ? String(a.name) : "";
          var nB2 = (b && b.name != null) ? String(b.name) : "";
          var diff2 = nB2.localeCompare(nA2, "ko", { numeric: true, sensitivity: "base" });
          if (diff2 !== 0) return diff2;
          var idA2 = (a && a.id != null) ? String(a.id) : "";
          var idB2 = (b && b.id != null) ? String(b.id) : "";
          if (idA2 !== idB2) return idA2 < idB2 ? -1 : 1;
          return itemA.idx - itemB.idx;
        }
        return itemA.idx - itemB.idx;
      });
    }

    var result = [];
    for (var j = 0; j < normalList.length; j++) {
      result.push(cloneNode(normalList[j].node, sortMode));
    }
    if (ungroupedNode) {
      result.push(cloneNode(ungroupedNode, sortMode));
    }
    if (unlinkedNode) {
      result.push(cloneNode(unlinkedNode, sortMode));
    }

    return result;
  }

  function findQaNodeTitles(treeNodes, projectId, sessionId) {
    var pName = "";
    var sTitle = "";
    if (!projectId) return { projectName: "", sessionTitle: "" };
    var list = Array.isArray(treeNodes) ? treeNodes : [];
    for (var i = 0; i < list.length; i++) {
      var p = list[i];
      if (p && p.id === projectId) {
        pName = p.name;
        if (sessionId && Array.isArray(p.sessions)) {
          for (var j = 0; j < p.sessions.length; j++) {
            if (p.sessions[j] && p.sessions[j].id === sessionId) {
              sTitle = p.sessions[j].title;
              break;
            }
          }
        }
        break;
      }
    }
    return {
      projectName: pName || projectId,
      sessionTitle: sTitle || sessionId
    };
  }

  function handoffMsgFileOf(msg, channelData) {
    if (!msg || msg.num == null || !channelData || !Array.isArray(channelData.files)) {
      return "";
    }
    var prefix = String(msg.num) + "-";
    for (var i = 0; i < channelData.files.length; i++) {
      var f = channelData.files[i];
      if (typeof f === "string" && f.indexOf(prefix) === 0) {
        return f;
      }
    }
    return "";
  }

  // 세션 연결은 "채널/파일" 키를 먼저 보고, 파일 이름만 나온 기록은 같은 이름이 다른 채널에 없을 때만 쓴다.
  function handoffLinkOf(tree, channelName, file) {
    var links = tree && tree.handoffLinks;
    if (!links || !file) { return null; }
    if (channelName && links[channelName + "/" + file]) { return links[channelName + "/" + file]; }
    if (!links[file]) { return null; }
    for (var cn in handoffChannels) {
      if (!Object.prototype.hasOwnProperty.call(handoffChannels, cn) || cn === channelName) { continue; }
      var cf = handoffChannels[cn] && handoffChannels[cn].files;
      if (Array.isArray(cf) && cf.indexOf(file) >= 0) { return null; }
    }
    return links[file];
  }

  // 세션 id 를 트리에서 찾아 노드로. 세션이 사라졌으면 null.
  function handoffSessionNodeOf(tree, link) {
    if (!link) { return null; }
    if (tree && Array.isArray(tree.projects)) {
      for (var i = 0; i < tree.projects.length; i++) {
        var p = tree.projects[i];
        if (p && Array.isArray(p.sessions)) {
          for (var j = 0; j < p.sessions.length; j++) {
            var s = p.sessions[j];
            if (s && s.id === link) {
              return {
                projectId: p.id,
                projectName: p.name,
                sessionId: link,
                sessionTitle: s.title ? s.title : link.slice(0, 8)
              };
            }
          }
        }
      }
    }
    if (tree && Array.isArray(tree.ungrouped)) {
      for (var k = 0; k < tree.ungrouped.length; k++) {
        var us = tree.ungrouped[k];
        if (us && us.id === link) {
          return {
            projectId: QA_UNGROUPED,
            projectName: "그룹 없음",
            sessionId: link,
            sessionTitle: us.title ? us.title : link.slice(0, 8)
          };
        }
      }
    }
    return null;
  }

  // 파일 이름이 기록에 안 남아 연결이 없는 메시지(Claude 가 번호만 출력한 c2a 등)는 머리말의 답장대상으로 이어진 메시지(자기가 답한 쪽, 자기에게 답한 쪽)를
  // 따라가 가장 가까운(홉이 적은, 같으면 번호가 작은) 연결된 메시지의 세션을 쓴다. 파일 이름 근거의 직접 연결은 호출하는 쪽에서 먼저 쓴다.
  // 같은 채널 안의 번호끼리만 잇는다(다른 채널의 같은 번호가 섞이지 않게 handoffLinkOf 에 채널 이름을 넘긴다).
  function handoffChainNodeOf(channelName, msg, channelData, tree) {
    if (!msg || msg.num == null || !channelData || !Array.isArray(channelData.messages)) { return null; }
    var neighbors = {};
    function addEdge(a, b) {
      if (!a || !b || a === b) { return; }
      (neighbors[a] = neighbors[a] || []).push(b);
      (neighbors[b] = neighbors[b] || []).push(a);
    }
    var byNum = {};
    var msgs = channelData.messages;
    for (var i = 0; i < msgs.length; i++) {
      var m = msgs[i];
      if (!m || m.num == null) { continue; }
      byNum[String(m.num)] = m;
      if (m.replyTo) { addEdge(String(m.num), String(m.replyTo)); }
    }
    var start = String(msg.num);
    var seen = {};
    seen[start] = true;
    var level = [start];
    while (level.length) {
      var found = [];
      var next = [];
      level.sort();
      for (var l = 0; l < level.length; l++) {
        var nbs = neighbors[level[l]] || [];
        for (var n = 0; n < nbs.length; n++) {
          var nn = nbs[n];
          if (seen[nn] || !byNum[nn]) { continue; }
          seen[nn] = true;
          next.push(nn);
          var node = handoffSessionNodeOf(tree, handoffLinkOf(tree, channelName, handoffMsgFileOf(byNum[nn], channelData)));
          if (node) { found.push({ num: nn, node: node }); }
        }
      }
      if (found.length) {
        found.sort(function (a, b) { return a.num < b.num ? -1 : (a.num > b.num ? 1 : 0); });
        return found[0].node;
      }
      level = next;
    }
    return null;
  }

  // BRIEF.md 의 "세션 ID: `ID1`, `ID2`" 줄에서 세션 ID 를 모두 꺼낸다(자리표시자 <...> 는 뺀다). handoff-lib.ps1 의 Get-HandoffBriefSessionIds 와 같은 규칙이다.
  function handoffBriefSessionIds(brief) {
    var line = /세션\s*ID\*{0,2}\s*[:：]([^\r\n]*)/.exec(String(brief == null ? "" : brief));
    var ids = [];
    if (!line) { return ids; }
    var re = /`([^`]+)`/g, m;
    while ((m = re.exec(line[1])) !== null) {
      var id = m[1].trim();
      if (id && id.charAt(0) !== "<" && ids.indexOf(id) < 0) { ids.push(id); }
    }
    return ids;
  }

  // 세션 전용 채널(BRIEF 에 세션 ID 가 적힌 채널)의 메시지는 그 세션에 붙인다. 세션 기록에 파일 이름이 안 찍혀 연결이 없고 답장대상 이웃도 연결이 없을 때의 마지막 근거다.
  // 이어서 다시 열어 ID 가 여럿이면 목록의 뒤쪽(최근) 것부터 보고, 트리에 있는 세션만 쓴다.
  function handoffBriefNodeOf(channelData, tree) {
    var ids = handoffBriefSessionIds(channelData && channelData.brief);
    for (var i = ids.length - 1; i >= 0; i--) {
      var node = handoffSessionNodeOf(tree, ids[i]);
      if (node) { return node; }
    }
    return null;
  }

  // 메시지의 주인 세션: c2a 는 머리말의 `세션`(Claude 가 쓴 세션 ID — Stop 훅이 적는다), agy 회신(a2c)은 그 회신이 답한 c2a 의 `세션`.
  // 같은 채널을 세션 둘이 함께 쓸 때 회신을 읽은 세션이 아니라 질문을 보낸 세션에 붙이려는 것이다(읽은 쪽으로 붙이면 엉뚱한 세션에 걸린다).
  // 세션을 이어서 다시 열면 세션 ID 가 바뀌어 머리말의 세션이 트리에 없을 수 있다. 그때 회신은 질문(c2a) 파일 이름이 나오는 대화 기록의 세션을 따른다
  // (이어 연 세션의 기록에는 앞선 대화가 이어져 있어 질문 파일 이름이 나온다). 둘 다 없으면(예전 메시지) null — 아래의 기존 근거를 쓴다.
  function handoffOwnerNodeOf(channelName, msg, channelData, tree) {
    if (!msg) { return null; }
    var ask = msg;
    if (msg.dir === "a2c") {
      ask = null;
      if (msg.replyTo && channelData && Array.isArray(channelData.messages)) {
        for (var i = 0; i < channelData.messages.length; i++) {
          var m = channelData.messages[i];
          if (m && String(m.num) === String(msg.replyTo)) { ask = m; break; }
        }
      }
      if (!ask) { return null; }
    }
    var sid = String(ask.session || "");
    var node = sid ? handoffSessionNodeOf(tree, sid) : null;
    if (node) { return node; }
    if (msg.dir === "a2c") {
      return handoffSessionNodeOf(tree, handoffLinkOf(tree, channelName, handoffMsgFileOf(ask, channelData)));
    }
    return null;
  }

  function handoffNodeOf(channelName, msg, channelData, tree) {
    var owner = handoffOwnerNodeOf(channelName, msg, channelData, tree);
    if (owner) { return owner; }
    var file = handoffMsgFileOf(msg, channelData);
    var link = handoffLinkOf(tree, channelName, file);
    var direct = handoffSessionNodeOf(tree, link);
    if (direct) { return direct; }
    var chained = handoffChainNodeOf(channelName, msg, channelData, tree);
    if (chained) { return chained; }
    var bound = handoffBriefNodeOf(channelData, tree);
    if (bound) { return bound; }
    var cName = (channelName != null && String(channelName).trim() !== "") ? String(channelName) : "";
    return {
      projectId: QA_UNLINKED,
      projectName: "연결 안 됨",
      sessionId: "c:" + cName,
      sessionTitle: cName
    };
  }

  function buildHandoffTree(channels, tree) {
    var projectList = [];
    var sessionLookup = {};

    if (tree && Array.isArray(tree.projects)) {
      for (var i = 0; i < tree.projects.length; i++) {
        var p = tree.projects[i];
        if (!p) continue;
        var pNode = {
          id: p.id,
          name: p.name || "",
          total: 0,
          waiting: 0,
          latestTime: "",
          sessions: []
        };
        if (Array.isArray(p.sessions)) {
          for (var j = 0; j < p.sessions.length; j++) {
            var s = p.sessions[j];
            if (!s) continue;
            var sNode = {
              id: s.id,
              title: s.title ? s.title : String(s.id || "").slice(0, 8),
              cwd: s.cwd || "",
              total: 0,
              waiting: 0,
              latestTime: "",
              archived: Boolean(s.archived),
              forkOf: s.forkOf || "",
              lastActivity: s.lastActivity || ""
            };
            pNode.sessions.push(sNode);
            sessionLookup[s.id] = sNode;
          }
        }
        projectList.push(pNode);
      }
    }

    var ungroupedNode = null;
    if (tree && Array.isArray(tree.ungrouped) && tree.ungrouped.length > 0) {
      ungroupedNode = {
        id: QA_UNGROUPED,
        name: "그룹 없음",
        total: 0,
        waiting: 0,
        latestTime: "",
        sessions: []
      };
      for (var u = 0; u < tree.ungrouped.length; u++) {
        var us = tree.ungrouped[u];
        if (!us) continue;
        var usNode = {
          id: us.id,
          title: us.title ? us.title : String(us.id || "").slice(0, 8),
          cwd: us.cwd || "",
          total: 0,
          waiting: 0,
          latestTime: "",
          archived: Boolean(us.archived),
          lastActivity: us.lastActivity || ""
        };
        ungroupedNode.sessions.push(usNode);
        sessionLookup[us.id] = usNode;
      }
    }

    var unlinkedNode = {
      id: QA_UNLINKED,
      name: "연결 안 됨",
      total: 0,
      waiting: 0,
      latestTime: "",
      sessions: []
    };
    var unlinkedSessionMap = {};

    if (channels && typeof channels === "object") {
      var channelNames = Object.keys(channels);
      for (var cI = 0; cI < channelNames.length; cI++) {
        var cName = channelNames[cI];
        var cData = channels[cName];
        if (!cData || !Array.isArray(cData.messages)) continue;

        for (var mI = 0; mI < cData.messages.length; mI++) {
          var msg = cData.messages[mI];
          if (!msg || typeof msg !== "object") continue;

          var nodeInfo = handoffNodeOf(cName, msg, cData, tree);
          var time = msg.time || "";
          var isWaiting = (msg.status === "보냄" || msg.status === "읽음");

          var targetSession = null;
          if (nodeInfo.projectId === QA_UNLINKED) {
            targetSession = unlinkedSessionMap[nodeInfo.sessionId];
            if (!targetSession) {
              targetSession = {
                id: nodeInfo.sessionId,
                title: nodeInfo.sessionTitle,
                cwd: "",
                total: 0,
                waiting: 0,
                latestTime: "",
                archived: false,
                lastActivity: ""
              };
              unlinkedSessionMap[nodeInfo.sessionId] = targetSession;
              unlinkedNode.sessions.push(targetSession);
            }
          } else {
            targetSession = sessionLookup[nodeInfo.sessionId];
          }

          if (targetSession) {
            targetSession.total++;
            if (isWaiting) {
              targetSession.waiting++;
            }
            if (time && (!targetSession.latestTime || time > targetSession.latestTime)) {
              targetSession.latestTime = time;
            }
          }
        }
      }
    }

    function finalizeProject(p) {
      var validSessions = [];
      for (var i = 0; i < p.sessions.length; i++) {
        var s = p.sessions[i];
        if (s.archived && s.total === 0) {
          continue;
        }
        validSessions.push(s);
      }

      validSessions.sort(function (a, b) {
        var aTime = a.latestTime || "";
        if (a.lastActivity && (!aTime || a.lastActivity > aTime)) {
          aTime = a.lastActivity;
        }
        var bTime = b.latestTime || "";
        if (b.lastActivity && (!bTime || b.lastActivity > bTime)) {
          bTime = b.lastActivity;
        }
        if (bTime !== aTime) {
          return bTime > aTime ? 1 : -1;
        }
        return (a.title || "").localeCompare(b.title || "");
      });

      var pTotal = 0;
      var pWaiting = 0;
      var pLatest = "";

      for (var j = 0; j < validSessions.length; j++) {
        var vs = validSessions[j];
        pTotal += vs.total;
        pWaiting += vs.waiting;
        if (vs.latestTime && (!pLatest || vs.latestTime > pLatest)) {
          pLatest = vs.latestTime;
        }
      }

      p.sessions = validSessions;
      p.total = pTotal;
      p.waiting = pWaiting;
      p.latestTime = pLatest;
    }

    var result = [];

    for (var pIdx = 0; pIdx < projectList.length; pIdx++) {
      finalizeProject(projectList[pIdx]);
      result.push(projectList[pIdx]);
    }

    if (ungroupedNode) {
      finalizeProject(ungroupedNode);
      if (ungroupedNode.sessions.length > 0) {
        result.push(ungroupedNode);
      }
    }

    finalizeProject(unlinkedNode);
    if (unlinkedNode.sessions.length > 0 && unlinkedNode.total > 0) {
      result.push(unlinkedNode);
    }

    return result;
  }

  function handoffFilterTree(nodes, query) {
    if (!Array.isArray(nodes)) return [];
    var q = (query == null ? "" : String(query)).trim().toLowerCase();
    if (!q) {
      return nodes.slice();
    }
    var result = [];
    for (var i = 0; i < nodes.length; i++) {
      var p = nodes[i];
      if (!p) continue;
      var pName = (p.name || "").toLowerCase();
      if (pName.indexOf(q) !== -1) {
        result.push({
          id: p.id,
          name: p.name,
          total: p.total,
          waiting: p.waiting,
          latestTime: p.latestTime,
          sessions: Array.isArray(p.sessions) ? p.sessions.slice() : []
        });
      } else {
        var matchingSessions = [];
        if (Array.isArray(p.sessions)) {
          for (var j = 0; j < p.sessions.length; j++) {
            var s = p.sessions[j];
            if (s && (s.title || "").toLowerCase().indexOf(q) !== -1) {
              matchingSessions.push(s);
            }
          }
        }
        if (matchingSessions.length > 0) {
          result.push({
            id: p.id,
            name: p.name,
            total: p.total,
            waiting: p.waiting,
            latestTime: p.latestTime,
            sessions: matchingSessions
          });
        }
      }
    }
    return result;
  }

  function handoffMessagesOf(channels, tree, projectId, sessionId) {
    if (!channels || typeof channels !== "object") return [];

    var list = [];
    var channelMap = {};
    var channelCount = 0;

    var cNames = Object.keys(channels);
    for (var i = 0; i < cNames.length; i++) {
      var cName = cNames[i];
      var cData = channels[cName];
      if (!cData || !Array.isArray(cData.messages)) continue;

      for (var j = 0; j < cData.messages.length; j++) {
        var msg = cData.messages[j];
        if (!msg) continue;
        var node = handoffNodeOf(cName, msg, cData, tree);
        if (projectId && node.projectId !== projectId) continue;
        if (sessionId && node.sessionId !== sessionId) continue;

        var file = handoffMsgFileOf(msg, cData);
        if (!channelMap[cName]) {
          channelMap[cName] = true;
          channelCount++;
        }
        list.push({
          msg: msg,
          channel: cName,
          file: file,
          _seq: list.length
        });
      }
    }

    if (channelCount > 1) {
      list.sort(function (a, b) {
        var tA = (a.msg && a.msg.time) || "";
        var tB = (b.msg && b.msg.time) || "";
        if (tA !== tB) {
          return tA > tB ? 1 : -1;
        }
        return a._seq - b._seq;
      });
    }

    return list.map(function (it) {
      return {
        msg: it.msg,
        channel: it.channel,
        file: it.file
      };
    });
  }

  function findHandoffNodeTitles(treeNodes, projectId, sessionId) {
    var pName = "";
    var sTitle = "";
    if (!projectId) return { projectName: "", sessionTitle: "" };
    var list = Array.isArray(treeNodes) ? treeNodes : [];
    for (var i = 0; i < list.length; i++) {
      var p = list[i];
      if (p && p.id === projectId) {
        pName = p.name;
        if (sessionId && Array.isArray(p.sessions)) {
          for (var j = 0; j < p.sessions.length; j++) {
            if (p.sessions[j] && p.sessions[j].id === sessionId) {
              sTitle = p.sessions[j].title;
              break;
            }
          }
        }
        break;
      }
    }
    return {
      projectName: pName || projectId,
      sessionTitle: sTitle || sessionId
    };
  }

  function getQaTreeSortMode() {
    try {
      return normalizeTreeSortMode(localStorage.getItem("samjil.treeSort.qa.v1"));
    } catch (e) {
      return TREE_SORT_DEFAULT;
    }
  }

  function setQaTreeSortMode(mode) {
    try {
      localStorage.setItem("samjil.treeSort.qa.v1", normalizeTreeSortMode(mode));
    } catch (e) {}
  }

  function getHandoffTreeSortMode() {
    try {
      return normalizeTreeSortMode(localStorage.getItem("samjil.treeSort.handoff.v1"));
    } catch (e) {
      return TREE_SORT_DEFAULT;
    }
  }

  function setHandoffTreeSortMode(mode) {
    try {
      localStorage.setItem("samjil.treeSort.handoff.v1", normalizeTreeSortMode(mode));
    } catch (e) {}
  }

  // 사이드바 행(프로젝트·세션)에는 시각을 두 개 보인다.
  //   세션: Claude Desktop 세션의 마지막 활동. 프로젝트 행은 그 안의 세션들 중 가장 최근 활동.
  //   위임(에이전트 위임) / 인수인계(에이전트 협의): agy 쪽 기록의 시각.
  function treeSessionTime(node) {
    if (!node) return "";
    if (node.lastActivity) return String(node.lastActivity);
    var best = "";
    var list = Array.isArray(node.sessions) ? node.sessions : [];
    for (var i = 0; i < list.length; i++) {
      var t = String(list[i].lastActivity || "");
      if (t > best) { best = t; }
    }
    return best;
  }

  // 지금 도는(또는 대기 중인) 작업이 있고 그 시작이 마지막 완료보다 늦은가. 정렬(sortTreeNodes 의 recordTimeOf)과 같은 기준이다.
  function qaIsRunning(node) {
    return Boolean(node) && node.pending > 0 && Boolean(node.latestTime) && String(node.latestTime) > String(node.latestDone || "");
  }

  // 위임 쪽 값: 지금 진행 중인 작업이 있으면 "진행 N분"(시작한 뒤 흐른 시간), 아니면 마지막으로 끝난 agy 작업의 완료 시각.
  // 끝난 것이 없으면 진행 중인지, 위임이 아예 없는지 보인다. nowMs 는 시험에서 현재 시각을 고정하려는 값이다.
  function qaDelegationValue(node, nowMs) {
    if (qaIsRunning(node)) {
      var started = new Date(String(node.latestTime).replace(/-/g, "/"));
      if (isNaN(started.getTime())) return "진행 중";
      var sec = Math.floor(((nowMs == null ? Date.now() : nowMs) - started.getTime()) / 1000);
      if (sec < 60) return "진행 중";
      if (sec < 3600) return "진행 " + Math.floor(sec / 60) + "분";
      if (sec < 86400) return "진행 " + Math.floor(sec / 3600) + "시간";
      return "진행 " + Math.floor(sec / 86400) + "일";
    }
    if (node && node.latestDone) return formatRelativeTime(node.latestDone, nowMs);
    if (node && node.pending > 0) return "진행 중";
    return "없음";
  }

  // 위임 쪽 값의 정확한 시각(마우스를 올릴 때 보이는 설명). 진행 중이면 시작 시각을 그렇게 밝힌다.
  function qaDelegationAbs(node) {
    if (qaIsRunning(node)) return node.latestTime + " 부터 진행 중";
    return (node && node.latestDone) || "";
  }

  // 시각 두 개를 한 줄에 보인다: "세션 시각 / agy 쪽 시각". 색으로 구분한다 - 세션은 Claude 색, 위임·인수인계는 agy 색.
  // 사이드바 위의 범례와, 각 시각에 마우스를 올릴 때 뜨는 설명(이름 + 정확한 날짜·시각)이 뜻을 알려 준다.
  function treeTimePairHtml(cls, sessNode, agyLabel, agyText, agyAbs, extraHtml) {
    var st = treeSessionTime(sessNode);
    var sText = st ? formatRelativeTime(st) : "-";
    var sTitle = "세션 " + (st || "정보 없음");
    var aTitle = agyLabel + " " + (agyAbs || agyText);
    return '<span class="' + cls + ' tree-times">' +
      '<span class="tt tt-session' + (st ? "" : " is-empty") + '" title="' + escapeHtml(sTitle) + '">' + escapeHtml(sText) + '</span>' +
      '<span class="tt-sep">/</span>' +
      '<span class="tt tt-agy' + (agyAbs ? "" : " is-empty") + '" title="' + escapeHtml(aTitle) + '">' + escapeHtml(agyText) + '</span>' +
      (extraHtml || "") + '</span>';
  }

  // 에이전트 위임 화면의 날짜 정렬은 agy 작업(위임 기록) 시각 기준이라 라벨도 그렇게 보인다
  function qaSortLabel(m) {
    if (m.value === "recent-desc") return "agy 최근 작업순";
    if (m.value === "recent-asc") return "agy 오래된 작업순";
    return m.label;
  }

  function initTreeSortSelects() {
    if (els.qaTreeSort) {
      els.qaTreeSort.innerHTML = "";
      TREE_SORT_MODES.forEach(function (m) {
        var opt = document.createElement("option");
        opt.value = m.value;
        opt.textContent = qaSortLabel(m);
        els.qaTreeSort.appendChild(opt);
      });
      els.qaTreeSort.value = getQaTreeSortMode();
      els.qaTreeSort.addEventListener("change", function () {
        setQaTreeSortMode(this.value);
        renderQaTree();
      });
    }
    if (els.handoffTreeSort) {
      els.handoffTreeSort.innerHTML = "";
      TREE_SORT_MODES.forEach(function (m) {
        var opt = document.createElement("option");
        opt.value = m.value;
        opt.textContent = m.label;
        els.handoffTreeSort.appendChild(opt);
      });
      els.handoffTreeSort.value = getHandoffTreeSortMode();
      els.handoffTreeSort.addEventListener("change", function () {
        setHandoffTreeSortMode(this.value);
        renderHandoffTree();
      });
    }
  }

  var QA_TREE_OPEN_KEY = "samjil.qaTreeOpen.v1";

  function getQaTreeOpenMap() {
    try {
      var raw = localStorage.getItem(QA_TREE_OPEN_KEY);
      if (raw) {
        var parsed = JSON.parse(raw);
        if (parsed && typeof parsed === "object") return parsed;
      }
    } catch (e) {}
    return {};
  }

  function setQaTreeOpen(projectId, isOpen) {
    if (!projectId) return;
    try {
      var map = getQaTreeOpenMap();
      map[projectId] = Boolean(isOpen);
      localStorage.setItem(QA_TREE_OPEN_KEY, JSON.stringify(map));
    } catch (e) {}
  }

  function isQaProjectOpen(projectId, hasSearchQuery) {
    if (hasSearchQuery) return true;
    var map = getQaTreeOpenMap();
    if (Object.prototype.hasOwnProperty.call(map, projectId)) {
      return Boolean(map[projectId]);
    }
    if (currentQaProject === projectId) return true;
    return false;
  }

  function renderQaTree() {
    if (!els.qaSessionList) return;

    var allNodes = buildQaTree(allItems, pendingItems, claudeTree, { source: qaSource });
    if (els.qaSessionCount) {
      els.qaSessionCount.textContent = allNodes.length;
    }

    var q = (els.qaSessionSearch && els.qaSessionSearch.value || "").trim().toLowerCase();
    var filtered = qaFilterTree(allNodes, q);
    var sorted = sortTreeNodes(filtered, getQaTreeSortMode(), { dateSource: "records" });
    var hasQuery = Boolean(q);

    var frag = document.createDocumentFragment();

    var feedCount = 0;
    if (qaSource === "all") {
      feedCount = allItems.length + pendingItems.length;
    } else {
      feedCount = allItems.filter(function (r) { return qaItemMatchesSelection(r, claudeTree, "", "", qaSource); }).length +
        pendingItems.filter(function (p) { return qaItemMatchesSelection(p, claudeTree, "", "", qaSource); }).length;
    }

    // 1. [전체 프로젝트 피드] 항목
    var allItem = document.createElement("div");
    var isFeedActive = (currentQaProject === "" && currentQaSession === "");
    allItem.className = "project-item" + (isFeedActive ? " active" : "");
    allItem.dataset.project = "";
    allItem.innerHTML = [
      '<span class="project-icon">' + icon("feed") + '</span>',
      '<div class="project-info">',
      '  <span class="project-name">전체 프로젝트 피드</span>',
      '  <span class="project-sub session-sub">모든 위임을 시간순으로</span>',
      '</div>',
      '<span class="project-badge">' + feedCount + '</span>'
    ].join("");
    makeActivatable(allItem);
    allItem.onclick = function () { selectQaProject(""); };
    frag.appendChild(allItem);

    // 2. 프로젝트 트리 목록
    sorted.forEach(function (p) {
      var isOpen = isQaProjectOpen(p.id, hasQuery);
      var isProjectActive = (currentQaProject === p.id && currentQaSession === "");

      var pItem = document.createElement("div");
      var pClass = "project-item tree-project" + (p.source === "agy" ? " tree-project-agy" : "") + (isProjectActive ? " active" : "") + (isOpen ? " open" : "");
      pItem.className = pClass;
      pItem.dataset.project = p.id;
      pItem.setAttribute("role", "treeitem");
      pItem.setAttribute("aria-expanded", isOpen ? "true" : "false");

      var sessCount = p.sessions ? p.sessions.length : 0;
      // 시각 두 줄: 세션(Desktop 세션의 마지막 활동, 세션 개수 포함) / 위임(agy 작업의 완료 시각)
      var subHtml = treeTimePairHtml("project-sub session-sub", p, "위임", qaDelegationValue(p), qaDelegationAbs(p), '<span class="tree-time-count">' + sessCount + '개</span>');

      var badgeHtml = '<span class="project-badge">' + (p.total + p.pending) + '</span>';
      if (p.pending > 0) {
        badgeHtml = '<span class="pending-pulse-dot" title="진행/대기 중 ' + p.pending + '건"></span> ' + badgeHtml;
      }

      var srcBadge = p.source === "agy" ? '<span class="tree-src-badge is-agy">agy</span>' : '';

      pItem.innerHTML = [
        '<span class="project-icon">' + icon("folder") + '</span>',
        '<div class="project-info">',
        '  <span class="project-name" title="' + escapeHtml(p.name) + '">' + escapeHtml(p.name) + srcBadge + '</span>',
        '  ' + subHtml,
        '</div>',
        '<span class="tree-chevron" aria-hidden="true"></span>',
        badgeHtml
      ].join("");

      makeActivatable(pItem);

      var chevron = pItem.querySelector(".tree-chevron");
      if (chevron) {
        chevron.onclick = function (e) {
          e.stopPropagation();
          var nextState = !isOpen;
          setQaTreeOpen(p.id, nextState);
          renderQaTree();
        };
      }

      pItem.onclick = function () {
        // 스마트 토글: 이미 이 프로젝트의 전체 목록이 활성화된 상태에서 다시 누를 때만 접기/펼치기 토글
        // 하위 세션이 선택되어 있거나 다른 프로젝트에서 진입 시에는 항상 목록을 펼친 상태(open)로 유지
        var isAlreadyProjectActive = (currentQaProject === p.id && !currentQaSession);
        var nextOpen = isAlreadyProjectActive ? !isOpen : true;
        currentQaProject = p.id;
        currentQaSession = "";
        setQaTreeOpen(p.id, nextOpen);
        renderQaTree();
        updateBreadcrumbs();
        updateHash();
        applyQaFilters();
      };

      frag.appendChild(pItem);

      // 세션 목록
      if (isOpen && p.sessions && p.sessions.length > 0) {
        var groupDiv = document.createElement("div");
        groupDiv.className = "tree-children";
        groupDiv.setAttribute("role", "group");

        p.sessions.forEach(function (s) {
          var isSessionActive = (currentQaProject === p.id && currentQaSession === s.id);
          var sItem = document.createElement("div");
          sItem.className = "session-item tree-session" + (isSessionActive ? " active" : "") + (s.forkDepth ? " fork-child" : "");
          if (s.forkDepth) { sItem.style.setProperty("--fork-depth", String(Math.min(s.forkDepth, 3))); sItem.title = "포크한 세션"; }
          sItem.dataset.session = s.id;
          sItem.setAttribute("role", "treeitem");

          var sSubHtml = treeTimePairHtml("session-sub", s, "위임", qaDelegationValue(s), qaDelegationAbs(s), "");

          var sBadgeHtml = '<span class="session-badge">' + (s.total + s.pending) + '</span>';
          if (s.pending > 0) {
            sBadgeHtml = '<span class="pending-pulse-dot" title="진행/대기 중 ' + s.pending + '건"></span> ' + sBadgeHtml;
          }

          var archivedHtml = s.archived ? '<span class="tree-archived">(보관됨)</span>' : '';

          sItem.innerHTML = [
            '<span class="session-icon">' + icon("thread") + '</span>',
            '<div class="session-info">',
            '  <span class="session-name" title="' + escapeHtml(s.title) + '">' + escapeHtml(s.title) + archivedHtml + '</span>',
            '  ' + sSubHtml,
            '</div>',
            sBadgeHtml
          ].join("");

          makeActivatable(sItem);
          sItem.onclick = function () {
            selectQaSession(s.id, p.id);
          };

          groupDiv.appendChild(sItem);
        });

        frag.appendChild(groupDiv);
      }
    });

    var prevScroll = els.qaSessionList.scrollTop;
    els.qaSessionList.innerHTML = "";
    els.qaSessionList.appendChild(frag);
    els.qaSessionList.scrollTop = prevScroll;
  }

  function selectQaAgy(agy) {
    currentQaAgy = agy || "";
    renderQaAgyChips();
    updateHash();
    applyQaFilters();
  }

  function selectQaProject(id, forceOpen) {
    currentQaAgy = "";
    currentQaProject = id || "";
    currentQaSession = "";
    if (currentQaProject && forceOpen !== false) {
      setQaTreeOpen(currentQaProject, true);
    }
    renderQaTree();
    updateBreadcrumbs();
    updateHash();
    applyQaFilters();
  }

  function selectQaSession(sessionId, projectId) {
    currentQaAgy = "";
    currentQaSession = sessionId || "";
    if (projectId !== undefined) {
      currentQaProject = projectId || "";
    } else {
      if (sessionId) {
        var tree = buildQaTree(allItems, pendingItems, claudeTree);
        var foundProject = null;
        for (var i = 0; i < tree.length; i++) {
          var p = tree[i];
          if (p && p.sessions) {
            for (var j = 0; j < p.sessions.length; j++) {
              if (p.sessions[j] && p.sessions[j].id === sessionId) {
                foundProject = p.id;
                break;
              }
            }
          }
          if (foundProject !== null) break;
        }
        if (foundProject !== null) {
          currentQaProject = foundProject;
        } else {
          currentQaSession = "";
          currentQaProject = "";
        }
      } else {
        currentQaProject = "";
      }
    }
    if (currentQaProject) {
      setQaTreeOpen(currentQaProject, true);
    }
    renderQaTree();
    updateBreadcrumbs();
    updateHash();
    applyQaFilters();
  }

  function findRepresentativeItemBySessionName(sName) {
    var pends = Array.isArray(pendingItems) ? pendingItems : [];
    for (var i = 0; i < pends.length; i++) {
      var p = pends[i];
      var s = (p && p.session != null && String(p.session).trim() !== "") ? String(p.session) : "__none__";
      if (s === sName) return p;
    }
    var recs = Array.isArray(allItems) ? allItems : [];
    for (var j = 0; j < recs.length; j++) {
      var r = recs[j];
      var s2 = (r && r.session != null && String(r.session).trim() !== "") ? String(r.session) : "__none__";
      if (s2 === sName) return r;
    }
    return null;
  }

  // ==========================================================================
  // Handoff Tree & Selection Management
  // ==========================================================================

  var HANDOFF_TREE_OPEN_KEY = "samjil.handoffTreeOpen.v1";

  function getHandoffTreeOpenMap() {
    try {
      var raw = localStorage.getItem(HANDOFF_TREE_OPEN_KEY);
      if (raw) {
        var parsed = JSON.parse(raw);
        if (parsed && typeof parsed === "object") return parsed;
      }
    } catch (e) {}
    return {};
  }

  function setHandoffTreeOpen(projectId, isOpen) {
    if (!projectId) return;
    try {
      var map = getHandoffTreeOpenMap();
      map[projectId] = Boolean(isOpen);
      localStorage.setItem(HANDOFF_TREE_OPEN_KEY, JSON.stringify(map));
    } catch (e) {}
  }

  function isHandoffProjectOpen(projectId, hasSearchQuery) {
    if (hasSearchQuery) return true;
    var map = getHandoffTreeOpenMap();
    if (Object.prototype.hasOwnProperty.call(map, projectId)) {
      return Boolean(map[projectId]);
    }
    if (currentHandoffProject === projectId) return true;
    return false;
  }

  function renderHandoffTree() {
    if (!els.handoffProjectList) return;

    var allNodes = buildHandoffTree(handoffChannels, claudeTree);
    if (els.handoffProjectCount) {
      els.handoffProjectCount.textContent = allNodes.length;
    }

    var q = (els.handoffProjectSearch && els.handoffProjectSearch.value || "").trim().toLowerCase();
    var filtered = handoffFilterTree(allNodes, q);
    var sorted = sortTreeNodes(filtered, getHandoffTreeSortMode());
    var hasQuery = Boolean(q);

    // 전체 메시지 수 계산
    var totalAllMsgs = 0;
    if (handoffChannels && typeof handoffChannels === "object") {
      for (var cKey in handoffChannels) {
        var cVal = handoffChannels[cKey];
        if (cVal && Array.isArray(cVal.messages)) {
          totalAllMsgs += cVal.messages.length;
        }
      }
    }

    var frag = document.createDocumentFragment();

    // 1. [전체 프로젝트] 항목
    var allItem = document.createElement("div");
    var isFeedActive = (currentHandoffProject === "" && currentHandoffSession === "");
    allItem.className = "project-item" + (isFeedActive ? " active" : "");
    allItem.dataset.project = "";
    allItem.innerHTML = [
      '<span class="project-icon">' + icon("feed") + '</span>',
      '<div class="project-info">',
      '  <span class="project-name">전체 프로젝트</span>',
      '  <span class="project-sub session-sub">모든 협의를 시간순으로</span>',
      '</div>',
      '<span class="project-badge">' + totalAllMsgs + '</span>'
    ].join("");
    makeActivatable(allItem);
    allItem.onclick = function () { selectHandoffProject(""); };
    frag.appendChild(allItem);

    // 2. 프로젝트 트리 목록
    sorted.forEach(function (p) {
      var isOpen = isHandoffProjectOpen(p.id, hasQuery);
      var isProjectActive = (currentHandoffProject === p.id && currentHandoffSession === "");

      var pItem = document.createElement("div");
      var pClass = "project-item tree-project" + (isProjectActive ? " active" : "") + (isOpen ? " open" : "");
      pItem.className = pClass;
      pItem.dataset.project = p.id;
      pItem.setAttribute("role", "treeitem");
      pItem.setAttribute("aria-expanded", isOpen ? "true" : "false");

      var sessCount = p.sessions ? p.sessions.length : 0;
      var waitHtml = p.waiting > 0 ? '<span class="tree-time-count who-agy">대기 중 ' + p.waiting + '</span>' : '';
      // 시각 두 줄: 세션(Desktop 세션의 마지막 활동, 세션 개수 포함) / 인수인계(마지막 메시지 시각)
      var subHtml = treeTimePairHtml("project-sub session-sub", p, "협의", p.latestTime ? formatRelativeTime(p.latestTime) : "없음", p.latestTime, '<span class="tree-time-count">' + sessCount + '개</span>' + waitHtml);

      var badgeHtml = '<span class="project-badge">' + p.total + '</span>';
      if (p.waiting > 0) {
        badgeHtml = '<span class="pending-pulse-dot" title="대기 중 ' + p.waiting + '건"></span> ' + badgeHtml;
      }

      pItem.innerHTML = [
        '<span class="project-icon">' + icon("folder") + '</span>',
        '<div class="project-info">',
        '  <span class="project-name" title="' + escapeHtml(p.name) + '">' + escapeHtml(p.name) + '</span>',
        '  ' + subHtml,
        '</div>',
        '<span class="tree-chevron" aria-hidden="true"></span>',
        badgeHtml
      ].join("");

      makeActivatable(pItem);

      var chevron = pItem.querySelector(".tree-chevron");
      if (chevron) {
        chevron.onclick = function (e) {
          e.stopPropagation();
          var nextState = !isOpen;
          setHandoffTreeOpen(p.id, nextState);
          renderHandoffTree();
        };
      }

      pItem.onclick = function () {
        // 스마트 토글: 이미 이 프로젝트의 전체 목록이 활성화된 상태에서 다시 누를 때만 접기/펼치기 토글
        // 하위 세션이 선택되어 있거나 다른 프로젝트에서 진입 시에는 항상 목록을 펼친 상태(open)로 유지
        var isAlreadyProjectActive = (currentHandoffProject === p.id && !currentHandoffSession);
        var nextOpen = isAlreadyProjectActive ? !isOpen : true;
        currentHandoffProject = p.id;
        currentHandoffSession = "";
        setHandoffTreeOpen(p.id, nextOpen);
        renderHandoffTree();
        updateBreadcrumbs();
        updateHash();
        renderHandoffView();
      };

      frag.appendChild(pItem);

      // 세션 목록
      if (isOpen && p.sessions && p.sessions.length > 0) {
        var groupDiv = document.createElement("div");
        groupDiv.className = "tree-children";
        groupDiv.setAttribute("role", "group");

        p.sessions.forEach(function (s) {
          var isSessionActive = (currentHandoffProject === p.id && currentHandoffSession === s.id);
          var sItem = document.createElement("div");
          sItem.className = "session-item tree-session" + (isSessionActive ? " active" : "") + (s.forkDepth ? " fork-child" : "");
          if (s.forkDepth) { sItem.style.setProperty("--fork-depth", String(Math.min(s.forkDepth, 3))); sItem.title = "포크한 세션"; }
          sItem.dataset.session = s.id;
          sItem.setAttribute("role", "treeitem");

          var sWaitHtml = s.waiting > 0 ? '<span class="tree-time-count who-agy">대기 중 ' + s.waiting + '</span>' : '';
          var sSubHtml = treeTimePairHtml("session-sub", s, "협의", s.latestTime ? formatRelativeTime(s.latestTime) : "없음", s.latestTime, sWaitHtml);

          var sBadgeHtml = '<span class="session-badge">' + s.total + '</span>';
          if (s.waiting > 0) {
            sBadgeHtml = '<span class="pending-pulse-dot" title="대기 중 ' + s.waiting + '건"></span> ' + sBadgeHtml;
          }

          var archivedHtml = s.archived ? '<span class="tree-archived">(보관됨)</span>' : '';

          sItem.innerHTML = [
            '<span class="session-icon">' + icon("thread") + '</span>',
            '<div class="session-info">',
            '  <span class="session-name" title="' + escapeHtml(s.title) + '">' + escapeHtml(s.title) + archivedHtml + '</span>',
            '  ' + sSubHtml,
            '</div>',
            sBadgeHtml
          ].join("");

          makeActivatable(sItem);
          sItem.onclick = function () {
            selectHandoffSession(s.id, p.id);
          };

          groupDiv.appendChild(sItem);
        });

        frag.appendChild(groupDiv);
      }
    });

    var prevScroll = els.handoffProjectList.scrollTop;
    els.handoffProjectList.innerHTML = "";
    els.handoffProjectList.appendChild(frag);
    els.handoffProjectList.scrollTop = prevScroll;
  }

  function selectHandoffProject(id, forceOpen) {
    if (id && handoffChannels && handoffChannels[id]) {
      var tree = buildHandoffTree(handoffChannels, claudeTree);
      var isRealProject = false;
      for (var pi = 0; pi < tree.length; pi++) {
        if (tree[pi] && tree[pi].id === id) {
          isRealProject = true;
          break;
        }
      }
      if (!isRealProject) {
        selectHandoffSession("c:" + id, QA_UNLINKED);
        return;
      }
    }
    currentHandoffProject = id || "";
    currentHandoffSession = "";
    if (currentHandoffProject && forceOpen !== false) {
      setHandoffTreeOpen(currentHandoffProject, true);
    }
    renderHandoffTree();
    updateBreadcrumbs();
    updateHash();
    renderHandoffView();
  }

  function selectHandoffSession(sessionId, projectId) {
    currentHandoffSession = sessionId || "";
    if (projectId !== undefined) {
      currentHandoffProject = projectId || "";
    } else {
      if (sessionId) {
        var tree = buildHandoffTree(handoffChannels, claudeTree);
        var foundProject = null;
        for (var i = 0; i < tree.length; i++) {
          var p = tree[i];
          if (p && p.sessions) {
            for (var j = 0; j < p.sessions.length; j++) {
              if (p.sessions[j] && p.sessions[j].id === sessionId) {
                foundProject = p.id;
                break;
              }
            }
          }
          if (foundProject !== null) break;
        }
        if (foundProject !== null) {
          currentHandoffProject = foundProject;
        } else {
          currentHandoffSession = "";
          currentHandoffProject = "";
        }
      } else {
        currentHandoffProject = "";
      }
    }
    if (currentHandoffProject) {
      setHandoffTreeOpen(currentHandoffProject, true);
    }
    renderHandoffTree();
    updateBreadcrumbs();
    updateHash();
    renderHandoffView();
  }

  // ==========================================================================
  // 1. 대시보드 뷰 렌더링: 지금 / 확인 필요 / 최근 활동 / 누적
  // ==========================================================================

  var STATUS_STEPS = { "보냄": 1, "읽음": 2, "처리됨": 3, "확인함": 4 };

  function renderDashboard() {
    if (currentNav !== "dashboard") return;
    renderNow();
    renderAccountQuotas();
    renderAttention();
    renderTimeline();
    renderStats();
    renderQuickSessions();
  }

  // 아직 완료 기록이 없는 inbox 작업만 남기고, 그중 processing 상태인 한 건을 고른다.
  function activePending() {
    var finished = {};
    allItems.forEach(function (r) { if (r && r.task_id) { finished[r.task_id] = true; } });
    return pendingItems.filter(function (p) { return p && p.task_id && !finished[p.task_id]; });
  }

  // 진행 중인 위임 카드의 경과 시간을 1초마다 갱신한다. 카드는 새로고침 때 다시 그려지므로 DOM을 매번 훑는다.
  setInterval(function () {
    var els2 = document.querySelectorAll(".live-elapsed[data-start]");
    for (var i = 0; i < els2.length; i++) {
      var pfx = els2[i].getAttribute("data-label-prefix") || "";
      (els2[i].querySelector(".mv") || els2[i]).textContent = pfx + formatDuration((Date.now() - Number(els2[i].getAttribute("data-start"))) / 1000);
    }
    var idles = document.querySelectorAll(".pg-idle[data-ms]");
    for (var j = 0; j < idles.length; j++) {
      var idleSec = (Date.now() - Number(idles[j].getAttribute("data-ms"))) / 1000;
      idles[j].textContent = formatDuration(idleSec) + " 전 활동";
      idles[j].classList.toggle("quiet", idleSec >= PROGRESS_QUIET_SEC);
    }
    tickHealthElements();
  }, 1000);

  function stopNowTicker() {
    if (nowTicker) { clearInterval(nowTicker); nowTicker = null; }
  }

  function renderNow() {
    if (!els.dashNow) return;
    stopNowTicker();

    var active = activePending();
    var running = null;
    var runningCount = 0;    // 워처가 작업을 동시에 여러 개 돌릴 수 있다
    for (var i = 0; i < active.length; i++) {
      if (active[i].state === "processing") { runningCount++; if (!running) { running = active[i]; } }
    }
    var queued = active.length - runningCount;

    var state, statusText, title;
    var aside = "";
    var meta = [];
    var clickItem = null;

    if (!hasLoadedStatusOnce) {
      state = "loading";
      statusText = "상태 확인 중";
      title = "잠시만 기다려 주세요";
      meta.push('<span class="skel skel-sm" aria-hidden="true"></span>');
      meta.push('<span class="skel skel-xs" aria-hidden="true"></span>');
      meta.push('<span class="skel skel-md" aria-hidden="true"></span>');
    } else if (!isServerOnline) {
      state = "offline";
      statusText = "뷰어 서버에 연결할 수 없습니다";
      title = "serve-viewer.ps1이 실행 중인지 확인하세요";
      meta.push('<span><code>~/.samjil/viewer/serve-viewer.ps1</code>을 다시 실행하면 이 화면이 이어서 갱신됩니다.</span>');
    } else if (running) {
      state = "running";
      statusText = runningCount > 1 ? "agy가 " + runningCount + "건을 동시에 작업 중" : "agy가 작업 중";
      if (queued > 0) { aside = "대기 " + queued + "건"; }
      title = extractQuestionKeyword(running.question) || "(질문 내용 없음)";
      if (running.model) { meta.push('<span>모델 <code>' + escapeHtml(running.model) + '</code></span>'); }
      meta.push('<span>' + (running.session ? "세션 " + escapeHtml(running.session) : "단발성 작업") + '</span>');
      var created = parseLocalTime(running.created);
      if (created) {
        meta.push('<span>접수 후 <span class="elapsed" id="now-elapsed">' +
          formatDuration((Date.now() - created.getTime()) / 1000) + '</span></span>');
        nowTicker = setInterval(function () {
          var el = document.getElementById("now-elapsed");
          if (!el) { stopNowTicker(); return; }
          el.textContent = formatDuration((Date.now() - created.getTime()) / 1000);
        }, 1000);
      }
      clickItem = running;
    } else if (systemStatus && systemStatus.watcherAlive) {
      state = "idle";
      statusText = "agy 워처 대기 중";
      var last = allItems[0];
      if (last) {
        title = "마지막 위임: " + (extractQuestionKeyword(last.question) || "(질문 내용 없음)");
        meta.push('<span>' + formatRelativeTime(last.timestamp) + '</span>');
        meta.push('<span>' + (isOkStatus(last) ? "성공" : (last.status ? "실패 (" + escapeHtml(last.status) + ")" : "상태 미기록")) + '</span>');
        if (recordModel(last)) { meta.push('<span><code title="' + escapeHtml(recordModel(last)) + '">' + escapeHtml(shortAgyModel(recordModel(last))) + '</code></span>'); }
        clickItem = last;
      } else {
        title = "아직 위임 기록이 없습니다";
      }
    } else {
      state = "stopped";
      statusText = "agy 워처가 꺼져 있습니다";
      var autoRestart = systemStatus && systemStatus.autoRestart;
      if (systemStatus && systemStatus.manualStop) {
        title = "stop-agy로 끈 상태라 자동으로 켜지 않습니다";
        meta.push('<span><code>~/.samjil/delegate-agy/scripts/start-agy.ps1</code>로 켤 수 있습니다.</span>');
      } else if (autoRestart && autoRestart.enabled) {
        title = "다음 점검 때 뷰어가 자동으로 다시 켭니다";
        meta.push('<span>뷰어가 ' + (autoRestart.intervalSeconds >= 60 ? Math.round(autoRestart.intervalSeconds / 60) + '분' : autoRestart.intervalSeconds + '초') + '마다 점검합니다.</span>');
        meta.push('<span>지금 바로 켜려면 <code>~/.samjil/delegate-agy/scripts/start-agy.ps1</code></span>');
        if (autoRestart.lastLaunch) { meta.push('<span>마지막 자동 재시작 ' + formatRelativeTime(autoRestart.lastLaunch) + '</span>'); }
      } else {
        title = "위임하려면 워처를 먼저 켜세요";
        meta.push('<span><code>~/.samjil/delegate-agy/scripts/start-agy.ps1</code>로 켤 수 있습니다.</span>');
      }
      if (queued > 0) { meta.push('<span>inbox에서 ' + queued + '건이 처리를 기다리고 있습니다.</span>'); }
    }

    if (state !== "offline" && state !== "running" && systemStatus && systemStatus.lastHeartbeat) {
      aside = "마지막 하트비트 " + formatRelativeTime(systemStatus.lastHeartbeat);
    }

    els.dashNow.setAttribute("data-state", state);
    els.nowStatusText.textContent = statusText;
    els.nowAside.textContent = aside;
    els.nowTitle.textContent = title;
    els.nowMeta.innerHTML = meta.join("");

    els.nowTitle.classList.toggle("is-link", clickItem !== null);
    if (clickItem !== null) {
      makeActivatable(els.nowTitle);
      els.nowTitle.onclick = function () {
        var node = qaNodeOf(clickItem, claudeTree);
        selectQaSession(node.sessionId, node.projectId);
        switchNav("qa");
      };
    } else {
      els.nowTitle.removeAttribute("tabindex");
      els.nowTitle.removeAttribute("role");
      els.nowTitle.onclick = null;
    }

    renderOutcomeStrip();
  }

  // 최근 위임 결과를 한 칸에 한 건씩, 오래된 것부터 왼쪽에 놓는다.
  function renderOutcomeStrip() {
    if (!els.outcomeStrip) return;
    if (!hasLoadedStatusOnce) {
      els.outcomeStrip.innerHTML = '<span class="skel skel-strip" aria-hidden="true"></span>';
      return;
    }
    var recent = allItems.filter(function (r) { return r && r.status; }).slice(0, 30).reverse();
    if (recent.length === 0) {
      els.outcomeStrip.innerHTML = "";
      return;
    }
    var errs = 0;
    var html = recent.map(function (r) {
      var ok = isOkStatus(r);
      if (!ok) { errs++; }
      var tip = (r.timestamp || "") + "  " + (ok ? "성공" : "실패") + (recordModel(r) ? "  " + recordModel(r) : "");
      return '<span class="tick ' + (ok ? "ok" : "err") + '" title="' + escapeHtml(tip) + '"></span>';
    }).join("");
    var label = "최근 " + recent.length + "건 " + (errs === 0 ? "모두 성공" : "중 실패 " + errs + "건");
    els.outcomeStrip.innerHTML = html + '<span class="strip-label">' + label + '</span>';
    els.outcomeStrip.setAttribute("aria-label", label);
  }

  function stepsHtml(status) {
    var step = STATUS_STEPS[status] || 0;
    var hold = (status === "보류");
    return '<span class="steps' + (hold ? " on-hold" : "") + '" data-step="' + step + '" title="보냄 → 읽음 → 처리됨 → 확인함">' +
      '<span class="steps-track" aria-hidden="true"><i></i><i></i><i></i><i></i></span>' +
      '<span class="steps-label">' + escapeHtml(status || "상태 없음") + '</span></span>';
  }

  // 핸드오프 채널 이름 -> 워처가 위임 작업 이름(handoff_<이름>_<번호>_<시각>)에 쓰는 이름.
  // handoff-pump.ps1 의 ConvertTo-HandoffSafeName 와 같은 규칙이다(영문·숫자·한글·_· - 만 남기고 40자까지).
  function handoffSafeName(name) {
    var s = String(name == null ? "" : name).replace(/[^A-Za-z0-9가-힣_-]+/g, "-").replace(/^-+|-+$/g, "");
    if (!s) s = "channel";
    if (s.length > 40) s = s.substring(0, 40).replace(/-+$/g, "");
    return s;
  }

  // 토큰 수를 짧게: 1만 이상은 "2.4만", 그 밖에는 천 단위 쉼표.
  function tokenShort(n) {
    n = Number(n) || 0;
    return n >= 10000 ? (n / 10000).toFixed(1) + "만" : n.toLocaleString();
  }

  function tokenRecordKey(r) { return r && r.task_id ? String(r.task_id) : "t:" + String(r && r.timestamp || ""); }

  // 한 채널의 핸드오프 위임 기록(위임 완료 레코드)에서 "메시지 번호 -> 그 호출이 쓴 토큰"을 만든다.
  // 레코드의 task_id 는 handoff_<채널>_<c2a 번호>_<시각> 이다. agy 는 채널마다 대화 하나를 이어 쓰고 usage 는 그 대화의 누적값이라,
  // 같은 대화(session_id)의 앞 호출과의 차이를 "이번 호출이 쓴 양"으로 본다. 앞 호출보다 줄었거나 앞 호출이 없으면(새 대화) 그 값이 곧 이번 호출이다.
  function handoffUsageIndex(channel, records) {
    var prefix = "handoff_" + handoffSafeName(channel) + "_";
    var num = function (v) { var n = parseInt(v, 10); return isNaN(n) ? 0 : n; };
    var list = [];
    (Array.isArray(records) ? records : []).forEach(function (r) {
      var id = r && r.task_id ? String(r.task_id) : "";
      if (id.indexOf(prefix) !== 0) { return; }
      var mm = /^(\d{4})_\d+$/.exec(id.slice(prefix.length));
      if (!mm) { return; }
      var total = num(r.total_tokens);
      if (total <= 0) { return; }
      list.push({
        num: mm[1], ts: String(r.timestamp || ""), sid: String(r.session_id || r.session || ""), model: String(r.model || ""),
        input: num(r.input_tokens), output: num(r.output_tokens), thinking: num(r.thinking_tokens), total: total,
        cum_total: num(r.cum_total_tokens), cum_input: num(r.cum_input_tokens), cum_output: num(r.cum_output_tokens), cum_thinking: num(r.cum_thinking_tokens),
        usage_basis: r && r.usage_basis ? String(r.usage_basis) : ""
      });
    });
    list.sort(function (a, b) { return a.ts < b.ts ? -1 : (a.ts > b.ts ? 1 : 0); });
    var prev = {};
    var out = {};
    list.forEach(function (c) {
      var p = prev[c.sid];
      var baseline = true;
      var d = { input: c.input, output: c.output, thinking: c.thinking, total: c.total };
      if (c.usage_basis) {
        baseline = (c.usage_basis === "own");
        var cumTotal = c.cum_total || (p ? p.cum_total + c.total : c.total);
        var cumIn = c.cum_input || (p ? p.cum_in + c.input : c.input);
        var cumOut = c.cum_output || (p ? p.cum_out + c.output : c.output);
        var cumThink = c.cum_thinking || (p ? p.cum_think + c.thinking : c.thinking);
        c.cum_total = cumTotal; c.cum_in = cumIn; c.cum_out = cumOut; c.cum_think = cumThink;
        out[c.num] = { num: c.num, model: c.model, ts: c.ts, delta: d, cumulative: { input: cumIn, output: cumOut, thinking: cumThink, total: cumTotal }, baseline: baseline };
      } else {
        if (p && c.total >= p.total && c.input >= p.input && c.output >= p.output && c.thinking >= p.thinking) {
          baseline = false;
          d = { input: c.input - p.input, output: c.output - p.output, thinking: c.thinking - p.thinking, total: c.total - p.total };
        }
        out[c.num] = { num: c.num, model: c.model, ts: c.ts, delta: d, cumulative: { input: c.input, output: c.output, thinking: c.thinking, total: c.total }, baseline: baseline };
      }
      prev[c.sid] = c;
    });
    return out;
  }

  // 머리줄 칩 글자와 설명(title). 설명은 이 숫자가 대화 누적에서 뺀 증가분이라는 것과 세부 값을 알려 준다.
  function handoffUsageText(u) {
    if (!u || !u.delta) { return null; }
    var d = u.delta, c = u.cumulative;
    var sign = u.baseline ? "" : "+";
    var tip = [
      u.baseline ? "이 대화의 첫 호출(누적값이 곧 이번 호출)" : "이번 호출이 쓴 양 (agy 대화 누적값의 증가분)",
      "총 " + sign + d.total.toLocaleString() + " · 입력 " + sign + d.input.toLocaleString() + " · 출력 " + sign + d.output.toLocaleString() + " · 사고 " + sign + d.thinking.toLocaleString(),
      "대화 누적 총 " + c.total.toLocaleString() + " 토큰" + (u.model ? " · " + u.model : "")
    ].join("\n");
    return { chip: sign + tokenShort(d.total) + " 토큰", title: tip, delta: d, cumulative: c, baseline: u.baseline };
  }

  // Claude 가 보낸 c2a 카드의 사용량(근사). u 는 서버(/api/handoff/claude-usage)가 돌려준 호출 하나의 값:
  //   front = 출력 + 새 입력(이 호출이 한 일의 크기), context = 그 호출이 본 대화 맥락의 크기(캐시에서 다시 읽은 입력 포함).
  // 맥락은 호출마다 대화 전체가 거의 그대로 다시 읽혀 "이 메시지에 든 양"이 아니라서 앞에 두지 않고 따로 보인다.
  function claudeUsageText(u) {
    if (!u || typeof u.front !== "number") { return null; }
    var n = function (v) { return Number(v || 0).toLocaleString(); };
    var tip = [
      "이 메시지를 만든 Claude 호출 한 번의 사용량 (근사치)",
      "출력 " + n(u.output) + " + 새 입력 " + n(u.newInput) + " = " + n(u.front) + " 토큰",
      "새 입력 = 이 호출에서 처음 들어간 맥락(일반 입력 + 캐시에 새로 쓴 입력)",
      "대화 맥락 " + n(u.context) + " 토큰 = 새 입력 + 캐시에서 다시 읽은 " + n(u.cacheRead) + " (맥락 크기이지 이 메시지에 든 양이 아닙니다)",
      "근사치인 이유: 어느 호출이 메시지를 만들었는지는 기록에 없어 파일이 생긴 시각 바로 앞의 호출로 짐작했고, 그 호출 안의 다른 일도 함께 들어 있으며, 메시지를 만들기까지 이어진 다른 호출은 빠졌습니다." + (u.model ? "\n모델 " + u.model : "")
    ].join("\n");
    return { chip: "≈" + tokenShort(u.front) + " 토큰", title: tip, output: u.output, newInput: u.newInput, front: u.front, context: u.context };
  }

  // 펼친 c2a 카드의 Claude 사용량 줄(agy 쪽 줄과 같은 모양, 앞에는 한 일의 크기, 맥락은 따로).
  function buildClaudeUsageEl(t) {
    var el = document.createElement("div");
    el.className = "handoff-usage is-claude";
    el.title = t.title;
    var items = [["출력", t.output.toLocaleString()], ["새 입력", t.newInput.toLocaleString()], ["합계", "≈" + t.front.toLocaleString()]];
    el.innerHTML = '<span class="handoff-usage-head">Claude 사용량 · 근사</span>' + items.map(function (it) {
      return '<span class="handoff-usage-item"><span class="handoff-usage-k">' + escapeHtml(it[0]) + '</span> ' + escapeHtml(it[1]) + '</span>';
    }).join("") + '<span class="handoff-usage-item handoff-usage-ctx"><span class="handoff-usage-k">대화 맥락</span> ' + escapeHtml(t.context.toLocaleString()) + '</span>';
    return el;
  }

  // c2a 메시지가 붙은 세션의 기록에서 읽은 값을 세션|생성시각 키로 모아 둔다. 값이 없으면(못 찾음) false 로 두어 다시 묻지 않는다.
  var claudeUsageStore = {};
  var claudeUsageAsked = {};
  var claudeUsageQueue = {};
  var claudeUsageTimer = null;

  function claudeUsageFor(channel, m) {
    if (!m || m.dir !== "c2a" || !m.created) { return null; }
    var node = handoffNodeOf(channel, m, handoffChannels[channel], claudeTree);
    if (!node || node.projectId === QA_UNLINKED || String(node.sessionId).indexOf("c:") === 0) { return null; }
    var key = node.sessionId + "|" + m.created;
    if (Object.prototype.hasOwnProperty.call(claudeUsageStore, key)) { return claudeUsageStore[key] || null; }
    if (!claudeUsageAsked[key]) {
      claudeUsageAsked[key] = true;
      (claudeUsageQueue[node.sessionId] = claudeUsageQueue[node.sessionId] || []).push(m.created);
      if (!claudeUsageTimer) { claudeUsageTimer = setTimeout(flushClaudeUsage, 0); }
    }
    return null;
  }

  // 모아 둔 요청을 세션별로 한 번에 보내고, 새 값이 있으면 카드를 다시 그린다.
  function flushClaudeUsage() {
    claudeUsageTimer = null;
    var queue = claudeUsageQueue;
    claudeUsageQueue = {};
    var sids = Object.keys(queue);
    if (!sids.length) { return; }
    Promise.all(sids.map(function (sid) {
      var all = queue[sid];
      var batches = [];
      for (var i = 0; i < all.length; i += 100) { batches.push(all.slice(i, i + 100)); }
      return Promise.all(batches.map(function (ts) {
        return fetchJson("/api/handoff/claude-usage?session=" + encodeURIComponent(sid) + "&ts=" + encodeURIComponent(ts.join(","))).then(function (res) {
          ts.forEach(function (t) { claudeUsageStore[sid + "|" + t] = (res && res.items && res.items[t]) ? res.items[t] : false; });
        }).catch(function () {
          ts.forEach(function (t) { claudeUsageStore[sid + "|" + t] = false; });
        });
      }));
    })).then(function () {
      if (currentNav === "handoff") { renderHandoffMessages(); }
    });
  }

  var handoffUsageCache = { key: "", maps: {} };
  // 렌더마다 채널별로 한 번만 만든다. 위임 기록이 바뀌면(개수나 가장 최근 시각) 다시 만든다.
  function handoffUsageFor(channel) {
    var key = allItems.length + "|" + (allItems[0] && allItems[0].timestamp || "");
    if (handoffUsageCache.key !== key) { handoffUsageCache = { key: key, maps: {} }; }
    if (!handoffUsageCache.maps[channel]) { handoffUsageCache.maps[channel] = handoffUsageIndex(channel, allItems); }
    return handoffUsageCache.maps[channel];
  }

  // 펼친 카드의 사용량 줄(에이전트 위임 카드의 토큰 줄과 같은 항목).
  function buildHandoffUsageEl(t) {
    var el = document.createElement("div");
    el.className = "handoff-usage";
    var s = t.baseline ? "" : "+";
    var items = [
      ["총 토큰", s + t.delta.total.toLocaleString()],
      ["입력", s + t.delta.input.toLocaleString()],
      ["출력", s + t.delta.output.toLocaleString()],
      ["사고", s + t.delta.thinking.toLocaleString()],
      ["대화 누적", t.cumulative.total.toLocaleString()]
    ];
    el.title = t.title;
    el.innerHTML = '<span class="handoff-usage-head">agy 사용량 · ' + (t.baseline ? "첫 호출" : "이번 호출") + '</span>' + items.map(function (it) {
      return '<span class="handoff-usage-item"><span class="handoff-usage-k">' + escapeHtml(it[0]) + '</span> ' + escapeHtml(it[1]) + '</span>';
    }).join("");
    return el;
  }

  function dirParty(dir) {
    return dir === "c2a" ? "claude" : (dir === "a2c" ? "agy" : null);
  }

  // 모델 ID -> 사람이 읽는 이름. 모르는 모양이면 추측하지 않고 그대로 돌려준다.
  //   claude-opus-4-5-20251101 -> Claude Opus 4.5 · claude-sonnet-5-5 -> Claude Sonnet 5.5 · claude-3-5-sonnet-20241022 -> Claude 3.5 Sonnet
  //   gemini-4-hydrogen-medium -> Gemini 4 Hydrogen (Medium) · gemini-4-neon-xhigh -> Gemini 4 Neon (Extra) · gemini-4-carbon-high -> Gemini 4 Carbon (High)
  //   gemini-pro-orchestrator-neon -> Orchestrator (Neon) · gemini-pro-orchestrator -> Orchestrator (Carbon) · gemini-pro-orchestrator-argon -> Orchestrator (Argon)
  //   gemini-3.8-flash-high -> Gemini 3.8 Flash (High) · "Claude Opus 5.5" 처럼 이미 사람이 쓴 이름(공백·대문자)은 그대로
  function formatModelName(raw) {
    var s = String(raw == null ? "" : raw).trim();
    if (!s) return "";
    if (/[\sA-Z]/.test(s)) return s;
    s = s.replace(/\[[^\]]*\]$/, "");
    var cap = function (w) { return w.charAt(0).toUpperCase() + w.slice(1); };
    var m = s.match(/^claude-(opus|sonnet|haiku|fable)-(\d+)(?:-(\d{1,2}))?(?:-\d{8})?$/);
    if (m) return "Claude " + cap(m[1]) + " " + m[2] + (m[3] ? "." + m[3] : "");
    m = s.match(/^claude-(\d+)(?:-(\d+))?-(opus|sonnet|haiku)(?:-\d{8})?$/);
    if (m) return "Claude " + m[1] + (m[2] ? "." + m[2] : "") + " " + cap(m[3]);
    if (/^gemini-pro-orchestrator-neon$/.test(s)) return "Orchestrator (Neon)";
    if (/^gemini-pro-orchestrator$/.test(s)) return "Orchestrator (Carbon)";
    if (/^gemini-pro-orchestrator/.test(s)) return "Orchestrator (Argon)";
    m = s.match(/^gemini-(\d+)-(hydrogen|argon|neon|carbon)-(low|medium|high|xhigh)$/);
    if (m) return "Gemini " + m[1] + " " + cap(m[2]) + " (" + (m[3] === "xhigh" ? "Extra" : cap(m[3])) + ")";
    m = s.match(/^gemini-(\d+(?:\.\d+)?)-(flash|pro|ultra|nano|lite)(?:-(low|medium|high))?$/);
    if (m) return "Gemini " + m[1] + " " + cap(m[2]) + (m[3] ? " (" + cap(m[3]) + ")" : "");
    return s;
  }

  // 노력 단계 이름: low -> Low · xhigh -> XHigh · max -> Max. 모르는 값은 첫 글자만 대문자로.
  function formatEffortName(raw) {
    var s = String(raw == null ? "" : raw).trim();
    if (!s) return "";
    var low = s.toLowerCase();
    if (low === "xhigh") return "XHigh";
    return low.charAt(0).toUpperCase() + low.slice(1);
  }

  // 모델 ID(+노력)를 화면 이름으로. agy(Gemini) 모델 ID 는 이름에 노력이 들어 있다("Gemini 4 Hydrogen (Medium)").
  // Claude 는 모델 ID 에 노력이 없으니 메시지 머리말의 `노력:` 을 "Claude Sonnet 5.5 (High)" 처럼 덧붙인다. 모델을 모르면 빈 문자열.
  function handoffNameOf(model, effort, party) {
    var base = formatModelName(model);
    if (!base) return "";
    if (party === "claude" && effort) return base + " (" + formatEffortName(effort) + ")";
    return base;
  }

  // 메시지 목록(번호 오름차순)에서 두 쪽이 가장 최근에 쓴 모델(메시지 머리말의 `모델:` 기준). 없으면 빈 문자열.
  function handoffLatestModels(messages) {
    var out = { claude: "", agy: "" };
    var list = Array.isArray(messages) ? messages : [];
    for (var i = list.length - 1; i >= 0; i--) {
      var m = list[i];
      if (!m || !m.model) continue;
      var p = dirParty(m.dir);
      if (p && !out[p]) out[p] = m.model;
      if (out.claude && out.agy) break;
    }
    return out;
  }

  // 두 쪽이 가장 최근에 쓴 "화면 이름"(모델 + Claude 는 노력). 같은 메시지의 모델과 노력을 짝으로 본다. 없으면 빈 문자열.
  function handoffLatestNames(messages) {
    var out = { claude: "", agy: "" };
    var list = Array.isArray(messages) ? messages : [];
    for (var i = list.length - 1; i >= 0; i--) {
      var m = list[i];
      if (!m || !m.model) continue;
      var p = dirParty(m.dir);
      if (p && !out[p]) out[p] = handoffNameOf(m.model, m.effort, p);
      if (out.claude && out.agy) break;
    }
    return out;
  }

  // agy 가 쓴 회신(a2c)에 머리말 모델이 없으면, 그 회신이 답한 메시지(답장대상)를 처리한 위임의 모델로 채운다.
  // resolver(num) 은 { model, inferred } 또는 null. 이미 모델이 있으면 그대로. 새 배열을 돌려준다.
  function handoffEnrichMessages(messages, resolver) {
    var list = Array.isArray(messages) ? messages : [];
    if (typeof resolver !== "function") return list;
    return list.map(function (m) {
      if (!m || m.model || dirParty(m.dir) !== "agy" || !m.replyTo) return m;
      var r = resolver(m.replyTo);
      if (!r || !r.model) return m;
      var c = {};
      for (var k in m) { if (Object.prototype.hasOwnProperty.call(m, k)) c[k] = m[k]; }
      c.model = r.model;
      return c;
    });
  }

  // 채널의 위임 기록으로 "이 c2a 번호를 처리한 agy 모델"을 찾는 함수를 만든다.
  //   채널 응답의 auto.dispatches(번호 -> 위임 작업 ID) -> 진행 중이면 대기 작업(pendingItems)의 모델, 끝났으면 위임 기록(allItems)의 모델.
  //   둘 다 모르면 위임 때 고른 단계(tier)의 기본 주 모델(config\models.json 의 기본값)을 짐작한다(inferred).
  //   옛 기록의 low · medium · high 는 그때 쓰던 gemini-3.8-flash-<단계> 로 짐작한다.
  function handoffDispatchResolver(channelData, records, pendings) {
    // 단계 -> 기본 주 모델(화면에서 짐작할 때만 쓴다. 실제 선택은 워처가 config\models.json 으로 한다).
    var tierModels = {
      "quick": "gemini-4-hydrogen-low", "build": "gemini-4-hydrogen-medium", "build-hard": "gemini-4-neon-medium",
      "feature": "gemini-pro-orchestrator-neon", "feature-carbon": "gemini-pro-orchestrator", "feature-argon": "gemini-pro-orchestrator",
      "think": "gemini-4-neon-high", "think-carbon": "gemini-4-carbon-high", "think-argon": "gemini-4-carbon-high", "deep": "gemini-4-neon-xhigh"
    };
    var ds = channelData && channelData.auto && Array.isArray(channelData.auto.dispatches) ? channelData.auto.dispatches : [];
    var recs = Array.isArray(records) ? records : [];
    var pend = Array.isArray(pendings) ? pendings : [];
    var usable = function (v) { v = String(v == null ? "" : v).trim(); return v && v.charAt(0) !== "(" ? v : ""; };
    return function (num) {
      if (num == null || num === "") return null;
      for (var i = ds.length - 1; i >= 0; i--) {
        var d = ds[i];
        if (!d || String(d.num) !== String(num)) continue;
        var id = d.taskId, j, v;
        if (id) {
          for (j = 0; j < pend.length; j++) { if (pend[j] && pend[j].task_id === id && (v = usable(pend[j].model))) return { model: v, inferred: false }; }
          for (j = 0; j < recs.length; j++) { if (recs[j] && recs[j].task_id === id && (v = usable(recs[j].model))) return { model: v, inferred: false }; }
        }
        if (d.tier && Object.prototype.hasOwnProperty.call(tierModels, String(d.tier))) return { model: tierModels[String(d.tier)], inferred: true };
        if (d.tier && /^(low|medium|high)$/.test(String(d.tier))) return { model: "gemini-3.8-flash-" + d.tier, inferred: true };
        return null;
      }
      return null;
    };
  }

  // 메시지 하나의 "보낸 쪽 → 받는 쪽" 이름.
  //   보낸 쪽: 그 메시지 머리말의 모델(+Claude 는 노력). 머리말에 모델이 없는 agy 회신은 그 회신이 답한 위임의 모델. 그것도 없으면 그 쪽이 가장 최근에 쓴 모델
  //            (senderInferred=true 로 표시해 "추정"임을 밝힌다). 그것도 없으면 Claude/agy 라고만.
  //   받는 쪽: 그 메시지에 답한 메시지(답장대상이 이 번호)의 모델이 있으면 그것(실제로 받은 쪽). 아직 답이 없는 c2a 는 그 메시지를 처리 중인(처리한) 위임의 모델.
  //            그것도 없으면 그 쪽이 가장 최근에 쓴 모델(inferred=true). 그것도 없으면 Claude/agy 라고만.
  //   resolver: handoffDispatchResolver 의 함수(선택). 없으면 메시지 머리말만으로 정한다.
  function handoffLabelParts(m, messages, resolver) {
    var senderParty = m ? dirParty(m.dir) : null;
    if (!senderParty) return null;
    var receiverParty = senderParty === "claude" ? "agy" : "claude";
    var generic = { claude: "Claude", agy: "agy" };
    var list = handoffEnrichMessages(Array.isArray(messages) ? messages : [], resolver);
    var full = m;
    if (m.model === undefined) {
      for (var k = 0; k < list.length; k++) { if (list[k] && String(list[k].num) === String(m.num)) { full = list[k]; break; } }
    } else if (!m.model && senderParty === "agy") {
      full = handoffEnrichMessages([m], resolver)[0];
    }
    var sender = handoffNameOf(full.model, full.effort, senderParty);
    var senderInferred = false;
    if (!sender) {
      var latestSender = handoffLatestNames(list)[senderParty];
      if (latestSender) { sender = latestSender; senderInferred = true; }
    }
    if (!sender) sender = generic[senderParty];
    var receiver = "";
    var inferred = false;
    for (var i = 0; i < list.length; i++) {
      var r = list[i];
      if (r && r.model && r.replyTo && String(r.replyTo) === String(m.num) && dirParty(r.dir) === receiverParty) {
        receiver = handoffNameOf(r.model, r.effort, receiverParty);
        break;
      }
    }
    if (!receiver && receiverParty === "agy" && typeof resolver === "function") {
      var dm = resolver(m.num);
      if (dm && dm.model) { receiver = handoffNameOf(dm.model, "", "agy"); inferred = !!dm.inferred; }
    }
    if (!receiver) {
      var latest = handoffLatestNames(list)[receiverParty];
      if (latest) { receiver = latest; inferred = true; }
    }
    if (!receiver) receiver = generic[receiverParty];
    return { senderParty: senderParty, sender: sender, receiverParty: receiverParty, receiver: receiver, inferred: inferred, senderInferred: senderInferred };
  }

  // 방향 표시: 모델명으로 "Claude Opus 5.5 → Gemini 4 Carbon (High)". 채널 정보가 없으면 예전처럼 Claude/agy.
  function dirLabelHtml(dir, m, channelName) {
    var data = (m && channelName && handoffChannels[channelName]) ? handoffChannels[channelName] : null;
    var parts = m ? handoffLabelParts(m, data ? data.messages : null, data ? handoffDispatchResolver(data, allItems, pendingItems) : null) : null;
    if (parts) {
      var tip = parts.inferred ? ' title="이 메시지에 답한 기록이 아직 없어, 그 쪽이 가장 최근에 쓴 모델로 표시했습니다"' : "";
      var sTip = parts.senderInferred ? ' title="이 메시지 머리말에 모델이 없어, 그 쪽이 가장 최근에 쓴 모델로 표시했습니다"' : "";
      return '<span class="who-' + parts.senderParty + '"' + sTip + '>' + escapeHtml(parts.sender) + '</span> → <span' + tip + '>' + escapeHtml(parts.receiver) + '</span>';
    }
    if (dir === "c2a") return '<span class="who-claude">Claude</span> → agy';
    if (dir === "a2c") return '<span class="who-agy">agy</span> → Claude';
    return escapeHtml(dir || "");
  }

  function qaStatusBadge(r) {
    if (!r.status) return '<span class="badge status-unknown">상태 미기록</span>';
    return isOkStatus(r)
      ? '<span class="badge status-ok">OK</span>'
      : '<span class="badge status-err">' + escapeHtml(String(r.status)) + '</span>';
  }

  // 대시보드 한 줄 항목: [색 막대][시각][제목/부제][상태]
  function buildRow(o) {
    var li = document.createElement("li");
    var row = document.createElement("div");
    row.className = "row" + (o.party ? " from-" + o.party : "") + (o.isErr ? " is-err" : "");
    row.innerHTML = [
      '<span class="row-bar" aria-hidden="true"></span>',
      '<span class="row-when">' + escapeHtml(formatClock(o.time)) + '</span>',
      '<div class="row-main">',
      '  <div class="row-title">' + o.titleHtml + '</div>',
      '  <div class="row-sub">' + o.subHtml + '</div>',
      '</div>',
      '<div class="row-side">' + (o.sideHtml || "") + '</div>'
    ].join("");
    if (o.time) { row.title = o.time; }
    makeActivatable(row);
    row.onclick = o.onClick;
    li.appendChild(row);
    return li;
  }

  function goQaSession(arg) {
    return function () {
      if (arg && typeof arg === "object") {
        var node = qaNodeOf(arg, claudeTree);
        selectQaSession(node.sessionId, node.projectId);
      } else if (typeof arg === "string" && arg) {
        var rep = findRepresentativeItemBySessionName(arg);
        if (rep) {
          var node2 = qaNodeOf(rep, claudeTree);
          selectQaSession(node2.sessionId, node2.projectId);
        } else {
          selectQaSession(arg);
        }
      } else {
        selectQaProject("");
      }
      switchNav("qa");
    };
  }

  function goHandoffProject(name, m) {
    return function () {
      if (m && handoffChannels[name]) {
        var node = handoffNodeOf(name, m, handoffChannels[name], claudeTree);
        selectHandoffSession(node.sessionId, node.projectId);
      } else if (name && handoffChannels[name]) {
        selectHandoffSession("c:" + name, QA_UNLINKED);
      } else {
        selectHandoffProject("");
      }
      switchNav("handoff");
    };
  }

  function handoffRow(projectName, m, subPrefix) {
    var waitText = "";
    if (m.status === "보냄" || m.status === "읽음") {
      var waitData = handoffChannels[projectName];
      var waitParts = handoffLabelParts(m, waitData ? waitData.messages : null, waitData ? handoffDispatchResolver(waitData, allItems, pendingItems) : null);
      if (waitParts) waitText = '<span class="who-' + waitParts.receiverParty + '">' + escapeHtml(waitParts.receiver) + ' 처리 대기</span>';
    }
    return buildRow({
      party: dirParty(m.dir),
      time: m.time,
      titleHtml: '<span class="num">#' + escapeHtml(m.num) + '</span>' + escapeHtml(m.title || "(제목 없음)"),
      subHtml: (subPrefix ? '<span>' + subPrefix + '</span>' : "") +
        '<span>' + escapeHtml(projectName) + '</span>' +
        (waitText || '<span>' + dirLabelHtml(m.dir, m, projectName) + '</span>'),
      sideHtml: stepsHtml(m.status),
      onClick: goHandoffProject(projectName, m)
    });
  }

  function dashSkeletonRowsHtml(count) {
    var html = "";
    for (var i = 0; i < count; i++) {
      html += '<li><div class="row is-skeleton" aria-hidden="true">' +
        '<span class="row-bar" aria-hidden="true"></span>' +
        '<span class="row-when"><span class="skel skel-xs"></span></span>' +
        '<div class="row-main">' +
          '<div class="row-title"><span class="skel skel-wide"></span></div>' +
          '<div class="row-sub"><span class="skel skel-sub"></span></div>' +
        '</div>' +
        '<div class="row-side"><span class="skel skel-pill"></span></div>' +
      '</div></li>';
    }
    return html;
  }

  function renderAttention() {
    if (!els.dashAttention) return;
    if (!hasLoadedStatusOnce) {
      if (els.dashAttentionCount) els.dashAttentionCount.textContent = "";
      els.dashAttention.innerHTML = dashSkeletonRowsHtml(3);
      return;
    }
    var items = [];

    var dayAgo = Date.now() - 86400000;
    allItems.forEach(function (r) {
      if (!r || !r.status || isOkStatus(r)) return;
      var d = parseLocalTime(r.timestamp);
      if (!d || d.getTime() < dayAgo) return;
      items.push({
        time: r.timestamp,
        node: function () {
          return buildRow({
            isErr: true,
            time: r.timestamp,
            titleHtml: escapeHtml(extractQuestionKeyword(r.question) || "(질문 내용 없음)"),
            subHtml: '<span>위임 실패</span>' +
              (recordModel(r) ? '<span title="' + escapeHtml(recordModel(r)) + '">' + escapeHtml(shortAgyModel(recordModel(r))) + '</span>' : "") +
              '<span>' + escapeHtml(r.session || "단발성") + '</span>',
            sideHtml: qaStatusBadge(r),
            onClick: goQaSession(r)
          });
        }
      });
    });

    items.sort(function (a, b) { return String(b.time).localeCompare(String(a.time)); });

    if (els.dashAttentionCount) {
      els.dashAttentionCount.textContent = items.length > 0 ? items.length + "건" : "";
    }

    els.dashAttention.innerHTML = "";
    if (items.length === 0) {
      els.dashAttention.innerHTML = '<li class="row-empty">확인할 항목이 없습니다. 최근 24시간 안에 실패한 위임이 생기면 여기에 나옵니다.</li>';
      return;
    }
    var frag = document.createDocumentFragment();
    items.forEach(function (it) { frag.appendChild(it.node()); });
    els.dashAttention.appendChild(frag);
  }

  function renderTimeline() {
    if (!els.dashTimeline) return;
    if (!hasLoadedStatusOnce) {
      els.dashTimeline.innerHTML = dashSkeletonRowsHtml(5);
      return;
    }
    var entries = [];

    activePending().forEach(function (p) {
      entries.push({
        time: p.created || "",
        node: function () {
          var processing = (p.state === "processing");
          return buildRow({
            party: "agy",
            time: p.created,
            titleHtml: escapeHtml(extractQuestionKeyword(p.question) || "(질문 내용 없음)"),
            subHtml: '<span>위임</span>' + (p.model ? '<span>' + escapeHtml(p.model) + '</span>' : "") +
              '<span>' + escapeHtml(p.session || "단발성") + '</span>',
            sideHtml: processing ? '<span class="badge status-pending-processing">진행 중</span>'
                                 : '<span class="badge status-pending-queued">대기 중</span>',
            onClick: goQaSession(p)
          });
        }
      });
    });

    allItems.slice(0, 10).forEach(function (r) {
      entries.push({
        time: r.timestamp || "",
        node: function () {
          return buildRow({
            party: "agy",
            isErr: Boolean(r.status) && !isOkStatus(r),
            time: r.timestamp,
            titleHtml: escapeHtml(extractQuestionKeyword(r.question) || "(질문 내용 없음)"),
            subHtml: '<span>위임</span>' +
              (recordModel(r) ? '<span title="' + escapeHtml(recordModel(r)) + '">' + escapeHtml(shortAgyModel(recordModel(r))) + '</span>' : "") +
              '<span>' + escapeHtml(r.session || "단발성") + '</span>',
            sideHtml: qaStatusBadge(r),
            onClick: goQaSession(r)
          });
        }
      });
    });

    entries.sort(function (a, b) { return String(b.time).localeCompare(String(a.time)); });
    entries = entries.slice(0, 10);

    els.dashTimeline.innerHTML = "";
    if (entries.length === 0) {
      els.dashTimeline.innerHTML = '<li class="row-empty">아직 기록이 없습니다. Claude나 Antigravity가 작업을 위임하면 여기에 쌓입니다.</li>';
      return;
    }
    var frag = document.createDocumentFragment();
    entries.forEach(function (e) { frag.appendChild(e.node()); });
    els.dashTimeline.appendChild(frag);
  }

  function renderStats() {
    if (!hasLoadedStatusOnce) {
      if (els.dashStats) {
        var labels = ["누적 위임", "오늘", "성공률", "평균 소요"];
        els.dashStats.innerHTML = labels.map(function (lb) {
          return '<div aria-hidden="true"><dt>' + lb + '</dt><dd><span class="skel skel-md"></span></dd></div>';
        }).join("");
      }
      if (els.modelBarsContainer) {
        var mHtml = "";
        for (var mi = 0; mi < 3; mi++) {
          mHtml += '<div class="model-bar-row is-skeleton" aria-hidden="true">' +
            '<span class="skel skel-sub"></span>' +
            '<div class="model-bar-track"><span class="skel skel-bar" style="margin:0"></span></div>' +
            '<span class="skel skel-sm"></span>' +
          '</div>';
        }
        els.modelBarsContainer.innerHTML = mHtml;
      }
      return;
    }
    var totalQa = allItems.length;
    var okCount = 0;
    var errCount = 0;
    var todayCount = 0;
    var totalElapsed = 0;
    var elapsedItemCount = 0;
    var todayKey = localDateKey(new Date());
    var modelUsage = {};

    allItems.forEach(function (r) {
      if (isOkStatus(r)) { okCount++; } else if (r.status) { errCount++; }
      if (r.timestamp && String(r.timestamp).slice(0, 10) === todayKey) { todayCount++; }
      if (r.elapsed_sec && !isNaN(Number(r.elapsed_sec))) {
        totalElapsed += Number(r.elapsed_sec);
        elapsedItemCount++;
      }
      var m = recordModel(r) || "기타";
      modelUsage[m] = (modelUsage[m] || 0) + 1;
    });

    var decided = okCount + errCount;
    var successRate = decided > 0 ? Math.round((okCount / decided) * 100) + "%" : "-";
    var avgSec = elapsedItemCount > 0 ? formatDuration(totalElapsed / elapsedItemCount) : "-";

    if (els.dashStats) {
      var stats = [
        ["누적 위임", totalQa.toLocaleString() + "건"],
        ["오늘", todayCount + "건"],
        ["성공률", successRate],
        ["평균 소요", avgSec]
      ];
      els.dashStats.innerHTML = stats.map(function (s) {
        return '<div' + (s[2] ? ' title="' + escapeHtml(s[2]) + '"' : '') + '><dt>' + s[0] + '</dt><dd>' + escapeHtml(s[1]) + '</dd></div>';
      }).join("");
    }

    renderDashboardModelStats(modelUsage, totalQa);
  }

  function renderQuickSessions() {
    if (!els.quickSessionsList) return;
    var sessions = groupQaSessions();
    if (sessions.length === 0) {
      if (!hasLoadedStatusOnce) {
        var sHtml = "";
        for (var si = 0; si < 5; si++) {
          sHtml += '<div class="quick-link-item is-skeleton" aria-hidden="true">' +
            '<span class="skel skel-xs" style="width:14px;height:14px"></span>' +
            '<span class="skel skel-wide"></span>' +
            '<span class="skel skel-xs" style="width:22px"></span>' +
          '</div>';
        }
        els.quickSessionsList.innerHTML = sHtml;
        return;
      }
      els.quickSessionsList.innerHTML = '<span class="empty-hint">세션 기록이 없습니다.</span>';
      return;
    }
    var frag = document.createDocumentFragment();
    sessions.slice(0, 6).forEach(function (s) {
      var item = document.createElement("div");
      item.className = "quick-link-item";
      var isNone = (s.name === "__none__");
      var displayName = isNone ? "단발성 작업" : s.name;
      item.innerHTML = [
        '<span class="session-icon">' + icon(isNone ? "single" : "thread") + '</span>',
        '<span class="quick-link-name" title="' + escapeHtml(displayName) + '">' + escapeHtml(displayName) + '</span>',
        (s.pending > 0 ? '<span class="pending-pulse-dot" title="진행/대기 중 ' + s.pending + '건"></span>' : ''),
        '<span class="quick-link-count">' + (s.total + s.pending) + '</span>'
      ].join("");
      makeActivatable(item);
      item.onclick = goQaSession(s.name);
      frag.appendChild(item);
    });
    els.quickSessionsList.innerHTML = "";
    els.quickSessionsList.appendChild(frag);
  }

  function renderDashboardModelStats(modelUsage, totalCount) {
    if (!els.modelBarsContainer) return;
    var models = Object.keys(modelUsage).sort(function (a, b) {
      return modelUsage[b] - modelUsage[a];
    });

    if (models.length === 0) {
      els.modelBarsContainer.innerHTML = "";
      return;
    }

    var frag = document.createDocumentFragment();
    models.forEach(function (m) {
      var count = modelUsage[m];
      var pct = totalCount > 0 ? Math.round((count / totalCount) * 100) : 0;

      var row = document.createElement("div");
      row.className = "model-bar-row";
      row.innerHTML = [
        '<span class="model-bar-name" title="' + escapeHtml(m) + '">' + escapeHtml(m) + '</span>',
        '<div class="model-bar-track" aria-hidden="true">',
        '  <div class="model-bar-fill" style="width: ' + pct + '%;"></div>',
        '</div>',
        '<span class="model-bar-val">' + count + '건 ' + pct + '%</span>'
      ].join("");
      frag.appendChild(row);
    });

    els.modelBarsContainer.innerHTML = "";
    els.modelBarsContainer.appendChild(frag);
  }

  // ==========================================================================
  // 실측 통계 (#/stats): 질문마다 직접/위임 · 모델 · 소요 시간 · 토큰 · 사유. 측정된 값만 보인다(예상치 없음).
  // 데이터는 /api/usage-stats?days=7|30|90. 서버가 대화 기록을 읽는 동안(collecting)은 3초마다 다시 묻는다.
  // ==========================================================================

  function usageModeLabel(mode) {
    return mode === "delegate" ? "위임" : (mode === "chat" ? "대화" : "직접");
  }

  function usageNum(n) {
    return (n === null || n === undefined) ? "-" : tokenShort(n);
  }

  function usageDur(sec) {
    return (sec === null || sec === undefined) ? "-" : formatDuration(sec);
  }

  // UTC 기록 시각(ISO) -> 이 PC 시각 "11-13 09:05"
  function usageWhen(iso) {
    var d = new Date(iso);
    if (!iso || isNaN(d.getTime())) return "";
    return pad2(d.getMonth() + 1) + "-" + pad2(d.getDate()) + " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes());
  }

  // 폴더 경로의 마지막 이름(프로젝트 표시용)
  function usageProjectName(path) {
    var parts = String(path || "").split(/[\\/]/).filter(function (p) { return p; });
    return parts.length ? parts[parts.length - 1] : "";
  }

  // 요약 한 줄: [이름, 값, 툴팁]
  function usageSummaryStats(summary) {
    var s = summary || {};
    var m = s.by_mode || {};
    var count = function (k) { return (m[k] && m[k].count) || 0; };
    var t = s.tasks || {};
    var r = s.reason || {};
    var rate = r.total > 0 ? Math.round((r.with / r.total) * 100) + "% (" + r.with + "/" + r.total + ")" : "-";
    var out = [
      ["질문", (s.total || 0).toLocaleString() + "건"],
      ["직접", count("direct").toLocaleString() + "건", "도구를 쓰고 Claude 가 직접 처리한 질문"],
      ["위임", count("delegate").toLocaleString() + "건", "agy 에 작업을 보낸 질문"],
      ["대화", count("chat").toLocaleString() + "건", "도구 호출 없이 답한 질문"],
      ["위임 작업", "성공 " + (t.ok || 0) + " · 실패 " + (t.fail || 0) + " · 취소 " + (t.cancel || 0), "위임 질문들이 보낸 agy 작업의 결과"],
      ["사유 기록", rate, "사유가 남은 직접 · 위임 질문의 비율."]
    ];
    if (s.auto > 0) out.push(["자동 진행", s.auto + "건", "/loop · 예약 실행으로 이어진 질문(구간을 나눌 수 없어 한 건으로 셉니다)"]);
    if (s.by_client && s.by_client.agy) {
      var agyDirNode = (s.by_client.agy.by_mode && s.by_client.agy.by_mode.direct != null) ? s.by_client.agy.by_mode.direct : s.by_client.agy.direct;
      if (agyDirNode != null) {
        var agyDirectCnt = typeof agyDirNode === "object" ? Number(agyDirNode.count || 0) : Number(agyDirNode || 0);
        if (agyDirectCnt > 0) {
          out.push(["agy 직접", agyDirectCnt.toLocaleString() + "건", "Antigravity 가 위임 없이 직접 처리한 질문"]);
        }
      }
    }
    return out;
  }

  function usageModeTableHtml(summary) {
    var m = (summary && summary.by_mode) || {};
    var bc = (summary && summary.by_client) || null;
    var head = '<thead><tr><th scope="col">방식</th><th scope="col" class="num">건수</th><th scope="col" class="num">소요 시간(중앙값)</th>' +
      '<th scope="col" class="num">총 토큰(중앙값)</th><th scope="col" class="num">캐시 읽기(중앙값)</th><th scope="col" class="num">agy 토큰(중앙값)</th>' +
      '<th scope="col" class="num">총 토큰 합</th><th scope="col" class="num">소요 시간 합</th></tr></thead>';
    var rowHtml = function (labelHtml, x, isDelegate, trClass) {
      return '<tr' + (trClass ? ' class="' + trClass + '"' : '') + '><th scope="row">' + labelHtml + '</th>' +
        '<td class="num">' + (x.count || 0).toLocaleString() + '</td>' +
        '<td class="num">' + usageDur(x.dur_median) + '</td>' +
        '<td class="num">' + usageNum(x.tokens_median) + '</td>' +
        '<td class="num">' + usageNum(x.cr_median) + '</td>' +
        '<td class="num">' + (isDelegate ? usageNum(x.agy_tokens_median) : "") + '</td>' +
        '<td class="num">' + (x.count ? usageNum(x.tokens_sum) : "-") + '</td>' +
        '<td class="num">' + (x.count ? usageDur(x.dur_sum) : "-") + '</td></tr>';
    };
    var body = ["direct", "delegate", "chat"].map(function (k) {
      var x = m[k] || {};
      var html = rowHtml('<span class="badge usage-' + k + '">' + usageModeLabel(k) + '</span>', x, k === "delegate", "");
      if (k === "direct" && bc && (bc.claude || bc.agy)) {
        var cRaw = bc.claude ? ((bc.claude.by_mode && bc.claude.by_mode.direct != null) ? bc.claude.by_mode.direct : bc.claude.direct) : null;
        var aRaw = bc.agy ? ((bc.agy.by_mode && bc.agy.by_mode.direct != null) ? bc.agy.by_mode.direct : bc.agy.direct) : null;
        var cDir = cRaw != null ? (typeof cRaw === "object" ? cRaw : (Number(cRaw) > 0 ? { count: Number(cRaw) } : null)) : null;
        var aDir = aRaw != null ? (typeof aRaw === "object" ? aRaw : (Number(aRaw) > 0 ? { count: Number(aRaw) } : null)) : null;
        if (cDir && (cDir.count || 0) > 0) {
          html += rowHtml('<span class="usage-sub-indent">↳</span> <span class="badge usage-claude">Claude 직접</span>', cDir, false, "usage-sub-row");
        }
        if (aDir && (aDir.count || 0) > 0) {
          html += rowHtml('<span class="usage-sub-indent">↳</span> <span class="badge usage-agy-direct">agy 직접</span>', aDir, true, "usage-sub-row");
        }
      }
      return html;
    }).join("");
    return head + "<tbody>" + body + "</tbody>";
  }

  // 모델 체인에서 모델 이름 중간이 쪼개지지 않게 각 이름 조각을 nowrap span 으로 감싼다(줄바꿈은 " › " · " → " · " · " · 공백에서만).
  function usageWrapModelNames(text) {
    return String(text || "").split(/(\s+)/).map(function (part) {
      if (!part || /^\s+$/.test(part) || part === "›" || part === "→" || part === "·") return escapeHtml(part);
      return '<span class="usage-model-name">' + escapeHtml(part) + '</span>';
    }).join("");
  }

  function usageModelTableHtml(list) {
    var rows = list || [];
    if (!rows.length) return "";
    var head = '<div class="usage-grid-row usage-grid-head" role="row">' +
      '<div class="usage-cell usage-cell-model" role="columnheader">모델</div>' +
      '<div class="usage-cell num" role="columnheader">건수</div>' +
      '<div class="usage-cell num" role="columnheader">소요 시간(중앙값)</div>' +
      '<div class="usage-cell num" role="columnheader">Claude 총 토큰(중앙값)</div>' +
      '<div class="usage-cell num" role="columnheader">agy 토큰(중앙값)</div></div>';
    var body = rows.map(function (x) {
      var comboStr = String(x.combo || "");
      var modelHtml = usageWrapModelNames(comboStr);
      if (x.mode === "delegate" && Array.isArray(x.real_models) && x.real_models.length > 0) {
        var validReal = x.real_models.filter(function (m) { return m && (m.short || m.model); }).slice();
        validReal.sort(function (a, b) {
          var diff = (Number(b.total) || 0) - (Number(a.total) || 0);
          return diff !== 0 ? diff : String(a.short || a.model).localeCompare(String(b.short || b.model));
        });
        var arrowIdx = comboStr.lastIndexOf(" → ");
        var cfgAgy = arrowIdx >= 0 ? comboStr.slice(arrowIdx + 3).trim() : "";
        var realShorts = validReal.map(function (m) { return String(m.short || usageAgyShort(m.model)); });
        var showReal = realShorts.length >= 2 || (realShorts.length === 1 && realShorts[0] !== cfgAgy);
        if (showReal) {
          modelHtml += ' <span class="usage-model-real">(' + realShorts.map(usageWrapModelNames).join(" · ") + ')</span>';
        }
      }
      return '<div class="usage-grid-row" role="row">' +
        '<div class="usage-cell usage-cell-model usage-model" role="cell">' + modelHtml + '</div>' +
        '<div class="usage-cell num" role="cell" data-label="건수">' + (x.count || 0).toLocaleString() + '</div>' +
        '<div class="usage-cell num" role="cell" data-label="소요(중앙값)">' + usageDur(x.dur_median) + '</div>' +
        '<div class="usage-cell num" role="cell" data-label="Claude(중앙값)">' + usageNum(x.tokens_median) + '</div>' +
        '<div class="usage-cell num" role="cell" data-label="agy(중앙값)">' + (x.mode === "delegate" ? usageNum(x.agy_tokens_median) : "") + '</div></div>';
    }).join("");
    return head + body;
  }

  // 일별 쌓은 막대(직접 · 위임 · 대화). claude/agy 분리가 있으면 날마다 왼쪽 Claude · 오른쪽 Agy 두 막대로 나란히 그린다.
  function usageDailyHtml(daily) {
    var days = daily || [];
    var hasSplit = days.some(function (d) { return Boolean(d && (d.claude || d.agy)); });
    var maxDay = 0;
    var maxBar = 0;
    days.forEach(function (d) {
      var tot = (d.direct || 0) + (d.delegate || 0) + (d.chat || 0);
      maxDay = Math.max(maxDay, tot);
      if (hasSplit) {
        var c = d.claude || {};
        var a = d.agy || {};
        var cTot = (c.direct || 0) + (c.delegate || 0) + (c.chat || 0);
        var aTot = (a.direct || 0) + (a.delegate || 0) + (a.chat || 0);
        maxBar = Math.max(maxBar, cTot, aTot);
      } else {
        maxBar = Math.max(maxBar, tot);
      }
    });
    if (!days.length || maxDay === 0) return "";
    var step = days.length <= 10 ? 1 : (days.length <= 31 ? 5 : 15);
    var showSub = (hasSplit && days.length <= 14);
    function stackHtml(cls, obj, labelPrefix, dateLabel) {
      var dr = (obj && obj.direct) || 0;
      var dl = (obj && obj.delegate) || 0;
      var ch = (obj && obj.chat) || 0;
      var tot = dr + dl + ch;
      var segs = [["chat", ch], ["delegate", dl], ["direct", dr]].map(function (p) {
        return p[1] > 0 ? '<span class="usage-seg usage-seg-' + p[0] + '" style="flex:' + p[1] + '"></span>' : "";
      }).join("");
      var hPct = (tot > 0 && maxBar > 0) ? Math.max(3, Math.round((tot / maxBar) * 100)) : 0;
      var tip = dateLabel + (labelPrefix ? " · " + labelPrefix + " " + tot + "건 (" : " · ") +
        "직접 " + dr + " · 위임 " + dl + " · 대화 " + ch + (labelPrefix ? ")" : "");
      return '<div class="usage-bar-stack ' + cls + '" style="height:' + hPct + '%" title="' + escapeHtml(tip) + '">' + segs + '</div>';
    }
    var cols = days.map(function (d, i) {
      var label = String(d.date || "").slice(5);
      var showLabel = ((days.length - 1 - i) % step === 0);
      if (hasSplit) {
        var c = d.claude || { direct: 0, delegate: 0, chat: 0 };
        var a = d.agy || { direct: 0, delegate: 0, chat: 0 };
        var cTot = (c.direct || 0) + (c.delegate || 0) + (c.chat || 0);
        var aTot = (a.direct || 0) + (a.delegate || 0) + (a.chat || 0);
        var colTip = label + " · Claude " + cTot + "건 · Agy " + aTot + "건 (합계 " + (cTot + aTot) + "건)";
        var pair = '<div class="usage-bar-pair">' +
          '<div class="usage-bar-slot">' + stackHtml("usage-bar-claude", c, "Claude", label) + (showSub ? '<span class="usage-bar-sub usage-bar-sub-claude">C</span>' : '') + '</div>' +
          '<div class="usage-bar-slot">' + stackHtml("usage-bar-agy", a, "Agy", label) + (showSub ? '<span class="usage-bar-sub usage-bar-sub-agy">A</span>' : '') + '</div>' +
        '</div>';
        return '<div class="usage-bar-col usage-bar-col-dual" title="' + escapeHtml(colTip) + '">' + pair +
          '<span class="usage-bar-label">' + (showLabel ? escapeHtml(label) : "") + '</span></div>';
      }
      var total = (d.direct || 0) + (d.delegate || 0) + (d.chat || 0);
      var tip = label + " · 직접 " + (d.direct || 0) + " · 위임 " + (d.delegate || 0) + " · 대화 " + (d.chat || 0);
      var segs = [["chat", d.chat], ["delegate", d.delegate], ["direct", d.direct]].map(function (p) {
        return p[1] > 0 ? '<span class="usage-seg usage-seg-' + p[0] + '" style="flex:' + p[1] + '"></span>' : "";
      }).join("");
      return '<div class="usage-bar-col" title="' + escapeHtml(tip) + '">' +
        '<div class="usage-bar-stack" style="height:' + (total > 0 ? Math.max(3, Math.round((total / maxBar) * 100)) : 0) + '%">' + segs + '</div>' +
        '<span class="usage-bar-label">' + (showLabel ? escapeHtml(label) : "") + '</span></div>';
    }).join("");
    var maxLine = hasSplit
      ? '가장 많은 날 ' + maxDay + '건 <span class="usage-bars-hint">· 왼쪽 C(Claude) / 오른쪽 A(Agy)</span>'
      : '가장 많은 날 ' + maxDay + '건';
    return '<p class="usage-bars-max">' + maxLine + '</p><div class="usage-bars' + (hasSplit ? ' usage-bars-dual' : '') + '" role="img" aria-label="일별 질문 수(Claude · Agy)">' + cols + '</div>';
  }

  // 토큰 칸: 직접 · 대화는 Claude 총 토큰, 위임은 agy 총 토큰(Claude 가 제출 · 검토에 쓴 몫은 툴팁)
  // agy 모델 이름을 짧게(shortAgyModel 과 같다): "gemini-4-hydrogen-medium" -> "hydrogen-medium" (전체 이름은 툴팁 · 펼친 줄에)
  function usageAgyShort(name) {
    return shortAgyModel(String(name || "").trim());
  }
  // 모델 칸: 직접은 Claude 모델, 위임은 "Claude → agy 모델들 (실제 모델들)" + 둘째 줄에 실제 모델별 토큰(입력+출력)
  function usageComboHtml(r) {
    var text = usageComboText(r);
    if (r.mode !== "delegate") return usageWrapModelNames(text);
    var cut = text.indexOf(" → ");
    if (cut < 0) return usageWrapModelNames(text);
    var first = text.slice(0, cut);
    var firstHtml = usageWrapModelNames(first);
    if (r.agent_label) {
      var subCut = first.indexOf(" › 서브 ");
      if (subCut >= 0) {
        var subTitle = "위임을 보낸 서브에이전트: " + (r.agent_model || r.agent_label) + (r.agent_effort ? " (effort " + r.agent_effort + ")" : "");
        firstHtml = usageWrapModelNames(first.slice(0, subCut)) +
          ' <span class="usage-model-sub" title="' + escapeHtml(subTitle) + '">' + usageWrapModelNames(first.slice(subCut + 1)) + '</span>';
      }
    } else if (r.src_client) {
      var srcClientDisp = String(r.src_client).toLowerCase() === "antigravity" ? "Antigravity" : String(r.src_client);
      var srcTip = r.src_model ? ("이 위임을 보낸 " + srcClientDisp + " 모델: " + r.src_model) : ("이 위임을 보낸 클라이언트: " + srcClientDisp);
      firstHtml = '<span title="' + escapeHtml(srcTip) + '">' + firstHtml + '</span>';
    }
    var failed = (Array.isArray(r.agy_failed) ? r.agy_failed : (r.agy_failed ? [r.agy_failed] : [])).map(function (m) { return usageAgyShort(m); }).filter(Boolean);
    var agy = String(r.agy_models || "").split(",").map(function (m) { return usageAgyShort(m); }).filter(Boolean);
    var agyPart = agy.length ? (agy.length > 2 ? agy[0] + " 외 " + (agy.length - 1) : agy.join(", ")) : "?";
    var agyHtml = "";
    if (failed.length) {
      var failedHtml = failed.map(function (m) {
        var title = "한도 · 과부하로 실패해 다음 모델로 넘어갔습니다: " + m;
        return '<span class="agy-failed usage-model-name" title="' + escapeHtml(title) + '">' + escapeHtml(m) + ' ✕</span>';
      }).join(" → ");
      agyHtml = '→ ' + failedHtml + ' → ' + usageWrapModelNames(agyPart);
    } else {
      agyHtml = '→ ' + usageWrapModelNames(agyPart);
    }
    var realList = Array.isArray(r.real_models) ? r.real_models.filter(function (m) { return m && (m.short || m.model); }).slice() : [];
    realList.sort(function (a, b) {
      var diff = (Number(b.total) || 0) - (Number(a.total) || 0);
      return diff !== 0 ? diff : String(a.short || a.model).localeCompare(String(b.short || b.model));
    });
    var realShorts = realList.map(function (m) { return String(m.short || usageAgyShort(m.model)); });
    var showReal = realShorts.length >= 2 || (realShorts.length === 1 && realShorts[0] !== agyPart);
    if (showReal) {
      agyHtml += ' <span class="usage-model-real">(' + realShorts.map(usageWrapModelNames).join(" · ") + ')</span>';
    }
    var chainHtml = '<div class="usage-model-chain">' +
      '<span class="usage-model-line">' + firstHtml + '</span>' +
      '<span class="usage-model-line usage-model-agy">' + agyHtml + '</span>' +
      '</div>';
    return chainHtml;
  }
  // ---- 질문 기록: 요약 줄 + 늘 보이는 모델 · 토큰 줄 + 펼치면 상세(토큰 장부 · 한도 · 사유와 질문 전문) ----
  var USAGE_DASH = "–";
  function usageDashNum(n) { return Number(n) > 0 ? tokenShort(n) : USAGE_DASH; }
  function usageDashDur(sec) { return (sec === null || sec === undefined || sec === "" || !isFinite(Number(sec))) ? USAGE_DASH : formatDuration(sec); }
  function usageLedgerNum(n) { var v = Number(n); return (isFinite(v) && v > 0) ? Math.round(v).toLocaleString("en-US") : USAGE_DASH; }

  // 질문 하나의 토큰 조각: Claude 본 세션 · 서브(있을 때), agy 실제 모델별. 서버가 tokens_detail 을 안 준 옛 응답은 합계만 쓴다.
  function usageTokenParts(r) {
    var td = (r && r.tokens_detail && typeof r.tokens_detail === "object") ? r.tokens_detail : null;
    var cl = td && td.claude && typeof td.claude === "object" ? td.claude : null;
    var ag = td && td.agy && typeof td.agy === "object" ? td.agy : null;
    var pos = function (v) { var n = Number(v); return (isFinite(n) && n > 0) ? n : 0; };
    var has = function (u) { return !!u && typeof u === "object" && (pos(u.total) > 0 || pos(u.calls) > 0); };
    var models = ag && Array.isArray(ag.models) ? ag.models.filter(function (m) { return m && m.model; }) : [];
    return {
      claude: cl,
      main: cl && has(cl.main) ? cl.main : null,
      sub: cl && has(cl.sub) ? cl.sub : null,
      claudeTotal: cl ? pos(cl.total) : pos(r && r.tokens),
      agy: ag, models: models,
      agyTotal: ag ? pos(ag.total) : pos(r && r.agy_tokens)
    };
  }
  function usageTotalTokens(r) { var p = usageTokenParts(r); return p.claudeTotal + p.agyTotal; }

  // 장부 한 줄: 이름 + 입력 · 캐시 쓰기 · 캐시 읽기 · 출력 · 합계(없는 값은 "–")
  function usageLedgerRowHtml(label, v, cls) {
    var think = Number(v.thinking) > 0 ? ' <small class="ur-think">사고 ' + escapeHtml(usageLedgerNum(v.thinking)) + '</small>' : "";
    return '<tr' + (cls ? ' class="' + cls + '"' : '') + '><th scope="row">' + label + '</th>' +
      '<td>' + usageLedgerNum(v.input) + '</td><td>' + (v.cw === null ? USAGE_DASH : usageLedgerNum(v.cw)) + '</td><td>' + usageLedgerNum(v.cr) + '</td>' +
      '<td>' + usageLedgerNum(v.output) + think + '</td><td>' + usageLedgerNum(v.total) + '</td></tr>';
  }
  function usageLedgerHtml(r) {
    var p = usageTokenParts(r);
    var rows = [];
    var cu = function (u) { return { input: u.input, cw: u.cache_write, cr: u.cache_read, output: u.output, total: u.total }; };
    if (p.main) rows.push(usageLedgerRowHtml("Claude 본 세션 <small>(" + (Number(p.main.calls) || 0) + "회)</small>", cu(p.main)));
    if (p.sub) rows.push(usageLedgerRowHtml("Claude 서브 <small>(" + (Number(p.sub.calls) || 0) + "회)</small>", cu(p.sub)));
    if (p.main && p.sub) rows.push(usageLedgerRowHtml("Claude 합계", cu(p.claude), "ur-sum-row"));
    var sum = { input: 0, cw: null, cr: 0, output: 0, total: 0, thinking: 0 };
    p.models.forEach(function (m) {
      rows.push(usageLedgerRowHtml('<span class="usage-model-name">agy ' + escapeHtml(usageAgyShort(m.model)) + '</span>',
        { input: m.input, cw: null, cr: m.cache, output: m.output, total: m.total, thinking: m.thinking }));
      sum.input += Number(m.input) || 0; sum.cr += Number(m.cache) || 0; sum.output += Number(m.output) || 0; sum.total += Number(m.total) || 0; sum.thinking += Number(m.thinking) || 0;
    });
    if (!p.models.length && p.agy && p.agyTotal > 0) {
      rows.push(usageLedgerRowHtml("agy", { input: p.agy.input, cw: null, cr: p.agy.cache, output: p.agy.output, total: p.agy.total, thinking: p.agy.thinking }));
    }
    if (p.models.length >= 2) rows.push(usageLedgerRowHtml("agy 합계", sum, "ur-sum-row"));
    if (!rows.length) return '<p class="ur-none">토큰 기록 없음</p>';
    return '<div class="ur-ledger-wrap"><table class="ur-ledger"><thead><tr><th scope="col"><span class="ur-sr">출처</span></th>' +
      '<th scope="col">입력</th><th scope="col">캐시 쓰기</th><th scope="col">캐시 읽기</th><th scope="col">출력</th><th scope="col">합계</th></tr></thead><tbody>' +
      rows.join("") + '</tbody></table></div>';
  }

  // 요약 줄 아래에 늘 보이는 줄: 모델 조합(모델 기록이 없으면 아무것도 없음). 토큰 숫자는 상세(장부)에서만 보인다.
  function usageTokensVisibleHtml(r) {
    if (usageModelLineHtml(r).indexOf("usage-muted") >= 0) return "";
    return '<div class="ur-models">' + usageModelLineHtml(r) + '</div>';
  }

  function usageFormatSharePct(p) {
    if (p === null || p === undefined || p === "" || typeof p === "boolean") return USAGE_DASH;
    var v = Number(p);
    if (!isFinite(v) || v < 0) return USAGE_DASH;
    return v < 0.1 ? "<0.1%" : v.toFixed(1) + "%";
  }
  function usageFormatSessRatio(ratio) {
    var r = Number(ratio);
    if (!(r > 0) || !isFinite(r)) return "";
    return (r >= 10 ? String(Math.round(r)) : r.toFixed(1)).replace(/\.0$/, "");
  }
  // 한도 지분의 근거 글(툴팁): 환산 토큰 · 입력 등가 한도 · 실측 증가
  function usageQuotaTip(eqLabel, rawTokens, entry, mDelta, mFrom, mTo) {
    var pctText = usageFormatSharePct(entry.share_pct);
    var tipParts = [
      "≈" + Math.round(Number(entry.est) || 0).toLocaleString("en-US") + " 토큰(원시 환산) 중 " + Math.round(Number(rawTokens || 0)).toLocaleString("en-US") + " (" + pctText + ")"
    ];
    if (Number(entry.est_cost) > 0) tipParts.push(eqLabel + " 입력 등가 한도 ≈" + Math.round(Number(entry.est_cost)).toLocaleString("en-US"));
    if (mDelta !== undefined && mDelta !== null && isFinite(Number(mDelta))) {
      var md = Math.round(Number(mDelta));
      if (mFrom !== undefined && mFrom !== null && mTo !== undefined && mTo !== null) {
        tipParts.push("실측 +" + md + "%p (" + Math.round(Number(mFrom)) + "%→" + Math.round(Number(mTo)) + "%)");
      } else {
        tipParts.push("실측 +" + md + "%p");
      }
    }
    if (entry.initial) tipParts.push("초기 추정(누적 " + Number(entry.five_points || 0) + "%p 기준)");
    if (entry.backfill) tipParts.push("이후 기준");
    return tipParts.join(" · ");
  }
  // 한 출처의 한 창(5시간 · 주간) 지분. 값이 없으면 null.
  function usageShareData(r, src, winKey) {
    var q = r && r.quota;
    if (!q || typeof q !== "object") return null;
    var sc = String((r && r.src_client) || "").trim().toLowerCase();
    var isAgySrc = (sc === "antigravity" || sc === "agy");
    if (src === "agy" && r.mode !== "delegate" && !isAgySrc) return null;
    var side = q[src];
    var entry = side && side[winKey];
    if (!entry || !(Number(entry.est_cost) > 0 || Number(entry.est) > 0)) return null;
    var raw;
    var mDelta = null, mFrom = null, mTo = null;
    if (src === "claude") {
      raw = (side.raw_tokens !== undefined && side.raw_tokens !== null) ? side.raw_tokens : ((Number(r.tokens) || 0) + (Number(r.cr_tokens) || 0));
    } else {
      raw = (side.raw_tokens !== undefined && side.raw_tokens !== null) ? side.raw_tokens : Number(r.agy_tokens || 0);
      var meas = side.measured && typeof side.measured === "object" ? side.measured : null;
      if (meas) {
        mDelta = winKey === "five_hour" ? meas.five_delta : meas.week_delta;
        mFrom = winKey === "five_hour" ? meas.five_from : meas.week_from;
        mTo = winKey === "five_hour" ? meas.five_to : meas.week_to;
      }
    }
    var pct = Number(entry.share_pct);
    // 퍼센트 옆에 보이는 토큰은 분모(entry.est)와 같은 단위로 맞춘다(Claude 는 raw_tokens, agy 는 tokens_detail.agy.total).
    var tdSide = r && r.tokens_detail && r.tokens_detail[src];
    var shownRaw = (src !== "claude" && tdSide && Number(tdSide.total) > 0) ? Number(tdSide.total) : (Number(raw) || 0);
    return { src: src, pct: pct, text: usageFormatSharePct(pct), raw: shownRaw, limit: Number(entry.est) || 0, tip: usageQuotaTip(src === "claude" ? "Opus" : "Neon", raw, entry, mDelta, mFrom, mTo) };
  }
  // 작은 막대(100% 에서 멈춤) + 퍼센트. withLabel 이면 앞에 출처 이름.
  function usageMeterHtml(d, withLabel) {
    var width = Math.max(0, Math.min(100, isFinite(d.pct) ? d.pct : 0));
    var name = d.src === "claude" ? "Claude" : "agy";
    return '<span class="ur-m ur-m-' + d.src + (d.pct >= 10 ? ' ur-m-hi' : '') + '" title="' + escapeHtml(name + " " + d.text + " · " + d.tip) + '">' +
      (withLabel ? '<span class="ur-m-name">' + name + '</span>' : '') +
      '<span class="ur-m-track" aria-hidden="true"><span class="ur-m-fill" style="width: ' + width.toFixed(1) + '%;"></span></span>' +
      '<span class="ur-m-pct">' + escapeHtml(d.text) + '</span>' +
      // 상세 한도 칸(withLabel)에서는 퍼센트 옆에 "이 질문 토큰 / 한도 추정(원시 토큰)" 을 붙인다. 컨텍스트 줄과 같은 모양.
      (withLabel && d.raw > 0 && d.limit > 0 ? '<span class="ur-m-ctxn usage-muted">' + escapeHtml(Math.round(d.raw).toLocaleString("en-US") + " / " + Math.round(d.limit).toLocaleString("en-US")) + '</span>' : '') +
      '</span>';
  }
  // 요약 줄의 5시간 지분: Claude 막대 위, agy 막대 아래
  function usageSummaryMeterHtml(r) {
    var parts = ["claude", "agy"].map(function (s) { return usageShareData(r, s, "five_hour"); }).filter(Boolean);
    if (!parts.length) return "";
    return '<span class="ur-meter">' + parts.map(function (d) { return usageMeterHtml(d, false); }).join("") + '</span>';
  }
  function usageSessionsText(r) {
    var q = r && r.quota;
    if (!q || typeof q !== "object") return "";
    var parts = [];
    var add = function (label, sess) {
      var t = sess && Number(sess.ratio) > 0 ? usageFormatSessRatio(sess.ratio) : "";
      if (t) parts.push(label + " " + t);
    };
    if (q.claude) add("Claude", q.claude.sessions);
    if (r.mode === "delegate" && q.agy) add("agy", q.agy.sessions);
    return parts.join(" · ");
  }
  function usageEndpointsTip() { return "초기 추정 — 처음·끝 기록 기준(반올림 오차 가능)"; }
  // 세션 환산이 처음·끝 기록(대체 계산)으로 나왔는지
  function usageSessionsEndpoints(r) {
    var q = r && r.quota;
    if (!q || typeof q !== "object") return false;
    var one = function (side) { return !!(side && side.sessions && Number(side.sessions.ratio) > 0 && side.sessions.basis === "endpoints"); };
    return one(q.claude) || (r.mode === "delegate" && one(q.agy));
  }
  // 컨텍스트 칸(출처 하나): 가장 큰 한 호출의 컨텍스트. 창 크기를 알면 막대 + 퍼센트 + 숫자, 모르면 숫자와 안내, 값이 없으면 "–".
  function usageContextCellHtml(r, src) {
    var name = src === "claude" ? "Claude" : "agy";
    var dash = '<span class="usage-muted">' + USAGE_DASH + '</span>';
    var empty = '<span class="ur-m ur-m-' + src + ' ur-m-empty"><span class="ur-m-name">' + name + '</span>' + dash + '</span>';
    var td = (r && r.tokens_detail && typeof r.tokens_detail === "object") ? r.tokens_detail : null;
    var main = null, sub = null;
    if (src === "claude") {
      var cx = td && td.claude && td.claude.context && typeof td.claude.context === "object" ? td.claude.context : null;
      main = cx && cx.main && Number(cx.main.tokens) > 0 ? cx.main : null;
      sub = cx && cx.sub && Number(cx.sub.tokens) > 0 ? cx.sub : null;
    } else {
      var ag = td && td.agy && typeof td.agy === "object" ? td.agy : null;
      main = ag && Number(ag.context) > 0 ? { tokens: ag.context, model: ag.context_model, window: ag.context_window } : null;
    }
    if (!main) return empty;
    var fmt = function (n) { return Math.round(Number(n)).toLocaleString("en-US"); };
    var win = Number(main.window) > 0 ? Number(main.window) : 0;
    var tokens = Number(main.tokens);
    var subLine = sub ? "\n서브 최대 " + fmt(sub.tokens) + (Number(sub.window) > 0 ? " / " + fmt(sub.window) : "") + (sub.model ? " (" + sub.model + ")" : "") : "";
    if (!win) {
      var tipNo = "가장 큰 호출의 컨텍스트 " + fmt(tokens) + (main.model ? " / 모델 " + main.model : "") + " — 창 크기를 몰라 비율은 없습니다. models.json 의 context_window 에 적으면 보입니다." + subLine;
      return '<span class="ur-m ur-m-' + src + ' ur-m-ctx" title="' + escapeHtml(tipNo) + '"><span class="ur-m-name">' + name + '</span>' +
        '<span class="ur-m-ctxn ur-m-ctxn-n">' + escapeHtml(fmt(tokens)) + '</span><span class="ur-m-ctxn usage-muted">(창 크기 미설정)</span></span>';
    }
    var pct = tokens / win * 100;
    var width = Math.max(0, Math.min(100, pct));
    var tip = "가장 큰 호출의 컨텍스트 " + fmt(tokens) + " / 모델 " + (main.model || USAGE_DASH) + " 창 " + fmt(win) + subLine;
    return '<span class="ur-m ur-m-' + src + ' ur-m-ctx' + (pct >= 10 ? ' ur-m-hi' : '') + '" title="' + escapeHtml(tip) + '"><span class="ur-m-name">' + name + '</span>' +
      '<span class="ur-m-track" aria-hidden="true"><span class="ur-m-fill" style="width: ' + width.toFixed(1) + '%;"></span></span>' +
      '<span class="ur-m-pct">' + escapeHtml(usageFormatSharePct(pct)) + '</span>' +
      '<span class="ur-m-ctxn usage-muted">' + escapeHtml(fmt(tokens) + " / " + fmt(win)) + '</span></span>';
  }
  function usageQuotaBlockHtml(r) {
    var dash = '<span class="usage-muted">' + USAGE_DASH + '</span>';
    // 출처마다 자리를 고정한다: 값이 없는 출처도 "–" 로 자리를 채워, Claude 주간이 없을 때 agy 값이 Claude 자리로 밀리지 않게 한다.
    var isNonClaude = Boolean(r && r.src_client && !r.claude_model && !(r.quota && r.quota.claude) && !(Number(r.tokens) > 0));
    var srcs = isNonClaude ? ["agy"] : (r && r.mode === "delegate" ? ["claude", "agy"] : ["claude"]);
    var rowHtml = function (label, winKey) {
      var cells = srcs.map(function (s) {
        var d = usageShareData(r, s, winKey);
        if (d) return usageMeterHtml(d, true);
        return '<span class="ur-m ur-m-' + s + ' ur-m-empty"><span class="ur-m-name">' + (s === "claude" ? "Claude" : "agy") + '</span>' + dash + '</span>';
      });
      return '<div class="ur-quota-row"><span class="ur-quota-k">' + label + '</span><span class="ur-quota-v">' + cells.join("") + '</span></div>';
    };
    // 주간 배수 줄: 5시간 · 주간 줄과 같은 출처 칸에 "5시간 × 7.5" 로 적어 무엇의 배수인지 읽히게 한다.
    var q = r && r.quota && typeof r.quota === "object" ? r.quota : {};
    var sessCells = srcs.map(function (s) {
      var name = s === "claude" ? "Claude" : "agy";
      var sv = q[s] && q[s].sessions && Number(q[s].sessions.ratio) > 0 ? q[s].sessions : null;
      if (!sv) return '<span class="ur-m ur-m-' + s + ' ur-m-empty"><span class="ur-m-name">' + name + '</span>' + dash + '</span>';
      var ratioText = usageFormatSessRatio(sv.ratio);
      var tip = name + " 주간 한도 ≈ 5시간 한도의 " + ratioText + "배" +
        (Number(sv.five_points) > 0 && Number(sv.week_points) > 0 ? "\n같은 기간 5시간 사용률 " + sv.five_points + "%p 오르는 동안 주간 " + sv.week_points + "%p 상승" : "") +
        (sv.basis === "endpoints" ? "\n" + usageEndpointsTip() : "");
      return '<span class="ur-m ur-m-' + s + '" title="' + escapeHtml(tip) + '"><span class="ur-m-name">' + name + '</span>' +
        '<span class="ur-m-sess">5시간 × ' + escapeHtml(ratioText) + '</span></span>';
    });
    var ctxCells = srcs.map(function (s) { return usageContextCellHtml(r, s); });
    return '<div class="ur-quota">' + rowHtml("5시간", "five_hour") + rowHtml("주간", "weekly") +
      '<div class="ur-quota-row"><span class="ur-quota-k">주간 배수</span><span class="ur-quota-v">' + sessCells.join("") + '</span></div>' +
      '<div class="ur-quota-row"><span class="ur-quota-k">컨텍스트</span><span class="ur-quota-v">' + ctxCells.join("") + '</span></div></div>';
  }
  function usageLimitBannerHtml(limits) {
    if (!limits || typeof limits !== "object") return "";
    var sideHtml = function (label, eqLabel, side) {
      var s = side && typeof side === "object" ? side : {};
      var fh = s.five_hour && Number(s.five_hour.est) > 0 ? s.five_hour : null;
      var wk = s.weekly && Number(s.weekly.est) > 0 ? s.weekly : null;
      var sess = s.sessions && Number(s.sessions.ratio) > 0 ? s.sessions : null;
      var basis = s.basis && typeof s.basis === "object" ? s.basis : {};
      var fPts = Number(basis.five_points || (fh && fh.five_points) || 0);
      var wPts = Number(basis.week_points || (sess && sess.week_points) || 0);
      var sfPts = Number(basis.sessions_five_points || (sess && sess.five_points) || 0);

      var textParts = [];
      if (fh) textParts.push("5시간 ≈" + Number(fh.est).toLocaleString("en-US"));
      if (wk) textParts.push("주간 ≈" + Number(wk.est).toLocaleString("en-US"));
      if (sess) textParts.push(usageFormatSessRatio(sess.ratio) + " 세션");

      var bodyText;
      if (!fh && !wk && !sess) {
        bodyText = label + " 계산 중";
      } else {
        if (!fh) textParts.unshift("5시간 계산 중");
        if (!wk && !sess) textParts.push("주간·세션 계산 중");
        else if (!wk) textParts.push("주간 계산 중");
        else if (!sess) textParts.push("세션 계산 중");
        bodyText = label + " " + textParts.join(" · ");
      }

      var tips = [];
      if (fPts > 0 || wPts > 0 || sfPts > 0) {
        tips.push("누적 기준: 5시간 +" + fPts + "%p (세션 구간 5시간 +" + sfPts + "%p / 주간 +" + wPts + "%p)");
      } else {
        tips.push("계산 중 (클린 구간 누적 부족)");
      }
      tips.push("임계치: 5시간 10%p 초기 / 20%p 확정, 주간·세션은 주간 5%p + 5시간 20%p");
      if (fh && Number(fh.est_cost) > 0) {
        tips.push(eqLabel + " 입력 등가 한도: 5시간 ≈" + Number(fh.est_cost).toLocaleString("en-US") + (wk && Number(wk.est_cost) > 0 ? " / 주간 ≈" + Number(wk.est_cost).toLocaleString("en-US") : ""));
      }
      if (fh && fh.initial) tips.push("5시간은 초기 추정");
      if (sess && sess.basis === "endpoints") tips.push("세션: " + usageEndpointsTip());

      return '<span class="usage-limits-side" title="' + escapeHtml(tips.join(" · ")) + '">' + escapeHtml(bodyText) + '</span>';
    };
    return '<span class="usage-limits-title">현재 추정 한도 —</span> ' +
      sideHtml("Claude", "Opus", limits.claude) +
      ' <span class="usage-muted">/</span> ' +
      sideHtml("agy", "Neon", limits.agy);
  }
  function usageComboText(r) {
    // Claude 모델은 노력 단계까지("opus-5-5 (high)"). 예전 기록처럼 노력을 모르면 모델만.
    var srcCaller = r.src_label || r.src_model || (r.src_client ? (String(r.src_client).toLowerCase() === "antigravity" ? "Antigravity" : String(r.src_client)) : "");
    var claude = srcCaller || r.claude_label || r.claude_model || String(r.combo || "").split(" → ")[0] || "?";
    if (r.mode !== "delegate") return claude;
    if (r.agent_label && claude.indexOf(" › 서브 ") < 0) claude += " › 서브 " + r.agent_label;
    var agy = String(r.agy_models || "").split(",").map(function (m) { return usageAgyShort(m); }).filter(Boolean);
    var failed = (Array.isArray(r.agy_failed) ? r.agy_failed : (r.agy_failed ? [r.agy_failed] : [])).map(function (m) { return usageAgyShort(m); }).filter(Boolean);
    var failedPart = failed.length ? failed.map(function (m) { return m + " ✕"; }).join(" → ") + " → " : "";
    if (!agy.length) return claude + " → " + (failedPart ? failedPart + "?" : "?");
    var agyPart = (agy.length > 2 ? agy[0] + " 외 " + (agy.length - 1) : agy.join(", "));
    return claude + " → " + failedPart + agyPart;
  }

  // 질문 행의 열고 닫음: 다시 그려도 펼친 질문은 펼친 채로 남게 키(세션 + 질문 시각)로 기억한다(새로 고침하면 모두 접힘).
  var usageOpenRows = {};
  function usageRowKey(r) { return String(r.session || "") + "|" + String(r.q_ts || ""); }

  function usageTaskStatusLabel(st) {
    if (!st) return "진행 중";
    if (st === "OK") return "성공";
    if (st === "CANCELLED") return "취소";
    return "실패";
  }
  // 위임 작업 칩: "작업 1 · hydrogen-medium · 성공 · 12분" (누르면 위임 카드로)
  function usageTaskChipsHtml(r) {
    var ids = r.task_ids || [];
    if (!ids.length) return "";
    var byId = {};
    (r.tasks || []).forEach(function (t) { if (t && t.id) byId[t.id] = t; });
    var chips = ids.map(function (id, i) {
      var t = byId[id] || {};
      var numPart = escapeHtml("작업 " + (i + 1));
      var modelPart = "";
      if (t.tried && String(t.tried).indexOf("->") >= 0 && t.status === "OK") {
        var rawChain = String(t.tried).split("->").map(function (s) { return s.trim(); }).filter(Boolean);
        var usedIdx = t.model ? rawChain.indexOf(t.model) : -1;
        if (usedIdx < 0 && t.model) {
          var shortModel = usageAgyShort(t.model);
          for (var ci = 0; ci < rawChain.length; ci++) {
            if (usageAgyShort(rawChain[ci]) === shortModel) { usedIdx = ci; break; }
          }
        }
        var failedList = (usedIdx >= 0) ? rawChain.slice(0, usedIdx) : rawChain.slice(0, -1);
        var usedModel = (usedIdx >= 0) ? rawChain[usedIdx] : (t.model || rawChain[rawChain.length - 1]);
        if (failedList.length) {
          var failedHtml = failedList.map(function (m) {
            var title = "한도 · 과부하로 실패해 다음 모델로 넘어갔습니다: " + m;
            return '<span class="agy-failed" title="' + escapeHtml(title) + '">' + escapeHtml(usageAgyShort(m)) + ' ✕</span>';
          }).join(" → ");
          modelPart = failedHtml + " → " + escapeHtml(usageAgyShort(usedModel));
        } else if (t.model) {
          modelPart = escapeHtml(usageAgyShort(t.model));
        }
      } else if (t.model) {
        modelPart = escapeHtml(usageAgyShort(t.model));
      }
      var parts = [numPart];
      if (modelPart) parts.push(modelPart);
      parts.push(escapeHtml(usageTaskStatusLabel(t.status)));
      if (t.sec !== null && t.sec !== undefined) parts.push(escapeHtml(usageDur(t.sec)));
      var cls = "usage-chip" + (t.status === "OK" ? "" : (t.status ? " usage-chip-bad" : " usage-chip-wait"));
      var acctTip = (t.account && t.account !== "primary") ? (" [" + t.account + "]") : "";
      return '<a class="' + cls + '" href="#/qa?task=' + encodeURIComponent(id) + '" title="' + escapeHtml(id + (t.model ? " · " + t.model : "") + acctTip) + '">' + parts.join(" · ") + '</a>';
    }).join("");
    return '<div class="usage-chips ur-tasks">' + chips + '</div>';
  }

  // 모델 줄: 모델 기록이 없으면 흐린 안내
  function usageModelLineHtml(r) {
    var agy = String(r.agy_models || "").trim();
    var claude = r.src_label || r.src_model || r.src_client || r.claude_label || r.claude_model || "";
    if (!claude && !agy) return '<span class="usage-muted">모델 기록 없음</span>';
    return usageComboHtml(r);
  }

  function usageAccountBadgeHtml(account, fallbackFrom) {
    var acct = account ? String(account).trim() : "";
    var fb = fallbackFrom ? String(fallbackFrom).trim() : "";
    var labelFor = function (s) {
      var m = /^sub(\d+)$/i.exec(s);
      return m ? ("부계정 " + m[1]) : s;
    };
    if (acct && acct.toLowerCase() !== "primary") {
      var lbl = labelFor(acct);
      var tip = fb ? (lbl + " 실행 (" + fb + " 한도/미응답 대체)") : (lbl + " 슬롯 실행");
      var txt = fb ? (lbl + " ← 대체") : lbl;
      return '<span class="badge acct-badge acct-sub" title="' + escapeHtml(tip) + '">' + escapeHtml(txt) + '</span>';
    }
    if (fb) {
      var tipFb = "부계정(" + fb + ") 한도 소진/미응답으로 주 계정 폴백 실행";
      return '<span class="badge acct-badge acct-fallback" title="' + escapeHtml(tipFb) + '">주 ← 부계정 폴백</span>';
    }
    return "";
  }

  function usageRowAccountBadgesHtml(r) {
    if (!r) return "";
    if (Array.isArray(r.tasks) && r.tasks.length > 0) {
      var seen = {};
      var badges = [];
      r.tasks.forEach(function (t) {
        if (!t) return;
        var a = t.account ? String(t.account).trim() : "primary";
        var fb = t.fallback_from ? String(t.fallback_from).trim() : "";
        if (a.toLowerCase() === "primary" && !fb) return;
        var k = a + "|" + fb;
        if (seen[k]) return;
        seen[k] = true;
        var b = usageAccountBadgeHtml(a, fb);
        if (b) badges.push(b);
      });
      if (badges.length > 0) return badges.join(" ");
    }
    if (Array.isArray(r.sub_accounts) && r.sub_accounts.length > 0) {
      if (r.sub_accounts.length === 1) return usageAccountBadgeHtml(r.sub_accounts[0], r.fallback_from);
      return r.sub_accounts.map(function (sa) { return usageAccountBadgeHtml(sa, ""); }).filter(Boolean).join(" ");
    }
    return usageAccountBadgeHtml(r.account, r.fallback_from);
  }

  function usageRowHtml(r, index) {
    var key = usageRowKey(r);
    var open = Boolean(usageOpenRows[key]);
    var detailId = "ur-d-" + (index === undefined ? String(key).replace(/[^A-Za-z0-9]/g, "") : index);
    var project = usageProjectName(r.project);
    var total = usageTotalTokens(r);
    var preview = r.preview ? escapeHtml(r.preview) : '<span class="usage-muted">(글 없음)</span>';
    var tokTip = (function () {
      var p = usageTokenParts(r);
      if (r && r.src_client && p.claudeTotal <= 0) return "agy " + usageDashNum(p.agyTotal);
      return "Claude " + usageDashNum(p.claudeTotal) + (r.mode === "delegate" ? " · agy " + usageDashNum(p.agyTotal) : "");
    })();
    var acctBadge = usageRowAccountBadgesHtml(r);
    var scLower = String((r && r.src_client) || "").trim().toLowerCase();
    var isAgySrc = (scLower === "antigravity" || scLower === "agy");
    var rowModeBadgeHtml = (function () {
      if (r.mode === "direct") {
        return isAgySrc
          ? '<span class="badge usage-agy-direct" title="Antigravity 직접 처리">Agy</span>'
          : '<span class="badge usage-direct" title="Claude 직접 처리">Claude</span>';
      }
      if (r.mode === "delegate") {
        return isAgySrc
          ? '<span class="badge usage-delegate usage-a2a" title="Antigravity → Agy 위임">A → A</span>'
          : '<span class="badge usage-delegate usage-c2a" title="Claude → Agy 위임">C → A</span>';
      }
      var chatTip = isAgySrc ? "Antigravity 대화" : "Claude 대화";
      return '<span class="badge usage-' + escapeHtml(r.mode) + '" title="' + chatTip + '">' + usageModeLabel(r.mode) + '</span>';
    })();
    var reason = r.reason
      ? '<span class="ur-reason-k">사유</span> <span class="ur-reason-v">' + escapeHtml(r.reason) + '</span>'
      : '<span class="ur-reason-k">사유</span> <span class="usage-muted">기록 없음</span>';
    var qFull = String(r.preview || "");
    var toksHtml = usageTokensVisibleHtml(r);
    var subMetaHtml = toksHtml + (acctBadge ? '<span class="ur-accts">' + acctBadge + '</span>' : '');
    return '<div class="ur" role="listitem" data-row="' + escapeHtml(key) + '">' +
      '<div class="ur-sum" role="button" tabindex="0" aria-expanded="' + (open ? "true" : "false") + '" aria-controls="' + detailId + '">' +
        '<span class="ur-when">' + usageWhen(r.q_ts) + '</span>' +
        '<span class="ur-mode">' + rowModeBadgeHtml +
          (r.auto ? ' <span class="badge" title="자동 진행: /loop · 예약 실행으로 이어진 구간이라 한 건으로 묶였습니다">자동</span>' : '') + '</span>' +
        '<span class="ur-proj" title="' + escapeHtml(r.project || "") + '">' + (project ? escapeHtml(project) : USAGE_DASH) + '</span>' +
        '<span class="ur-q">' + preview + '</span>' +
        '<span class="ur-nums">' +
          '<span class="ur-dur">' + usageDashDur(r.dur_sec) + '</span>' +
          '<span class="ur-tok" title="' + escapeHtml(tokTip) + '">' + usageDashNum(total) + '</span>' +
          '<span class="ur-share">' + usageSummaryMeterHtml(r) + '</span>' +
        '</span>' +
        (subMetaHtml ? '<div class="ur-toks">' + subMetaHtml + '</div>' : '') +
      '</div>' +
      '<div class="ur-detail" id="' + detailId + '"' + (open ? "" : " hidden") + '>' +
        usageTaskChipsHtml(r) +
        usageLedgerHtml(r) +
        usageQuotaBlockHtml(r) +
        '<div class="ur-foot"><p class="ur-reason">' + reason + '</p>' +
          '<p class="ur-full" title="' + escapeHtml(qFull) + '">' + (qFull ? escapeHtml(qFull) : USAGE_DASH) + '</p></div>' +
      '</div></div>';
  }

  // 요약 줄 누르기 · Enter · Space: 바로 뒤의 상세를 열고 닫는다(el 은 .ur-sum)
  function usageToggleRow(el) {
    var detail = el && el.nextElementSibling;
    if (!detail) return;
    var open = detail.hidden;
    detail.hidden = !open;
    el.setAttribute("aria-expanded", open ? "true" : "false");
    var holder = el.parentElement;
    var key = holder && holder.getAttribute ? holder.getAttribute("data-row") : "";
    if (key) { if (open) { usageOpenRows[key] = true; } else { delete usageOpenRows[key]; } }
  }
  if (typeof document !== "undefined" && document.addEventListener) {
    document.addEventListener("click", function (e) {
      var sum = e.target && e.target.closest ? e.target.closest(".ur-sum") : null;
      if (sum) usageToggleRow(sum);
    });
    document.addEventListener("keydown", function (e) {
      if (e.key !== "Enter" && e.key !== " ") return;
      var sum = e.target && e.target.classList && e.target.classList.contains("ur-sum") ? e.target : null;
      if (!sum) return;
      e.preventDefault();
      usageToggleRow(sum);
    });
  }

  function usageRowsHtml(rows) {
    var list = rows || [];
    if (!list.length) return "";
    return list.map(function (r, i) { return usageRowHtml(r, i); }).join("");
  }

  // 화면 위쪽 안내 한 줄(없으면 빈 글자): 오류 > 수집 중 > 기록 없음
  function usageMessageText(data, error) {
    if (error) return error;
    if (!data) return "불러오는 중입니다.";
    var total = (data.summary && data.summary.total) || 0;
    if (data.collecting) {
      return total > 0 ? "대화 기록을 읽는 중입니다. 읽은 만큼 먼저 보입니다." : "대화 기록을 읽는 중입니다. 처음에는 수십 초 걸릴 수 있습니다.";
    }
    if (total === 0) return "이 기간에 기록된 질문이 없습니다. Claude Code 에서 질문을 한 뒤 '지금 갱신'을 누르세요.";
    return "";
  }

  function usageFilterRows(rows, clientFilter) {
    var list = Array.isArray(rows) ? rows : [];
    if (!clientFilter) return list;
    return list.filter(function (r) {
      if (!r) return false;
      var sc = String(r.src_client || "").trim().toLowerCase();
      var isAgy = (sc === "antigravity" || sc === "agy");
      if (clientFilter === "claude") return !isAgy;
      if (clientFilter === "agy") return isAgy;
      if (clientFilter === "claude_direct") return !isAgy && r.mode === "direct";
      if (clientFilter === "agy_direct") return isAgy && r.mode === "direct";
      if (clientFilter === "agy_delegate") return r.mode === "delegate";
      return true;
    });
  }

  function usageDiagGroupView(group, unackedList, samples) {
    var g = group || {};
    var cat = g.category || "";
    var label = g.label || cat || "기타";
    var count = Number(g.count || 0);
    var unacked = 0;
    if (Array.isArray(unackedList)) {
      for (var i = 0; i < unackedList.length; i++) {
        var u = unackedList[i];
        if (u && u.category === cat) {
          unacked = Number(u.count || 0);
          break;
        }
      }
    }
    var list = Array.isArray(samples) ? samples : [];
    var rows = list.filter(function (s) { return s && s.category === cat; }).slice(0, 3).map(function (s) {
      var rawDetail = String(s.detail || "").split(/\r?\n/)[0].trim();
      var text = rawDetail.length > 80 ? rawDetail.slice(0, 77) + "..." : rawDetail;
      return {
        when: usageWhen(s.timestamp || s.created_at || ""),
        text: text,
        taskId: String(s.task_id || s.id || ""),
        acked: Boolean(s.acked)
      };
    });
    return { label: label, count: count, unacked: unacked, rows: rows };
  }

  function renderUsageDiagnostics() {
    if (!els.usageDiagnosticsSection) return;
    var diag = usageDiagnosticsData;
    if (!diag || !Number(diag.total_failed)) {
      els.usageDiagnosticsSection.hidden = true;
      return;
    }
    els.usageDiagnosticsSection.hidden = false;
    if (els.usageDiagSummary) {
      els.usageDiagSummary.textContent = "최근 " + (diag.days || 14) + "일 · 실패/취소 " + diag.total_failed + "건 (스캔 " + (diag.total_scanned || 0) + "건)";
    }
    var resSum = diag.resolution_summary || null;
    var samplesList = Array.isArray(diag.samples) ? diag.samples : (Array.isArray(diag.records) ? diag.records : []);
    var resolvedN = resSum && resSum.resolved != null ? Number(resSum.resolved) : 0;
    var failedN = resSum && resSum.failed != null ? Number(resSum.failed) : 0;
    var remainingN = resSum && resSum.remaining != null ? Number(resSum.remaining) : (diag.unacked_total != null ? Number(diag.unacked_total) : 0);
    if (!resSum && samplesList.length > 0) {
      resolvedN = 0; failedN = 0; remainingN = 0;
      for (var si = 0; si < samplesList.length; si++) {
        var st = String(samplesList[si].ack_status || (samplesList[si].acked ? "resolved" : "open"));
        if (st === "resolved") resolvedN++;
        else if (st === "failed") failedN++;
        else remainingN++;
      }
    }
    if (els.usageDiagUnacked) {
      if (resSum || (diag.unacked_total != null && typeof diag.unacked_total !== "boolean" && !isNaN(Number(diag.unacked_total)))) {
        els.usageDiagUnacked.hidden = false;
        if (remainingN > 0 && failedN > 0) {
          els.usageDiagUnacked.className = "usage-diag-unacked is-failed";
          els.usageDiagUnacked.textContent = "남은 " + remainingN + "건 · 처리 실패 " + failedN + "건";
        } else if (remainingN > 0) {
          els.usageDiagUnacked.className = "usage-diag-unacked";
          els.usageDiagUnacked.textContent = "남은 건 " + remainingN + "건";
        } else if (failedN > 0) {
          els.usageDiagUnacked.className = "usage-diag-unacked is-failed";
          els.usageDiagUnacked.textContent = "처리 실패 " + failedN + "건";
        } else {
          els.usageDiagUnacked.className = "usage-diag-unacked is-acked";
          els.usageDiagUnacked.textContent = "모두 완료";
        }
      } else {
        els.usageDiagUnacked.hidden = true;
        els.usageDiagUnacked.textContent = "";
      }
    }
    if (els.usageDiagCounts) {
      var cb = diag.counts_by_status || {};
      var statusPills = [
        ["실패 (ERROR)", cb.ERROR || 0, ""],
        ["취소 (CANCELLED)", cb.CANCELLED || 0, ""],
        ["차단 (BLOCKED)", cb.BLOCKED || 0, ""],
        ["완료", resolvedN, " is-resolved"],
        ["처리 실패", failedN, failedN > 0 ? " is-failed" : ""],
        ["남은 건", remainingN, remainingN > 0 ? " is-remaining" : ""]
      ];
      els.usageDiagCounts.innerHTML = statusPills.map(function (p) {
        return '<span class="usage-diag-count-pill' + p[2] + '">' + escapeHtml(p[0]) + ": " + Number(p[1]).toLocaleString() + "건</span>";
      }).join("");
    }
    if (els.usageDiagBrief) {
      els.usageDiagBrief.textContent = diag.fix_brief || "";
    }
    if (els.usageDiagGroups) {
      var cats = Array.isArray(diag.by_category) ? diag.by_category : [];
      var unackedList = Array.isArray(diag.unacked_by_category) ? diag.unacked_by_category : [];
      var samples = samplesList;
      var orderedCats = cats.filter(function (g) { return g && g.category !== "user_cancelled"; })
        .concat(cats.filter(function (g) { return g && g.category === "user_cancelled"; }));
      els.usageDiagGroups.innerHTML = orderedCats.map(function (g) {
        var cat = g.category || "";
        var view = usageDiagGroupView(g, unackedList, samples);
        var isCancelled = (cat === "user_cancelled");
        var unackedBadge = view.unacked > 0
          ? '<span class="usage-diag-unacked">미처리 ' + view.unacked + '건</span>'
          : '';
        var ackBtn = view.unacked > 0
          ? '<button type="button" class="usage-diag-ack" data-category="' + escapeHtml(cat) + '" data-label="' + escapeHtml(view.label) + '" data-unacked="' + view.unacked + '">처리 표시</button>'
          : '';
        var headLeft = isCancelled ? ('▸ ' + escapeHtml(view.label)) : escapeHtml(view.label);
        var headInner = '<span>' + headLeft + '</span>' +
          '<span style="display:inline-flex;align-items:center;gap:6px;flex-wrap:wrap">' +
            '<span>' + view.count + '건</span>' + unackedBadge + ackBtn +
          '</span>';
        var casesHtml = view.rows.map(function (r) {
          var linkHtml = r.taskId
            ? '<a class="usage-diag-sample-link" href="#/qa?task=' + encodeURIComponent(r.taskId) + '" title="' + escapeHtml(r.taskId) + '">' + escapeHtml(r.taskId.slice(-12)) + '</a>'
            : '';
          var lineHtml = "";
          if (r.text) {
            var parts = [];
            if (r.when) parts.push(escapeHtml(r.when));
            parts.push(escapeHtml(r.text));
            if (linkHtml) parts.push(linkHtml);
            lineHtml = parts.join(" · ");
          } else {
            lineHtml = linkHtml;
          }
          if (!lineHtml) return "";
          return '<div class="usage-diag-case' + (r.acked ? ' is-acked' : '') + '">' + lineHtml + '</div>';
        }).join("");
        var bodyHtml = (g.root_cause ? '<div class="usage-diag-group-cause">' + escapeHtml(g.root_cause) + '</div>' : '') +
          (g.recommendation ? '<div class="usage-diag-group-rec">권장: ' + escapeHtml(g.recommendation) + '</div>' : '') +
          casesHtml;
        if (isCancelled) {
          return '<details class="usage-diag-group is-acked"><summary class="usage-diag-group-head" style="cursor:pointer">' + headInner + '</summary>' + bodyHtml + '</details>';
        }
        return '<div class="usage-diag-group"><div class="usage-diag-group-head">' + headInner + '</div>' + bodyHtml + '</div>';
      }).join("");
    }
    if (els.usageDiagHandled) {
      var handled = Array.isArray(diag.handled_records) ? diag.handled_records : [];
      if (handled.length === 0) {
        els.usageDiagHandled.hidden = true;
        els.usageDiagHandled.innerHTML = "";
      } else {
        els.usageDiagHandled.hidden = false;
        var handledSummary = "처리된 내역 · 완료 " + resolvedN + "건 · 처리 실패 " + failedN + "건 · 남은 건 " + remainingN + "건";
        var handledRowsHtml = handled.map(function (h) {
          var st = String(h.ack_status || "resolved");
          var badgeCls = st === "failed" ? "is-failed" : "is-resolved";
          var badgeText = st === "failed" ? "처리 실패" : "완료";
          var whenStr = usageWhen(h.acked_at || h.timestamp || "");
          var tid = String(h.task_id || "");
          var linkHtml = tid
            ? '<a class="usage-diag-sample-link" href="#/qa?task=' + encodeURIComponent(tid) + '" title="' + escapeHtml(tid) + '">' + escapeHtml(tid.slice(-12)) + '</a>'
            : '';
          var noteText = String(h.ack_note || "").trim() || "(메모 없음)";
          return '<div class="usage-diag-handled-row">' +
            '<span class="usage-diag-status-badge ' + badgeCls + '">' + badgeText + '</span>' +
            '<span class="usage-diag-handled-cat">' + escapeHtml(h.label || h.category || "기타") + '</span>' +
            '<span class="usage-diag-handled-note" title="' + escapeHtml(noteText) + '">' + escapeHtml(noteText) + '</span>' +
            '<span class="usage-diag-handled-when">' + escapeHtml(whenStr) + '</span>' +
            linkHtml +
          '</div>';
        }).join("");
        els.usageDiagHandled.innerHTML =
          '<details class="usage-diag-handled-box">' +
            '<summary class="usage-diag-handled-head"><span>' + escapeHtml(handledSummary) + '</span><span class="usage-diag-handled-count">' + handled.length + '건 표시</span></summary>' +
            '<div class="usage-diag-handled-list">' + handledRowsHtml + '</div>' +
          '</details>';
      }
    }
  }

  function loadUsageDiagnostics() {
    return fetchJson("/api/qa/diagnostics?days=14&limit=200")
      .then(function (d) {
        usageDiagnosticsData = d;
        if (currentNav === "stats") renderUsageDiagnostics();
      })
      .catch(function () {
        // 진단 API 실패 시 조용히 숨김 유지
      });
  }

  // ==========================================================================
  // 계정별 남은 한도 (클 · 주 · 부1 · 부2)
  // ==========================================================================

  function quotaLevelClass(remPct) {
    if (remPct == null || remPct === "" || typeof remPct === "boolean" || isNaN(Number(remPct))) {
      return "is-empty";
    }
    var n = Number(remPct);
    if (n <= 10) return "is-danger";
    if (n <= 30) return "is-warn";
    return "is-ok";
  }

  function formatQuotaResetText(win) {
    if (!win || !win.available) return "-";
    if (win.reset_passed) return "리셋됨";
    if (win.idle_window) return "현재 창 미사용";
    var sec;
    if (win.reset_in_sec != null && win.reset_in_sec !== "" && typeof win.reset_in_sec !== "boolean" && !isNaN(Number(win.reset_in_sec)) && Number(win.reset_in_sec) >= 0) {
      sec = Number(win.reset_in_sec);
    } else if (win.reset_at) {
      var ms = Date.parse(win.reset_at);
      if (isNaN(ms)) return "-";
      sec = Math.floor((ms - Date.now()) / 1000);
    } else {
      return "-";
    }
    if (sec <= 0) return "곧 리셋";
    if (sec < 3600) return Math.max(1, Math.round(sec / 60)) + "분 후 리셋";
    if (sec < 86400) {
      var h = Math.floor(sec / 3600);
      var m = Math.floor((sec % 3600) / 60);
      return m === 0 ? (h + "시간 후 리셋") : (h + "시간 " + m + "분 후 리셋");
    }
    var d = Math.floor(sec / 86400);
    var h2 = Math.floor((sec % 86400) / 3600);
    return h2 === 0 ? (d + "일 후 리셋") : (d + "일 " + h2 + "시간 후 리셋");
  }

  function formatQuotaAgoText(isoStr) {
    if (!isoStr) return "측정 기록 없음";
    var ms = Date.parse(isoStr);
    if (isNaN(ms)) return "측정 기록 없음";
    var sec = Math.floor((Date.now() - ms) / 1000);
    if (sec < 60) return "방금 전";
    if (sec < 3600) return Math.floor(sec / 60) + "분 전";
    if (sec < 86400) return Math.floor(sec / 3600) + "시간 전";
    return Math.floor(sec / 86400) + "일 전";
  }

  function formatQuotaPctText(val) {
    var clamped = Math.max(0, Math.min(100, Number(val)));
    if (Math.abs(clamped - Math.round(clamped)) < 0.005) {
      return Math.round(clamped) + "%";
    }
    return clamped.toFixed(2) + "%";
  }

  function quotaHueOf(remPct) {
    var p = Math.max(0, Math.min(100, Number(remPct)));
    return Math.round((p / 100) * 132);
  }

  function accountQuotaWindowHtml(title, win) {
    var hasPct = Boolean(win && win.available && win.remaining_pct != null && win.remaining_pct !== "" && typeof win.remaining_pct !== "boolean" && !isNaN(Number(win.remaining_pct)));
    var num = hasPct ? Number(win.remaining_pct) : null;
    var clamped = hasPct ? Math.max(0, Math.min(100, num)) : 0;
    var lvl = hasPct ? quotaLevelClass(num) : "is-empty";
    var pctText = hasPct ? formatQuotaPctText(clamped) : "\u2013";
    var hueStyle = hasPct ? (' style="--q-hue:' + quotaHueOf(clamped) + '"') : "";
    var barStyle = 'width:' + clamped.toFixed(2).replace(/\.?0+$/, "") + '%' + (hasPct ? (';--q-hue:' + quotaHueOf(clamped)) : "");
    var resetText = formatQuotaResetText(win);
    var tip = title + ": " + (hasPct ? ("남은 한도 " + pctText + " · " + resetText) : "측정 데이터 없음");
    return '<div class="quota-win-row" title="' + escapeHtml(tip) + '">' +
      '<div class="quota-win-head">' +
        '<span class="quota-win-label">' + escapeHtml(title) + '</span>' +
        '<span class="quota-win-pct ' + lvl + (hasPct ? ' has-q-hue' : '') + '"' + hueStyle + '>' + escapeHtml(pctText) + '</span>' +
      '</div>' +
      '<div class="quota-bar"><span class="quota-bar-fill ' + lvl + (hasPct ? ' has-q-hue' : '') + '" style="' + barStyle + '"></span></div>' +
      '<div class="quota-win-reset">' + escapeHtml(resetText) + '</div>' +
    '</div>';
  }

  function accountQuotaCardHtml(acct) {
    var a = acct || {};
    var id = a.id || "";
    var provider = a.provider || "";
    var badgeCls = provider === "claude" ? "is-claude" : ((provider === "primary" || id === "primary") ? "is-primary" : "is-sub");
    var stText = "대기";
    var stCls = "is-idle";
    if (a.refreshing) {
      stText = "갱신 중…";
      stCls = "is-refreshing";
    } else if (a.status === "cooldown") {
      stText = "쿨다운";
      stCls = "is-cooldown";
    } else if (a.status === "offline") {
      stText = "오프라인";
      stCls = "is-offline";
    } else if (a.status === "idle") {
      stText = "대기";
      stCls = "is-idle";
    } else if (provider === "claude" && a.refreshable === false) {
      stText = "자동 기록";
      stCls = "is-claude";
    } else if (a.status === "online") {
      stText = "정상";
      stCls = "is-online";
    } else if (provider === "claude") {
      stText = "대기";
      stCls = "is-idle";
    }
    var agoText = formatQuotaAgoText(a.measured_at);
    var tipParts = [];
    if (a.measured_at) tipParts.push("측정 시각: " + a.measured_at);
    if (a.note) tipParts.push(a.note);
    var footTip = tipParts.join(" · ");
    var subHtml = a.sub_label ? '<span class="quota-card-sub">' + escapeHtml(a.sub_label) + '</span>' : '';
    return '<article class="quota-card ' + badgeCls + (a.refreshing ? ' is-refreshing' : '') + (a.status ? ' status-' + escapeHtml(a.status) : '') + '" data-account-id="' + escapeHtml(id) + '" data-provider="' + escapeHtml(provider) + '">' +
      '<header class="quota-card-head">' +
        '<span class="quota-short-badge ' + badgeCls + '">' + escapeHtml(a.short_label || "") + '</span>' +
        '<div class="quota-card-titles">' +
          '<span class="quota-card-name">' + escapeHtml(a.label || id) + '</span>' +
          subHtml +
        '</div>' +
        '<span class="quota-status-pill ' + stCls + '">' + escapeHtml(stText) + '</span>' +
      '</header>' +
      '<div class="quota-card-windows">' +
        accountQuotaWindowHtml("5시간", a.five_hour) +
        accountQuotaWindowHtml("주간", a.weekly) +
      '</div>' +
      '<footer class="quota-card-foot"' + (footTip ? ' title="' + escapeHtml(footTip) + '"' : '') + '>' +
        '<span class="quota-card-ago">' + escapeHtml(agoText) + '</span>' +
      '</footer>' +
    '</article>';
  }

  function accountQuotasGridHtml(accounts) {
    var list = Array.isArray(accounts) ? accounts : [];
    if (!list.length) return "";
    return list.map(function (a) { return accountQuotaCardHtml(a); }).join("");
  }

  function sidebarQuotasHtml(accounts) {
    var list = Array.isArray(accounts) ? accounts : [];
    if (!list.length) return "";
    var chips = list.map(function (a) {
      a = a || {};
      var id = a.id || "";
      var provider = a.provider || "";
      var shortLbl = a.short_label || a.label || id;
      var fh = a.five_hour;
      var wk = a.weekly;
      var fhValid = Boolean(fh && fh.available && fh.remaining_pct != null && fh.remaining_pct !== "" && typeof fh.remaining_pct !== "boolean" && !isNaN(Number(fh.remaining_pct)));
      var wkValid = Boolean(wk && wk.available && wk.remaining_pct != null && wk.remaining_pct !== "" && typeof wk.remaining_pct !== "boolean" && !isNaN(Number(wk.remaining_pct)));
      var minPct = null;
      if (fhValid && wkValid) {
        minPct = Math.min(Number(fh.remaining_pct), Number(wk.remaining_pct));
      } else if (fhValid) {
        minPct = Number(fh.remaining_pct);
      } else if (wkValid) {
        minPct = Number(wk.remaining_pct);
      }
      var lvl = minPct != null ? quotaLevelClass(minPct) : "is-empty";
      var pctText = minPct != null ? (Math.round(Math.max(0, Math.min(100, minPct))) + "%") : "\u2013";
      var stText = a.refreshing ? "갱신 중…" : (a.status === "cooldown" ? "쿨다운" : (a.status === "offline" ? "오프라인" : (a.status === "idle" ? "대기" : (provider === "claude" ? "자동 기록" : (a.status === "online" ? "정상" : "대기")))));
      var fhTxt = fhValid ? (formatQuotaPctText(fh.remaining_pct) + " (" + formatQuotaResetText(fh) + ")") : "-";
      var wkTxt = wkValid ? (formatQuotaPctText(wk.remaining_pct) + " (" + formatQuotaResetText(wk) + ")") : "-";
      var titleStr = (a.label || shortLbl) + (a.sub_label ? " (" + a.sub_label + ")" : "") + " · " + stText + "\n5시간: " + fhTxt + "\n주간: " + wkTxt;
      var chipHueStyle = minPct != null ? (' style="--q-hue:' + quotaHueOf(minPct) + '"') : "";
      return '<button type="button" class="sidebar-quota-chip ' + lvl + (a.refreshing ? ' is-refreshing' : '') + '" data-account-id="' + escapeHtml(id) + '"' + chipHueStyle + ' title="' + escapeHtml(titleStr) + '">' +
        '<span class="sq-label">' + escapeHtml(shortLbl) + '</span>' +
        '<span class="sq-pct">' + escapeHtml(pctText) + '</span>' +
      '</button>';
    }).join("");
    return '<div class="sidebar-quotas-head">' +
        '<span>남은 한도</span>' +
        '<button type="button" class="sidebar-quotas-refresh" id="sidebar-quotas-refresh" title="계정별 한도 새로고침" aria-label="계정별 한도 새로고침">↻</button>' +
      '</div>' +
      '<div class="sidebar-quotas-row">' + chips + '</div>';
  }

  function sidebarQuotasSkeletonHtml() {
    var chips = "";
    for (var i = 0; i < 4; i++) {
      chips += '<span class="sidebar-quota-chip is-skeleton" aria-hidden="true"><span class="skel skel-xs" style="width:32px;height:11px"></span></span>';
    }
    return '<div class="sidebar-quotas-head"><span>남은 한도</span><span class="sidebar-quotas-refresh" aria-hidden="true">↻</span></div>' +
      '<div class="sidebar-quotas-row">' + chips + '</div>';
  }

  function accountQuotasSkeletonHtml() {
    var html = "";
    for (var i = 0; i < 4; i++) {
      html += '<article class="quota-card is-skeleton" aria-hidden="true">' +
        '<div class="quota-card-head"><span class="skel skel-badge"></span><span class="skel skel-title"></span><span class="skel skel-pill"></span></div>' +
        '<div class="quota-win"><div class="quota-win-row"><span class="skel skel-sm"></span><span class="skel skel-xs"></span></div><div class="skel skel-bar"></div><span class="skel skel-sub"></span></div>' +
        '<div class="quota-win"><div class="quota-win-row"><span class="skel skel-sm"></span><span class="skel skel-xs"></span></div><div class="skel skel-bar"></div><span class="skel skel-sub"></span></div>' +
        '<div class="quota-card-foot"><span class="skel skel-xs"></span></div>' +
      '</article>';
    }
    return html;
  }

  function usageSkeletonSummaryHtml() {
    var html = "";
    for (var i = 0; i < 6; i++) {
      html += '<div aria-hidden="true"><dt><span class="skel skel-xs"></span></dt><dd><span class="skel skel-md"></span></dd></div>';
    }
    return html;
  }

  function usageSkeletonRowsHtml(count) {
    var html = "";
    for (var i = 0; i < count; i++) {
      html += '<div class="skel-row" aria-hidden="true"><span class="skel skel-sm"></span><span class="skel skel-wide"></span><span class="skel skel-sm"></span></div>';
    }
    return html;
  }

  function renderAccountQuotas() {
    var d = accountQuotasData;
    var isInitialLoading = (d === null);
    var accounts = (d && Array.isArray(d.accounts)) ? d.accounts : [];
    var hasAccounts = accounts.length > 0;
    var showBlock = isInitialLoading || hasAccounts;
    var isRefreshing = Boolean((d && d.refreshing) || quotaRefreshingReq);
    var metaText = "";
    if (d && d.cooldown_sec > 0) {
      metaText = "쿨다운 " + d.cooldown_sec + "초 후 다시 시도 가능";
    } else if (isRefreshing) {
      metaText = "남은 한도를 조회하는 중…";
    } else if (d && d.measured_at) {
      metaText = "마지막 측정 " + formatQuotaAgoText(d.measured_at);
    }

    var gridHtml = isInitialLoading ? accountQuotasSkeletonHtml() : (hasAccounts ? accountQuotasGridHtml(accounts) : "");

    if (els.dashQuotasBlock) els.dashQuotasBlock.hidden = !showBlock;
    if (els.dashQuotasGrid && showBlock) els.dashQuotasGrid.innerHTML = gridHtml;
    if (els.dashQuotasMeta) els.dashQuotasMeta.textContent = metaText;
    if (els.dashQuotasRefresh) {
      els.dashQuotasRefresh.disabled = isRefreshing;
      els.dashQuotasRefresh.textContent = isRefreshing ? "조회 중…" : "한도 새로고침";
    }

    if (els.statsQuotasBlock) els.statsQuotasBlock.hidden = !showBlock;
    if (els.statsQuotasGrid && showBlock) els.statsQuotasGrid.innerHTML = gridHtml;
    if (els.statsQuotasMeta) els.statsQuotasMeta.textContent = metaText;
    if (els.statsQuotasRefresh) {
      els.statsQuotasRefresh.disabled = isRefreshing;
      els.statsQuotasRefresh.textContent = isRefreshing ? "조회 중…" : "한도 새로고침";
    }

    if (els.sidebarQuotas) {
      els.sidebarQuotas.hidden = !showBlock;
      if (isInitialLoading) {
        els.sidebarQuotas.innerHTML = sidebarQuotasSkeletonHtml();
      } else if (hasAccounts) {
        els.sidebarQuotas.innerHTML = sidebarQuotasHtml(accounts);
        var sbBtn = els.sidebarQuotas.querySelector("#sidebar-quotas-refresh");
        if (sbBtn) {
          sbBtn.disabled = isRefreshing;
          sbBtn.classList.toggle("is-spinning", isRefreshing);
        }
      } else {
        els.sidebarQuotas.innerHTML = "";
      }
    }
  }

  var QUOTA_AUTO_RELOAD_MS = 5 * 60 * 1000;

  function scheduleQuotaPoll() {
    if (quotaPollTimer) { clearTimeout(quotaPollTimer); quotaPollTimer = null; }
    if (quotaPollCount < 18) {
      quotaPollTimer = setTimeout(function () {
        quotaPollCount++;
        loadAccountQuotas();
      }, 2500);
    }
  }

  function loadAccountQuotas() {
    lastQuotaLoadAt = Date.now();
    return fetchJson("/api/quotas")
      .then(function (d) {
        if (!d || !Array.isArray(d.accounts) || !d.accounts.length) {
          if (quotaPollTimer) { clearTimeout(quotaPollTimer); quotaPollTimer = null; }
          accountQuotasData = d || null;
          renderAccountQuotas();
          return d;
        }
        accountQuotasData = d;
        renderAccountQuotas();
        if (d.refreshing && quotaPollCount < 18) {
          scheduleQuotaPoll();
        } else if (quotaPollTimer) {
          clearTimeout(quotaPollTimer);
          quotaPollTimer = null;
        }
        return d;
      })
      .catch(function () {
        if (quotaPollTimer) { clearTimeout(quotaPollTimer); quotaPollTimer = null; }
        return null;
      });
  }

  function triggerAccountQuotasRefresh() {
    if (quotaRefreshingReq) return;
    quotaRefreshingReq = true;
    if (quotaPollTimer) { clearTimeout(quotaPollTimer); quotaPollTimer = null; }
    renderAccountQuotas();
    return fetch("/api/quotas/refresh", { method: "POST", headers: { "X-Samjil-Viewer": "1" } })
      .then(function (r) {
        if (!r.ok) { throw new Error("HTTP " + r.status); }
        return r.text().then(function (t) {
          if (!t) return null;
          if (t.charCodeAt(0) === 0xFEFF) { t = t.slice(1); }
          return JSON.parse(t);
        });
      })
      .then(function (d) {
        quotaRefreshingReq = false;
        quotaPollCount = 0;
        if (d) {
          if (Array.isArray(d.accounts)) {
            accountQuotasData = d;
          } else if (accountQuotasData) {
            accountQuotasData = {
              accounts: accountQuotasData.accounts,
              refreshing: Boolean(d.refreshing),
              cooldown_sec: d.cooldown_sec || 0,
              measured_at: d.measured_at || accountQuotasData.measured_at
            };
          } else {
            accountQuotasData = d;
          }
        }
        renderAccountQuotas();
        if (d && d.refreshing) {
          scheduleQuotaPoll();
        }
      })
      .catch(function () {
        quotaRefreshingReq = false;
        renderAccountQuotas();
      });
  }

  function renderUsageStats() {
    if (!els.viewStats) return;
    Array.prototype.forEach.call(document.querySelectorAll(".usage-day-btn"), function (btn) {
      btn.setAttribute("aria-pressed", parseInt(btn.dataset.days, 10) === usageDays ? "true" : "false");
    });
    var d = usageData;
    var summary = (d && d.summary) || null;
    var isInitialLoading = (!d && !usageError);
    var msg = usageMessageText(d, usageError);
    // 최초 로딩(스켈레톤으로 공간 고정) 또는 이미 데이터가 있는 백그라운드 수집 중일 때는 상단 배너를 띄우지 않아 레이아웃 밀림을 방지한다.
    var inlineCollecting = Boolean(!usageError && (isInitialLoading || (d && d.collecting && summary && summary.total > 0)));
    if (els.usageMessage) {
      els.usageMessage.textContent = inlineCollecting ? "" : msg;
      els.usageMessage.hidden = inlineCollecting || !msg;
      els.usageMessage.classList.toggle("usage-message-error", !!usageError);
    }
    if (els.usageUpdated) {
      if (isInitialLoading) {
        els.usageUpdated.textContent = "불러오는 중";
        els.usageUpdated.title = "실측 통계를 불러오는 중입니다.";
      } else if (d && d.collecting) {
        els.usageUpdated.textContent = "수집 중";
        els.usageUpdated.title = "대화 기록을 읽는 중입니다. 읽은 만큼 먼저 보입니다.";
      } else {
        els.usageUpdated.textContent = (d && d.updated_at) ? usageWhen(d.updated_at) + " 갱신" : "";
        els.usageUpdated.title = "";
      }
    }
    if (els.usageCount) els.usageCount.textContent = "최근 " + usageDays + "일";
    if (els.usageSummary) {
      els.usageSummary.innerHTML = summary ? usageSummaryStats(summary).map(function (s) {
        return '<div' + (s[2] ? ' title="' + escapeHtml(s[2]) + '"' : '') + '><dt>' + s[0] + '</dt><dd>' + escapeHtml(s[1]) + '</dd></div>';
      }).join("") : (isInitialLoading ? usageSkeletonSummaryHtml() : "");
    }
    if (els.usageModes) {
      els.usageModes.innerHTML = (summary && summary.total > 0)
        ? usageModeTableHtml(summary)
        : (isInitialLoading ? '<tbody><tr><td>' + usageSkeletonRowsHtml(4) + '</td></tr></tbody>' : "");
    }
    if (els.usageModels) {
      els.usageModels.innerHTML = d ? (usageModelTableHtml(d.by_model) || "") : (isInitialLoading ? usageSkeletonRowsHtml(3) : "");
    }
    if (els.usageDaily) {
      els.usageDaily.innerHTML = d ? (usageDailyHtml(d.daily) || '<span class="empty-hint">표시할 날이 없습니다.</span>') : (isInitialLoading ? '<div class="skel-chart" aria-hidden="true"></div>' : "");
    }
    if (els.usageLimitsBanner) {
      var limBanner = d ? usageLimitBannerHtml(d.limits) : "";
      if (summary && summary.sub_quotas && typeof summary.sub_quotas === "object") {
        var sqKeys = Object.keys(summary.sub_quotas).sort();
        if (sqKeys.length) {
          var sqParts = sqKeys.map(function (sk) {
            var q = summary.sub_quotas[sk];
            if (!q) return "";
            var m = /^sub(\d+)$/i.exec(sk);
            var nm = m ? ("부계정 " + m[1]) : sk;
            var f = (q.five_used != null) ? (Math.round(Number(q.five_used)) + "%") : "-";
            var w = (q.week_used != null) ? (Math.round(Number(q.week_used)) + "%") : "-";
            return '<span class="usage-subquota-pill" title="부계정 참고 실측 (' + escapeHtml(q.measured_at || "") + ')">' + escapeHtml(nm + " 5h " + f + " · 주간 " + w) + '</span>';
          }).filter(Boolean);
          if (sqParts.length) {
            limBanner = (limBanner ? limBanner + ' ' : '') + '<span class="usage-subquotas">' + sqParts.join(" ") + '</span>';
          }
        }
      }
      els.usageLimitsBanner.innerHTML = limBanner;
      els.usageLimitsBanner.hidden = !limBanner;
    }
    var filteredRows = usageFilterRows(d ? d.rows : [], usageClientFilter);
    var visibleRows = filteredRows.slice(0, usageRowsVisibleCount);
    if (els.usageRows) els.usageRows.innerHTML = d ? usageRowsHtml(visibleRows) : (isInitialLoading ? usageSkeletonRowsHtml(5) : "");
    if (els.usageLoadmore) {
      var remaining = filteredRows.length - visibleRows.length;
      els.usageLoadmore.hidden = remaining <= 0;
      if (els.usageLoadmoreInfo) {
        els.usageLoadmoreInfo.textContent = remaining > 0 ? ("남은 " + remaining.toLocaleString() + "건") : "";
      }
    }
    if (els.usageRowsCount) {
      var shown = visibleRows.length;
      var filteredTotal = filteredRows.length;
      var total = summary ? summary.total : 0;
      els.usageRowsCount.textContent = shown < filteredTotal
        ? shown + " / " + filteredTotal.toLocaleString() + "건 (전체 " + total.toLocaleString() + "건)"
        : (filteredTotal < total ? filteredTotal + "건 (전체 " + total.toLocaleString() + "건)" : shown + "건");
    }
    renderUsageDiagnostics();
    updateTopbarMeta();
  }

  // 화면 전환 때: 실측 통계로 들어오면 그리고 불러오고, 나가면 다시 묻기 예약을 푼다.
  function enterOrLeaveUsageStats(entering) {
    if (entering) {
      renderAccountQuotas();
      if (!lastQuotaLoadAt || (Date.now() - lastQuotaLoadAt >= QUOTA_AUTO_RELOAD_MS)) { loadAccountQuotas(); }
      if (allItems.length > 0 || pendingItems.length > 0) { renderQuickSessions(); }
      renderUsageStats();
      loadUsageStats(false);
      if (!usageDiagnosticsData) { loadUsageDiagnostics(); }
    } else if (usageTimer) {
      clearTimeout(usageTimer);
      usageTimer = null;
    }
  }

  function loadUsageStats(refresh) {
    if (usageTimer) { clearTimeout(usageTimer); usageTimer = null; }
    var asked = usageDays;
    return fetchJson("/api/usage-stats?days=" + asked + "&limit=200" + (refresh ? "&refresh=1" : ""))
      .then(function (d) {
        if (asked !== usageDays) return;
        usageData = d;
        usageError = "";
      })
      .catch(function () {
        if (asked !== usageDays) return;
        usageError = "실측 통계를 불러오지 못했습니다. 뷰어 서버가 켜져 있는지 확인하세요.";
      })
      .then(function () {
        if (asked !== usageDays || currentNav !== "stats") return;
        renderUsageStats();
        // 수집 중이면 3초 뒤, 아니면 1분 뒤 다시 묻는다(화면이 열려 있는 동안만)
        usageTimer = setTimeout(function () { loadUsageStats(false); }, (usageData && usageData.collecting) ? 3000 : 60000);
      });
  }

  // ==========================================================================
  // 2. 에이전트 위임 메인 뷰 (QA Cards & Session Thread Rendering)
  // ==========================================================================

  function uniqueModels() {
    var set = {};
    allItems.forEach(function (r) { if (recordModel(r)) { set[recordModel(r)] = true; } });
    pendingItems.forEach(function (p) { if (p.model) { set[p.model] = true; } });
    return Object.keys(set).sort();
  }

  function populateModelFilter() {
    if (!els.modelFilter) return;
    var current = els.modelFilter.value;
    var models = uniqueModels();
    els.modelFilter.innerHTML = '<option value="">모든 모델</option>';
    models.forEach(function (m) {
      var o = document.createElement("option");
      o.value = m; o.textContent = m;
      els.modelFilter.appendChild(o);
    });
    if (models.indexOf(current) !== -1) { els.modelFilter.value = current; }
  }

  function renderQaAgyChips() {
    if (!els.qaSessionChips) return;

    var agySessions = qaAgySessionsOf(allItems, pendingItems, claudeTree, currentQaProject, currentQaSession);
    var hasNamed = agySessions.some(function (s) { return s.name !== "__none__"; });

    if (!hasNamed) {
      els.qaSessionChips.hidden = true;
      els.qaSessionChips.innerHTML = "";
      currentQaAgy = "";
      return;
    }

    els.qaSessionChips.hidden = false;

    var totalCount = 0;
    var totalPending = 0;
    var totalErrors = 0;
    var namedSessions = [];
    var noneSession = null;

    for (var i = 0; i < agySessions.length; i++) {
      var s = agySessions[i];
      totalCount += (s.total + s.pending);
      totalPending += s.pending;
      totalErrors += s.errors;
      if (s.name === "__none__") {
        noneSession = s;
      } else {
        namedSessions.push(s);
      }
    }

    var validAgys = { "": true };
    for (var n = 0; n < namedSessions.length; n++) {
      validAgys[namedSessions[n].name] = true;
    }
    if (noneSession) {
      validAgys["__none__"] = true;
    }

    if (currentQaAgy && !validAgys[currentQaAgy]) {
      currentQaAgy = "";
    }

    function buildChipHtml(agyVal, displayName, count, pending, errors) {
      var isActive = (currentQaAgy === agyVal);
      var dotHtml = (pending > 0) ? '<span class="pending-pulse-dot"></span>' : '';
      var errHtml = (errors > 0) ? '<span class="qa-chip-err">실패 ' + errors + '</span>' : '';
      return [
        '<button type="button" class="qa-chip' + (isActive ? ' active' : '') + '" data-agy="' + escapeHtml(agyVal) + '">',
        dotHtml,
        '<span class="qa-chip-name">' + escapeHtml(displayName) + '</span>',
        '<span class="qa-chip-count">' + count + '</span>',
        errHtml,
        '</button>'
      ].join("");
    }

    var split = qaChipSplit(namedSessions, currentQaAgy, QA_CHIP_VISIBLE);
    var collapsible = split.hidden.length > 0;
    if (!collapsible) { qaChipsExpanded = false; }
    var chipSessions = (collapsible && qaChipsExpanded) ? namedSessions : split.shown;

    var htmlParts = [];
    htmlParts.push(buildChipHtml("", "전체", totalCount, totalPending, totalErrors));
    for (var sIdx = 0; sIdx < chipSessions.length; sIdx++) {
      var ns = chipSessions[sIdx];
      htmlParts.push(buildChipHtml(ns.name, ns.name, ns.total + ns.pending, ns.pending, ns.errors));
    }
    if (noneSession) {
      htmlParts.push(buildChipHtml("__none__", "단발성", noneSession.total + noneSession.pending, noneSession.pending, noneSession.errors));
    }
    if (collapsible) {
      var moreErr = (!qaChipsExpanded && split.hiddenErrors > 0) ? '<span class="qa-chip-err">실패 ' + split.hiddenErrors + '</span>' : '';
      htmlParts.push(
        '<button type="button" class="qa-chip qa-chip-more" data-more="1" aria-expanded="' + (qaChipsExpanded ? "true" : "false") + '">' +
        '<span class="qa-chip-name">' + (qaChipsExpanded ? "접기" : "다른 세션 " + split.hidden.length + "개 더 보기") + '</span>' + moreErr + '</button>'
      );
    }

    els.qaSessionChips.classList.toggle("expanded", collapsible && qaChipsExpanded);
    els.qaSessionChips.innerHTML = htmlParts.join("");

    els.qaSessionChips.onclick = function (e) {
      var btn = e.target && e.target.closest ? e.target.closest(".qa-chip") : null;
      if (!btn) return;
      if (btn.getAttribute("data-more")) {
        qaChipsExpanded = !qaChipsExpanded;
        renderQaAgyChips();
        var again = els.qaSessionChips.querySelector(".qa-chip-more");
        if (again && again.focus) { again.focus({ preventScroll: true }); }   // 다시 그려도 키보드 위치를 잃지 않게(칩 영역은 맨 위에서 시작)
        els.qaSessionChips.scrollTop = 0;
        return;
      }
      var agy = btn.getAttribute("data-agy") || "";
      selectQaAgy(agy);
    };
  }

  function applyQaFilters() {
    var q = (els.qaSearch ? els.qaSearch.value : "").trim().toLowerCase();
    var model = els.modelFilter ? els.modelFilter.value : "";
    var status = els.statusFilter ? els.statusFilter.value : "";

    // 1. 이미 완료된 task_id 집합
    var finishedTaskIds = {};
    allItems.forEach(function (r) {
      if (r && r.task_id) { finishedTaskIds[r.task_id] = true; }
    });

    // 2. pending 목록 필터링
    if (status) {
      filteredPending = [];
    } else {
      filteredPending = pendingItems.filter(function (p) {
        if (!p || !p.task_id) return false;
        if (finishedTaskIds[p.task_id]) return false;
        if (!qaItemMatchesSelection(p, claudeTree, currentQaProject, currentQaSession, qaSource)) return false;
        if (!qaItemMatchesAgy(p, currentQaAgy)) return false;
        if (model && p.model !== model) return false;
        if (q) {
          var qText = (p.question || "").toLowerCase();
          var mText = (p.model || "").toLowerCase();
          var tText = (p.task_id || "").toLowerCase();
          if (qText.indexOf(q) === -1 && mText.indexOf(q) === -1 && tText.indexOf(q) === -1) return false;
        }
        return true;
      });
    }

    // 3. 완료 레코드 필터링
    filteredQa = allItems.filter(function (r) {
      if (!qaItemMatchesSelection(r, claudeTree, currentQaProject, currentQaSession, qaSource)) return false;
      if (!qaItemMatchesAgy(r, currentQaAgy)) return false;
      if (model && recordModel(r) !== model) return false;
      if (status) {
        var stUp = String(r.status || "").trim().toUpperCase();
        var isOkRec = isOkStatus(r);
        if (status === "OK" && !isOkRec) return false;
        if (status === "ERROR" && isOkRec) return false;
        if (status === "CANCELLED" && stUp !== "CANCELLED") return false;
        if (status === "BLOCKED" && stUp !== "BLOCKED") return false;
      }
      if (q) {
        var hay = [recordModel(r), r.computer_name, r.task_id, r.source, r.session, r.session_id, r.question, r.answer]
          .map(function (v) { return v == null ? "" : String(v); })
          .join(" ").toLowerCase();
        if (hay.indexOf(q) === -1) return false;
      }
      return true;
    });

    renderQaAgyChips();

    // 헤더 건수는 filteredQa/filteredPending 을 읽으므로 반드시 필터 계산 뒤에 갱신한다.
    // (앞에서 부르면 직전 값이 표시되어, 대시보드에서 막 넘어왔을 때 "0건"으로 보였다.)
    updateQaHeader();

    shownQaCount = 0;
    if (els.cards) {
      els.cards.innerHTML = "";

      // pending 카드를 목록 상단에 렌더링
      if (filteredPending.length > 0) {
        var pFrag = document.createDocumentFragment();
        filteredPending.forEach(function (p) {
          var qIdx = pendingItems.indexOf(p);
          if (qIdx < 0) qIdx = 0;
          pFrag.appendChild(buildPendingCard(p, qIdx));
        });
        els.cards.appendChild(pFrag);
      }
    }

    renderMoreQa();
    renderProcessDialog();
    updateTopbarMeta();
  }

  // 질문/답변 구역의 펼침 상태(과정은 카드 맨 윗줄의 버튼으로 창을 연다).
  //   기본: 모든 카드의 질문·과정·답변을 접은 채로 시작한다(맨 위 카드와 실행 중인 카드도 접는다).
  //   사용자가 직접 열거나 닫은 구역만 qaOpenOverrides 에 기억해서, 5초마다 카드를 다시 그려도 그대로 유지한다.
  //   (예전에는 그리기 직전의 "현재 상태"를 통째로 저장했는데, 그러면 기본으로 펼쳐졌던 카드도 사용자가 연 것으로
  //   기억돼 새 카드가 생겨도 이전 카드가 계속 펼쳐 있었다.)
  var qaOpenOverrides = {};   // "<카드 키>|q" / "|a" -> true(열었음) / false(닫았음)

  function qaSectionKey(d) {
    var type = d.classList.contains("q") ? "q" : "a";
    return d.parentNode.getAttribute("data-key") + "|" + type;
  }

  // 사용자가 건드리지 않은 구역을 기본으로 펼칠지. 접속 직후에는 맨 위 카드든 실행 중인 카드든 모두 접은 채로 시작한다(사용자 요청).
  // 필요한 카드만 사용자가 직접 펼치고, 그 선택은 qaOpenOverrides 로 기억한다.
  function qaDefaultAnswerOpen(o) {
    return false;
  }

  function applyQaOpenDefaults() {
    if (!els.cards) return;
    var first = els.cards.querySelector(".card[data-key]");
    var items = els.cards.querySelectorAll(".card[data-key] > details.qa");
    for (var i = 0; i < items.length; i++) {
      var d = items[i];
      var k = qaSectionKey(d);
      d.open = Object.prototype.hasOwnProperty.call(qaOpenOverrides, k)
        ? qaOpenOverrides[k]
        : qaDefaultAnswerOpen({
            isFirst: d.parentNode === first,
            isAnswer: d.classList.contains("a"),
            isProcessing: d.parentNode.classList.contains("processing")
          });
    }
  }

  function updateQaHeader() {
    if (!els.qaCurrentSessionTitle) return;

    if (!currentQaProject) {
      els.qaCurrentSessionTitle.textContent = "전체 프로젝트 피드";
    } else {
      var tree = buildQaTree(allItems, pendingItems, claudeTree);
      var titles = findQaNodeTitles(tree, currentQaProject, currentQaSession);
      if (!currentQaSession) {
        els.qaCurrentSessionTitle.textContent = titles.projectName;
      } else {
        els.qaCurrentSessionTitle.textContent = titles.sessionTitle;
      }
    }

    var totalInSession = filteredQa.length + filteredPending.length;
    if (els.qaCurrentSessionCount) {
      els.qaCurrentSessionCount.textContent = totalInSession + "건";
    }

    var latestItem = filteredPending[0] || filteredQa[0];
    if (els.chipQaTime) {
      els.chipQaTime.textContent = "최근 작업: " + (latestItem ? (latestItem.timestamp || latestItem.created || "-") : "-");
    }
    if (els.chipQaModels) {
      var mVal = els.modelFilter ? els.modelFilter.value : "";
      els.chipQaModels.textContent = "모델: " + (mVal || "전체");
    }
    if (els.chipQaStatus) {
      var sVal = els.statusFilter ? els.statusFilter.value : "";
      els.chipQaStatus.textContent = "상태: " + (sVal || "전체");
    }
    if (els.qaDiagChip) {
      var errCnt = 0, cancelCnt = 0, blockCnt = 0;
      filteredQa.forEach(function (r) {
        var su = String((r && r.status) || "").trim().toUpperCase();
        if (su === "CANCELLED") cancelCnt++;
        else if (su === "BLOCKED") blockCnt++;
        else if (su && !isOkStatus(r)) errCnt++;
      });
      var totalBad = errCnt + cancelCnt + blockCnt;
      if (totalBad > 0) {
        var parts = [];
        if (errCnt > 0) parts.push("실패 " + errCnt);
        if (cancelCnt > 0) parts.push("취소 " + cancelCnt);
        if (blockCnt > 0) parts.push("차단 " + blockCnt);
        els.qaDiagChip.textContent = "진단: " + parts.join(" · ");
        els.qaDiagChip.classList.toggle("active", Boolean(els.statusFilter && (els.statusFilter.value === "ERROR" || els.statusFilter.value === "CANCELLED" || els.statusFilter.value === "BLOCKED")));
        els.qaDiagChip.hidden = false;
      } else {
        els.qaDiagChip.hidden = true;
      }
    }
  }

  function renderMoreQa() {
    if (!els.cards) return;
    var next = filteredQa.slice(shownQaCount, shownQaCount + PAGE_SIZE);
    var frag = document.createDocumentFragment();
    next.forEach(function (r) {
      frag.appendChild(buildCard(r));
    });
    els.cards.appendChild(frag);
    shownQaCount += next.length;

    if (els.loadMoreBtn) {
      els.loadMoreBtn.hidden = (shownQaCount >= filteredQa.length);
    }

    if (shownQaCount === 0 && filteredPending.length === 0) {
      els.cards.innerHTML = '<p class="empty">해당 세션 또는 조건에 일치하는 위임 기록이 없습니다.</p>';
    }
    applyQaOpenDefaults();
  }

  // ==========================================================================
  // Image & Lightbox Logic
  // ==========================================================================

  function initImagePopups() {
    if (!document.getElementById("image-hover-popup")) {
      var hp = document.createElement("div");
      hp.id = "image-hover-popup";
      hp.innerHTML = '<img src="" alt="미리보기"><div class="popup-caption"></div>';
      document.body.appendChild(hp);
    }

    if (!document.getElementById("image-lightbox")) {
      var lb = document.createElement("div");
      lb.id = "image-lightbox";
      lb.innerHTML = [
        '<div class="lightbox-header">',
        '  <span class="lightbox-title"></span>',
        '  <div class="lightbox-actions">',
        '    <a class="lightbox-btn lightbox-open-newtab" href="#" target="_blank" rel="noopener" title="새 탭에서 원본 열기">새 탭에서 열기</a>',
        '    <button class="lightbox-btn lightbox-close" type="button" title="닫기 (Esc)">닫기</button>',
        '  </div>',
        '</div>',
        '<div class="lightbox-img-wrap">',
        '  <img class="lightbox-img" src="" alt="확대 이미지">',
        '</div>'
      ].join("");

      lb.addEventListener("click", function (e) {
        if (e.target === lb || e.target.classList.contains("lightbox-img-wrap") || e.target.classList.contains("lightbox-close")) {
          closeLightbox();
        }
      });

      document.addEventListener("keydown", function (e) {
        if (e.key === "Escape") { closeLightbox(); }
      });

      document.body.appendChild(lb);
    }
  }

  function makeImageUrl(imgPath, cwd) {
    var url = "/image?path=" + encodeURIComponent(imgPath);
    if (cwd) { url += "&cwd=" + encodeURIComponent(cwd); }
    return url;
  }

  function showHoverPopup(e, imgUrl, label) {
    var hp = document.getElementById("image-hover-popup");
    if (!hp) return;
    var img = hp.querySelector("img");
    var caption = hp.querySelector(".popup-caption");
    if (img) img.src = imgUrl;
    if (caption) caption.textContent = label || imgUrl;
    hp.style.display = "flex";

    var x = e.clientX + 16;
    var y = e.clientY + 16;
    var vw = window.innerWidth;
    var vh = window.innerHeight;
    if (x + 520 > vw) x = Math.max(10, e.clientX - 530);
    if (y + 420 > vh) y = Math.max(10, vh - 430);
    hp.style.left = x + "px";
    hp.style.top = y + "px";
  }

  function hideHoverPopup() {
    var hp = document.getElementById("image-hover-popup");
    if (hp) hp.style.display = "none";
  }

  function openLightbox(imgUrl, label) {
    hideHoverPopup();
    var lb = document.getElementById("image-lightbox");
    if (!lb) return;
    var img = lb.querySelector(".lightbox-img");
    var title = lb.querySelector(".lightbox-title");
    var openBtn = lb.querySelector(".lightbox-open-newtab");
    if (img) img.src = imgUrl;
    if (title) title.textContent = label || "이미지 원본 보기";
    if (openBtn) openBtn.href = imgUrl;
    lb.style.display = "flex";
    document.body.style.overflow = "hidden";
  }

  function closeLightbox() {
    var lb = document.getElementById("image-lightbox");
    if (!lb) return;
    lb.style.display = "none";
    var img = lb.querySelector(".lightbox-img");
    if (img) img.src = "";
    document.body.style.overflow = "";
  }

  // @cwd 값(문자열 하나, 폴더 배열, 없음)을 폴더 문자열 배열로 만든다. 빈 값과 중복(대소문자, 끝의 \ 또는 / 무시)은 뺀다.
  // 서버가 예전에는 문자열 하나를, 지금은 폴더 배열을 주므로 둘 다 받는다(예전 기록·옛 서버도 그대로 보인다).
  function cwdListOf(value) {
    var src = Array.isArray(value) ? value : (value == null ? [] : [value]);
    var out = [], seen = {};
    for (var i = 0; i < src.length; i++) {
      var s = String(src[i] == null ? "" : src[i]).trim();
      if (!s) continue;
      var key = s.replace(/[\\/]+$/, "").toLowerCase() || s.toLowerCase();
      if (seen[key]) continue;
      seen[key] = true;
      out.push(s);
    }
    return out;
  }

  // 질문 맨 위의 @cwd 줄들. 워처와 같은 규칙이다: 맨 위의 지시어 줄(@cwd/@session/@model)만 보고, 줄 순서대로 모은다.
  function leadingCwds(text) {
    var out = [];
    var lines = String(text == null ? "" : text).split(/\r?\n/);
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (/^\s*$/.test(line)) continue;
      var m = line.match(/^\ufeff?@cwd:\s*(.+)$/i);
      if (m) { out.push(m[1].trim()); continue; }
      if (/^\ufeff?@(session|model):/i.test(line)) continue;
      break;
    }
    return cwdListOf(out);
  }

  function extractImagesFromText(text) {
    if (!text) return { cwd: "", cwds: [], images: [] };
    // @cwd 는 여러 줄일 수 있다. cwds 가 폴더 목록이고, cwd 는 그 첫 번째다(상대 경로 이미지는 첫 폴더 기준으로 찾는다).
    var cwds = leadingCwds(text);
    if (!cwds.length) {
      // 예전 동작: 맨 위가 아니라 본문 중간에 있는 @cwd 한 줄도 읽는다
      var cwdMatch = text.match(/@cwd:\s*([^\r\n]+)/i);
      if (cwdMatch) cwds = cwdListOf(cwdMatch[1]);
    }
    var cwd = cwds[0] || "";
    var candidates = [];
    var seen = {};

    function add(path) {
      if (!path) return;
      path = path.trim().replace(/^[`"']+|[`"']+$/g, "").trim();
      if (!path) return;
      if (/\.(png|jpe?g|gif|webp|svg|bmp|ico)$/i.test(path)) {
        if (!seen[path]) {
          seen[path] = true;
          candidates.push(path);
        }
      }
    }

    var btRegex = /`([^`\r\n]+\.(?:png|jpe?g|gif|webp|svg|bmp|ico))`\s*/gi;
    var m;
    while ((m = btRegex.exec(text)) !== null) { add(m[1]); }

    var mdRegex = /!?\[[^\]]*\]\(([^)\r\n]+\.(?:png|jpe?g|gif|webp|svg|bmp|ico))\)/gi;
    while ((m = mdRegex.exec(text)) !== null) { add(m[1]); }

    var absRegex = /\b([a-zA-Z]:\\[^\s<>"'`*?|]+\.(?:png|jpe?g|gif|webp|svg|bmp|ico))\b/gi;
    while ((m = absRegex.exec(text)) !== null) { add(m[1]); }

    var relRegex = /(?:^|[\s"'(<])((?:[a-zA-Z0-9_\-\.\uac00-\ud7a3]+\/|[a-zA-Z0-9_\-\.\uac00-\ud7a3]+\\)*[a-zA-Z0-9_\-\.\uac00-\ud7a3]+\.(?:png|jpe?g|gif|webp|svg|bmp|ico))(?=[\s"')>]|$)/gi;
    while ((m = relRegex.exec(text)) !== null) { add(m[1]); }

    return { cwd: cwd, cwds: cwds, images: candidates };
  }

  function createImageGallery(images, cwd) {
    if (!images || images.length === 0) return null;
    var gallery = document.createElement("div");
    gallery.className = "qa-image-gallery";
    gallery.innerHTML = '<div class="qa-image-gallery-title">참조 이미지 ' + images.length + '개 (올려 두면 미리보기, 클릭하면 크게 보기)</div>';

    var grid = document.createElement("div");
    grid.className = "qa-image-gallery-grid";
    var validCount = images.length;

    images.forEach(function (imgPath) {
      var fullUrl = makeImageUrl(imgPath, cwd);
      var card = document.createElement("div");
      card.className = "image-thumb-card";
      card.title = imgPath + "\n(마우스 오버: 확대 / 클릭: 크게 보기)";

      var img = document.createElement("img");
      img.className = "image-thumb-img";
      img.src = fullUrl;
      img.alt = imgPath;
      img.loading = "lazy";

      var label = document.createElement("div");
      label.className = "image-thumb-label";
      label.textContent = imgPath.replace(/^.*[\\\/]/, '');

      card.appendChild(img);
      card.appendChild(label);

      img.onerror = function () {
        card.remove();
        validCount--;
        if (validCount <= 0) {
          gallery.remove();
        } else {
          var titleEl = gallery.querySelector(".qa-image-gallery-title");
          if (titleEl) {
            titleEl.textContent = '참조 이미지 ' + validCount + '개 (올려 두면 미리보기, 클릭하면 크게 보기)';
          }
        }
      };

      card.addEventListener("mouseenter", function (e) { showHoverPopup(e, fullUrl, imgPath); });
      card.addEventListener("mouseleave", hideHoverPopup);
      card.addEventListener("click", function (e) {
        e.preventDefault();
        openLightbox(fullUrl, imgPath);
      });

      grid.appendChild(card);
    });

    gallery.appendChild(grid);
    return gallery;
  }

  // ==========================================================================
  // 마크다운, KaTeX, 구문 강조, Mermaid, GFM 콜아웃 공통 렌더링 헬퍼
  // ==========================================================================
  var mermaidInitialized = false;
  var mermaidCounter = 0;

  // ==========================================================================
  // 화면 테마: 시스템(기본) / 라이트 / 다크. 첫 그리기 전 결정은 index.html 머리의 theme-init 가 맡고, 여기서는 바꾸기만 한다.
  // ==========================================================================
  var THEME_KEY = "samjil-viewer-theme";

  function normalizeThemePref(value) {
    return value === "light" || value === "dark" ? value : "system";
  }

  function resolveTheme(pref, systemLight) {
    var p = normalizeThemePref(pref);
    if (p === "system") { return systemLight ? "light" : "dark"; }
    return p;
  }

  function systemPrefersLight() {
    try { return Boolean(window.matchMedia && window.matchMedia("(prefers-color-scheme: light)").matches); } catch (e) { return false; }
  }

  function applyTheme(pref) {
    var p = normalizeThemePref(pref);
    var theme = resolveTheme(p, systemPrefersLight());
    var root = document.documentElement;
    root.setAttribute("data-theme", theme);
    root.setAttribute("data-theme-pref", p);
    var hd = document.getElementById("hljs-dark");
    var hl = document.getElementById("hljs-light");
    if (hd) { hd.disabled = (theme !== "dark"); }
    if (hl) { hl.disabled = (theme !== "light"); }
    var buttons = document.querySelectorAll("#theme-switch button[data-theme-pref]");
    Array.prototype.forEach.call(buttons, function (b) {
      b.setAttribute("aria-pressed", b.getAttribute("data-theme-pref") === p ? "true" : "false");
    });
    // 다음에 그리는 다이어그램부터 새 테마를 쓰도록 다시 초기화하게 한다
    mermaidInitialized = false;
  }

  function currentThemePref() {
    try { return normalizeThemePref(localStorage.getItem(THEME_KEY)); } catch (e) { return "system"; }
  }

  function setThemePref(pref) {
    var p = normalizeThemePref(pref);
    try {
      if (p === "system") { localStorage.removeItem(THEME_KEY); } else { localStorage.setItem(THEME_KEY, p); }
    } catch (e) {}
    applyTheme(p);
  }

  function initTheme() {
    applyTheme(currentThemePref());
    var group = document.getElementById("theme-switch");
    if (group) {
      group.addEventListener("click", function (ev) {
        var btn = ev.target && ev.target.closest ? ev.target.closest("button[data-theme-pref]") : null;
        if (btn) { setThemePref(btn.getAttribute("data-theme-pref")); }
      });
    }
    // 기기의 밝기 설정이 바뀌면 '시스템'을 고른 경우에만 따라간다
    try {
      var mq = window.matchMedia("(prefers-color-scheme: light)");
      var onChange = function () { if (currentThemePref() === "system") { applyTheme("system"); } };
      if (mq.addEventListener) { mq.addEventListener("change", onChange); } else if (mq.addListener) { mq.addListener(onChange); }
    } catch (e) {}
  }

  function ensureMermaidInit() {
    if (mermaidInitialized) return;
    if (window.mermaid && typeof window.mermaid.initialize === "function") {
      try {
        window.mermaid.initialize({
          startOnLoad: false,
          theme: document.documentElement.getAttribute("data-theme") === "light" ? "default" : "dark",
          securityLevel: "loose",
          fontFamily: "IBM Plex Sans KR, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif"
        });
        mermaidInitialized = true;
      } catch (e) {}
    }
  }

  var ALERT_TYPES = {
    note: {
      label: "Note",
      icon: '<svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor"><path d="M0 8a8 8 0 1 1 16 0A8 8 0 0 1 0 8Zm8-6.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13ZM6.5 7.75A.75.75 0 0 1 7.25 7h1a.75.75 0 0 1 .75.75v2.75h.25a.75.75 0 0 1 0 1.5h-2a.75.75 0 0 1 0-1.5h.25v-2h-.25a.75.75 0 0 1-.75-.75ZM8 6a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"/></svg>'
    },
    tip: {
      label: "Tip",
      icon: '<svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor"><path d="M8 1.5c-2.363 0-4 1.69-4 3.75 0 .984.424 1.625.984 2.304l.214.253c.223.264.47.556.673.848.284.411.537.896.621 1.49a.75.75 0 0 1-1.484.211c-.04-.282-.163-.547-.37-.847a8.456 8.456 0 0 0-.542-.68c-.619-.747-1.346-1.633-1.346-3.279C2.75 2.568 5.12 0 8 0s5.25 2.568 5.25 5.25c0 1.646-.727 2.532-1.346 3.28-.168.202-.35.419-.541.679-.208.3-.332.565-.372.847a.751.751 0 0 1-1.485-.21c.084-.595.338-1.08.621-1.49.204-.292.45-.584.673-.848.075-.088.147-.173.213-.253.561-.679.985-1.32.985-2.304 0-2.06-1.637-3.75-4-3.75ZM5.75 12h4.5a.75.75 0 0 1 0 1.5h-4.5a.75.75 0 0 1 0-1.5Zm1 3h2.5a.75.75 0 0 1 0 1.5h-2.5a.75.75 0 0 1 0-1.5Z"/></svg>'
    },
    important: {
      label: "Important",
      icon: '<svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor"><path d="M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v9.5A1.75 1.75 0 0 1 14.25 13H9.06l-2.573 2.573A1.458 1.458 0 0 1 4 14.543V13H1.75A1.75 1.75 0 0 1 0 11.25Zm1.75-.25a.25.25 0 0 0-.25.25v9.5c0 .138.112.25.25.25h3a.75.75 0 0 1 .75.75v2.19l2.72-2.72a.749.749 0 0 1 .53-.22h5.5a.25.25 0 0 0 .25-.25v-9.5a.25.25 0 0 0-.25-.25Zm6.47 2.97a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5a.75.75 0 0 1 .75-.75Zm0 7.03a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"/></svg>'
    },
    warning: {
      label: "Warning",
      icon: '<svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor"><path d="M6.457 1.047c.659-1.234 2.427-1.234 3.086 0l6.082 11.378A1.75 1.75 0 0 1 14.082 15H1.918a1.75 1.75 0 0 1-1.543-2.575Zm1.763.707a.25.25 0 0 0-.44 0L1.698 13.132a.25.25 0 0 0 .22.368h12.164a.25.25 0 0 0 .22-.368Zm.53 3.996v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 11a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z"/></svg>'
    },
    caution: {
      label: "Caution",
      icon: '<svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor"><path d="M4.47.22A.749.749 0 0 1 5 0h6c.199 0 .389.079.53.22l4.25 4.25c.141.14.22.331.22.53v6c0 .199-.079.389-.22.53l-4.25 4.25a.749.749 0 0 1-.53.22H5a.749.749 0 0 1-.53-.22L.22 11.75A.749.749 0 0 1 0 11.22V5.25c0-.199.079-.389.22-.53Zm.84 1.28L1.5 5.31v5.38l3.81 3.81h5.38l3.81-3.81V5.31L10.69 1.5ZM8 4a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5A.75.75 0 0 1 8 4Zm0 8a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"/></svg>'
    }
  };

  var COPY_ICON_SVG = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>';
  var COPIED_ICON_SVG = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"></polyline></svg>';

  function renderMarkdownWithMath(text) {
    if (!text) return "";
    var hasMarked = window.marked && typeof window.marked.parse === "function";
    if (!hasMarked) return escapeHtml(text);

    var hasKatex = window.katex && typeof window.katex.renderToString === "function";
    var mathList = [];

    // 1. 코드 블록(```...```) 및 인라인 코드(`...`) 임시 보호
    var codeBlocks = [];
    var s = String(text).replace(/(```[\s\S]*?```|`[^`\n]*?`)/g, function (match) {
      var ph = "%%%CBLOCK_" + codeBlocks.length + "%%%";
      codeBlocks.push(match);
      return ph;
    });

    if (hasKatex) {
      // 2. 블록 수식 ($$...$$ 또는 \[...\]) 보호
      s = s.replace(/(?:\$\$([\s\S]*?)\$\$|\\\[([\s\S]*?)\\\])/g, function (match, m1, m2) {
        var math = (m1 || m2 || "").trim();
        var ph = "%%%MATH_B_" + mathList.length + "%%%";
        mathList.push({ type: "block", math: math });
        return "\n\n" + ph + "\n\n";
      });

      // 3. 인라인 수식 ($...$ 또는 \(...\)) 보호
      // 절충: PowerShell 변수($env:..., $PSScriptRoot)나 가격($5 ~ $10), 일반 한글 문장이 수식으로
      // 깨지는 오탐을 막기 위해, $...$ 안에 한글이나 $식별자가 들어 있으면 수식으로 보지 않는다.
      // (수식 안에 한글이 꼭 필요하면 \( \text{정답} \) 또는 $$ 블록 수식을 쓴다.)
      s = s.replace(/(?:(?<!\\|\w)\$(?!\s)([^\$\n]+?)(?<!\s)\$(?![A-Za-z0-9_:])|\\\(([\s\S]*?)\\\))/g, function (match, m1, m2) {
        var math = (m1 || m2 || "").trim();
        if (!math) return match;
        if (m1 && (/[\uAC00-\uD7A3]/.test(math) || /(?:^|\s)\$[A-Za-z_]/.test(math))) {
          return match;
        }
        var ph = "%%%MATH_I_" + mathList.length + "%%%";
        mathList.push({ type: "inline", math: math });
        return ph;
      });
    }

    // 4. 백틱 바깥 일반 텍스트의 '<' 이스케이프 (URL 자동 링크 <http(s)://...> 제외)
    // 백틱 없이 적힌 <!--주석-->, 닫히지 않은 <script ...> 등이 HTML 블록으로 해석되어
    // marked/DOMPurify 에서 뒤쪽 본문 전체가 잘리는 현상을 막는다.
    s = s.replace(/<(?![hH][tT][tT][pP][sS]?:\/\/[^\s<>]+>)/g, "&lt;");

    // 4-1. 단독 '~'(예: 1~5줄, 약 ~10분)가 취소선(~~...~~)이나 아래첨자로 오해석되지 않게 이스케이프한다(~~ / ~~~ 는 보존).
    s = s.replace(/(^|[^~])~(?![~])/g, "$1&#126;");

    // 5. 코드 블록 복원
    codeBlocks.forEach(function (code, i) {
      s = s.replace("%%%CBLOCK_" + i + "%%%", function () { return code; });
    });

    // 6. 마크다운 변환 (질문 지시문 등의 단일 줄바꿈도 줄바꿈으로 유지)
    var html = window.marked.parse(s, { breaks: true });

    // 7. DOMPurify 정제 (수식 플레이스홀더 및 task-list 체크박스 보존)
    if (window.DOMPurify && typeof window.DOMPurify.sanitize === "function") {
      html = window.DOMPurify.sanitize(html, { ADD_TAGS: ["input"], ADD_ATTR: ["type", "checked", "disabled"] });
    }

    if (!hasKatex) return html;

    // 8. KaTeX 수식 HTML 치환
    mathList.forEach(function (item, i) {
      var rendered = "";
      try {
        rendered = window.katex.renderToString(item.math, {
          displayMode: item.type === "block",
          throwOnError: false
        });
      } catch (err) {
        rendered = '<span class="katex-error" title="' + escapeHtml(err.message) + '">' + escapeHtml(item.math) + '</span>';
      }

      var target = item.type === "block" ? "%%%MATH_B_" + i + "%%%" : "%%%MATH_I_" + i + "%%%";
      if (item.type === "block") {
        var pWrapped = new RegExp("<p>\\s*" + target + "\\s*<\\/p>", "g");
        if (pWrapped.test(html)) {
          html = html.replace(pWrapped, function () { return '<div class="katex-display-wrapper">' + rendered + '</div>'; });
        } else {
          html = html.replace(target, function () { return rendered; });
        }
      } else {
        html = html.replace(target, function () { return rendered; });
      }
    });

    return html;
  }

  function postProcessMarkdownElements(container, cwd) {
    if (!container) return;

    ensureMermaidInit();

    // 1. GFM Alerts (> [!NOTE], > [!TIP], > [!IMPORTANT], > [!WARNING], > [!CAUTION])
    var bqs = container.querySelectorAll("blockquote");
    bqs.forEach(function (bq) {
      if (bq.classList.contains("markdown-alert")) return;
      var firstP = bq.querySelector("p");
      if (!firstP) return;
      var rawHtml = firstP.innerHTML;
      var match = rawHtml.match(/^\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\](\s*<br\s*\/?>)?/i);
      if (match) {
        var type = match[1].toLowerCase();
        var alertInfo = ALERT_TYPES[type];
        if (alertInfo) {
          bq.classList.add("markdown-alert", "markdown-alert-" + type);
          var remaining = rawHtml.slice(match[0].length).trim();
          if (remaining) {
            firstP.innerHTML = remaining;
          } else {
            firstP.remove();
          }
          var titleEl = document.createElement("div");
          titleEl.className = "markdown-alert-title";
          titleEl.innerHTML = alertInfo.icon + "<span>" + alertInfo.label + "</span>";
          bq.insertBefore(titleEl, bq.firstChild);
        }
      }
    });

    // 2. Code blocks (Mermaid / Highlight.js / Copy button)
    var pres = container.querySelectorAll("pre");
    pres.forEach(function (pre) {
      if (pre.parentElement && pre.parentElement.classList.contains("code-block-wrapper")) return;
      if (pre.classList.contains("code-handled")) return;

      var code = pre.querySelector("code");
      if (!code) return;

      var lang = "";
      var classNames = code.className ? String(code.className).split(/\s+/) : [];
      for (var i = 0; i < classNames.length; i++) {
        var cls = classNames[i];
        if (cls.indexOf("language-") === 0) {
          lang = cls.replace("language-", "").trim().toLowerCase();
          break;
        }
      }

      // 2-1. Mermaid 다이어그램
      if (lang === "mermaid") {
        pre.classList.add("code-handled");
        var graphCode = (code.textContent || "").trim();
        var mBlock = document.createElement("div");
        mBlock.className = "mermaid-block";
        var mId = "mermaid-svg-" + Date.now() + "-" + (++mermaidCounter);

        if (window.mermaid && typeof window.mermaid.render === "function") {
          try {
            window.mermaid.render(mId, graphCode).then(function (res) {
              mBlock.innerHTML = res.svg;
            }).catch(function (err) {
              mBlock.innerHTML = '<div class="mermaid-error">Mermaid 렌더링 실패: ' + escapeHtml(err.message || String(err)) + '</div>';
            });
          } catch (err) {
            mBlock.innerHTML = '<div class="mermaid-error">Mermaid 에러: ' + escapeHtml(err.message || String(err)) + '</div>';
          }
        } else {
          mBlock.innerHTML = '<pre>' + escapeHtml(graphCode) + '</pre>';
        }

        if (pre.parentNode) {
          pre.parentNode.replaceChild(mBlock, pre);
        }
        return;
      }

      // 2-2. Syntax highlighting (highlight.js)
      if (window.hljs && typeof window.hljs.highlightElement === "function") {
        try {
          window.hljs.highlightElement(code);
        } catch (e) {}
      }

      // 2-3. Code block wrapper + 헤더 + 복사 버튼
      var wrapper = document.createElement("div");
      wrapper.className = "code-block-wrapper";

      var header = document.createElement("div");
      header.className = "code-block-header";

      var langSpan = document.createElement("span");
      langSpan.className = "code-block-lang";
      langSpan.textContent = lang || "CODE";

      var copyBtn = document.createElement("button");
      copyBtn.className = "code-copy-btn";
      copyBtn.type = "button";
      copyBtn.title = "코드 클립보드에 복사";
      copyBtn.innerHTML = COPY_ICON_SVG + "<span>복사</span>";

      copyBtn.addEventListener("click", function (e) {
        e.stopPropagation();
        var codeText = code.innerText || code.textContent || "";
        if (navigator.clipboard && typeof navigator.clipboard.writeText === "function") {
          navigator.clipboard.writeText(codeText).then(function () {
            copyBtn.classList.add("copied");
            copyBtn.innerHTML = COPIED_ICON_SVG + "<span>복사됨!</span>";
            setTimeout(function () {
              copyBtn.classList.remove("copied");
              copyBtn.innerHTML = COPY_ICON_SVG + "<span>복사</span>";
            }, 2000);
          }).catch(function () {
            copyBtn.querySelector("span").textContent = "실패";
          });
        }
      });

      header.appendChild(langSpan);
      header.appendChild(copyBtn);

      if (pre.parentNode) {
        pre.parentNode.insertBefore(wrapper, pre);
        wrapper.appendChild(header);
        wrapper.appendChild(pre);
      }
      pre.classList.add("code-handled");
    });

    // 3. 인라인 이미지 참조 (pre 바깥에 있는 code)
    var inlineCodes = container.querySelectorAll("code");
    inlineCodes.forEach(function (code) {
      if (code.closest("pre")) return;
      var str = (code.textContent || "").trim();
      if (/\.(png|jpe?g|gif|webp|svg|bmp|ico)$/i.test(str)) {
        var imgUrl = makeImageUrl(str, cwd);
        code.classList.add("inline-image-ref");
        code.title = str + " (올려 두면 미리보기, 클릭하면 원본 보기)";
        code.addEventListener("mouseenter", function (e) { showHoverPopup(e, imgUrl, str); });
        code.addEventListener("mouseleave", hideHoverPopup);
        code.addEventListener("click", function (e) {
          e.preventDefault();
          e.stopPropagation();
          openLightbox(imgUrl, str);
        });
      }
    });

    // 4. 테이블 반응형 스크롤 래퍼
    var tables = container.querySelectorAll("table");
    tables.forEach(function (table) {
      if (table.parentElement && table.parentElement.classList.contains("table-wrapper")) return;
      var wrap = document.createElement("div");
      wrap.className = "table-wrapper";
      if (table.parentNode) {
        table.parentNode.insertBefore(wrap, table);
        wrap.appendChild(table);
      }
    });

    // 5. 외부 링크 새 탭 열기
    var links = container.querySelectorAll("a");
    links.forEach(function (link) {
      var href = link.getAttribute("href") || "";
      if (/^https?:\/\//i.test(href)) {
        link.setAttribute("target", "_blank");
        link.setAttribute("rel", "noopener noreferrer");
      }
    });
  }

  function renderBody(container, text, cwd) {
    var canRenderMarkdown = window.marked && typeof window.marked.parse === "function";
    if (canRenderMarkdown) {
      container.classList.add("md");
      container.innerHTML = renderMarkdownWithMath(text || "");
      postProcessMarkdownElements(container, cwd);
    } else {
      var pre = document.createElement("pre");
      pre.textContent = text || "";
      container.appendChild(pre);
    }
  }

  function badge(cls, text) {
    var s = document.createElement("span");
    s.className = "badge " + cls;
    s.textContent = text;
    return s;
  }

  // 색 없는 메타 항목. 색은 상태 배지에만 쓴다.
  // 기록이 antigravity MCP 직접 호출로 남은 것인가(source 필드). 필드가 없는 옛 기록은 bridge 로 본다.
  function viaMcp(r) {
    return Boolean(r) && String(r.source || "").trim().toLowerCase() === "mcp";
  }

  // 기록의 질문·답변이 20000자에서 잘리면 끝에 안내 문구가 붙는다(common.ps1 의 Truncate-Text). 이 문구를 본문에서 떼어 내고
  // 그 자리에 원본 파일을 여는 링크를 보인다(문구가 열린 코드 블록 안에 섞여 코드처럼 보이는 일도 막는다).
  var TRUNCATION_NOTE_RE = /\n?\.\.\. \(내용이 길어 일부 생략됨[^)\r\n]*\)\s*$/;

  function splitTruncationNote(text) {
    var s = text == null ? "" : String(text);
    var m = TRUNCATION_NOTE_RE.exec(s);
    if (!m) return { text: s, truncated: false };
    return { text: s.slice(0, m.index), truncated: true };
  }

  // 원본 파일을 내려 주는 뷰어 API. kind: "question"(processed 의 지시파일) | "answer"(outbox 의 응답 파일)
  function qaSourceUrl(taskId, kind) {
    return "/api/qa/source?task=" + encodeURIComponent(taskId) + "&kind=" + kind;
  }

  // 잘린 글에 붙일 원본 링크 정보. MCP 로 직접 부른 기록은 원본 파일이 런타임 폴더에 없고, 작업 ID 가 없어도 찾을 수 없어 null.
  function qaTruncationLinkOf(r, kind) {
    if (!r || !r.task_id || viaMcp(r)) return null;
    return {
      url: qaSourceUrl(r.task_id, kind),
      label: kind === "question" ? "지시 원본 전체 보기" : "답변 원본 전체 보기",
      hint: (kind === "question" ? "processed 폴더의 지시파일 " + r.task_id : "outbox 폴더의 응답 파일 " + r.task_id + ".response.md") + " - 창에서 렌더링/Raw 로 보기 (Ctrl+클릭: Raw 를 새 탭에서)"
    };
  }

  // ---- 카드에는 일반적인 길이까지만 보인다 ----
  // 기록 145건의 길이를 보면 답변은 중앙값 300자, 상위 25%가 약 1,100자 이상이고 2,000자를 넘는 것은 13%뿐이다. 질문은 더 길어서(상위 25%가 약 2,000자 이상) 3,000자로 둔다.
  // 글자 수와 줄 수 중 먼저 닿는 쪽에서 줄 단위로 자르고, 한도를 조금 넘는 정도(여유)는 접지 않고 다 보인다.
  var QA_PREVIEW_ANSWER_MAX = 2000;
  var QA_PREVIEW_QUESTION_MAX = 3000;
  var QA_PREVIEW_MAX_LINES = 40;
  var QA_PREVIEW_SLACK_CHARS = 400;
  var QA_PREVIEW_SLACK_LINES = 8;

  function qaPreviewLimitOf(kind) {
    return { chars: kind === "question" ? QA_PREVIEW_QUESTION_MAX : QA_PREVIEW_ANSWER_MAX, lines: QA_PREVIEW_MAX_LINES };
  }

  // 반환: { text, cut, shown, total }. 자르면 text 는 앞부분이고, 코드 블록 한가운데서 잘렸으면 블록을 닫아 준다(뒤 글이 코드로 번지지 않게).
  function qaPreviewOf(text, maxChars, maxLines) {
    var s = text == null ? "" : String(text);
    var lines = s.split("\n");
    if (s.length <= maxChars + QA_PREVIEW_SLACK_CHARS && lines.length <= maxLines + QA_PREVIEW_SLACK_LINES) {
      return { text: s, cut: false, shown: s.length, total: s.length };
    }
    var out = [];
    var used = 0;
    for (var i = 0; i < lines.length; i++) {
      if (out.length >= maxLines) { break; }
      if (out.length > 0 && used + lines[i].length > maxChars) { break; }
      out.push(out.length === 0 && lines[i].length > maxChars ? lines[i].slice(0, maxChars) : lines[i]);
      used += lines[i].length + 1;
    }
    // 끝의 빈 줄과 제목 줄(뒤에 올 문단이 잘려 제목만 남는 것)은 뺀다
    while (out.length > 1 && (!out[out.length - 1].trim() || /^\s*#{1,6}\s/.test(out[out.length - 1]))) { out.pop(); }
    var shown = out.join("\n");
    var fences = 0;
    for (var j = 0; j < out.length; j++) { if (/^\s*(```|~~~)/.test(out[j])) { fences++; } }
    return { text: fences % 2 === 1 ? shown + "\n```" : shown, cut: true, shown: shown.length, total: s.length };
  }

  // 원본 창이 보여 줄 "기록에 저장된 글". 5초마다 카드를 다시 그려도 같은 키로 덮어써서 쌓이지 않는다.
  var qaInlineTexts = {};

  // 카드 본문을 그린다. 일반적인 길이를 넘으면 앞부분만 그리고 아래에 "전체 보기" 줄을 붙이며,
  // 기록 자체가 20000자에서 잘려 있으면(끝의 안내 문구) 안내를 떼어 내고 원본 파일을 여는 길을 준다.
  function renderQaText(container, text, cwd, r, kind) {
    var parts = splitTruncationNote(text);
    var lim = qaPreviewLimitOf(kind);
    var pv = qaPreviewOf(parts.text, lim.chars, lim.lines);
    renderBody(container, pv.cut ? pv.text : parts.text, cwd);
    if (!pv.cut && !parts.truncated) return;

    var link = qaTruncationLinkOf(r, kind);
    var key = kind + ":" + String((r && (r.task_id || r.timestamp)) || "");
    qaInlineTexts[key] = parts.text;
    var msgText;
    if (pv.cut && parts.truncated) { msgText = "앞부분 " + pv.shown.toLocaleString() + "자만 보입니다. 기록에도 일부만 저장돼 있습니다."; }
    else if (pv.cut) { msgText = "앞부분 " + pv.shown.toLocaleString() + "자만 보입니다 (전체 " + pv.total.toLocaleString() + "자)."; }
    else { msgText = "내용이 길어 일부만 보입니다."; }
    var canOpen = pv.cut || Boolean(link);
    if (!canOpen) { msgText += " 원본 파일은 이 PC 에 없습니다."; }

    var note = document.createElement("div");
    note.className = "truncation-note";
    var msg = document.createElement("span");
    msg.textContent = msgText;
    note.appendChild(msg);
    if (canOpen) {
      var a;
      if (link) {
        a = document.createElement("a");
        a.href = link.url;                       // 새 탭에서 Raw 로 여는 길(Ctrl+클릭, 가운데 클릭, 자바스크립트가 막힌 경우)
        a.target = "_blank";
        a.rel = "noopener";
        a.textContent = parts.truncated ? link.label : (kind === "question" ? "질문 전체 보기" : "답변 전체 보기");   // 기록이 온전하면 "원본"이 아니라 그냥 전체
        a.title = link.hint;
      } else {
        a = document.createElement("button");    // 원본 파일이 없는 기록(MCP 등)은 기록에 저장된 글을 창에서 보여 준다
        a.type = "button";
        a.textContent = kind === "question" ? "질문 전체 보기" : "답변 전체 보기";
        a.title = "기록에 저장된 전체 내용을 창에서 보기";
      }
      a.className = "src-open";
      a.setAttribute("data-src-task", link ? String(r.task_id) : "");
      a.setAttribute("data-src-kind", kind);
      a.setAttribute("data-src-cwd", cwd || "");
      a.setAttribute("data-src-key", key);
      a.setAttribute("data-src-file", parts.truncated && link ? "1" : "0");   // 기록이 잘려 있어야만 원본 파일이 필요하다
      note.appendChild(a);
    }
    container.parentNode ? container.parentNode.insertBefore(note, container.nextSibling) : container.appendChild(note);
  }

  // ---- 원본 창: 길어서 잘린 질문·답변의 전체 원본을 답변과 같은 스타일로 보고, Raw 로 진짜 원본 텍스트도 본다 ----
  // 렌더링이 이 글자 수를 넘는 파일에서는 브라우저가 오래 멈출 수 있어, 그런 파일은 기본을 Raw 로 연다(토글로 렌더링도 가능).
  var QA_SOURCE_RENDER_MAX = 400000;

  function qaSourceDefaultView(len) {
    return (typeof len === "number" && len > QA_SOURCE_RENDER_MAX) ? "raw" : "rendered";
  }

  // 원본 파일을 보면 "지시 원본/답변 원본", 기록에 저장된 글을 보면 "질문 전체/답변 전체"
  function qaSourceTitle(kind, fromRecord) {
    if (fromRecord) { return kind === "question" ? "질문 전체" : "답변 전체"; }
    return kind === "question" ? "지시 원본" : "답변 원본";
  }

  var srcDlgState = null;   // { task, kind, cwd, text, view, error }
  var srcDlgCache = {};     // url -> 받아 둔 원본 글(토글할 때 다시 받지 않는다)

  function ensureSourceDialog() {
    var dlg = document.getElementById("source-dialog");
    if (dlg) return dlg;
    dlg = document.createElement("dialog");
    dlg.id = "source-dialog";
    dlg.setAttribute("aria-labelledby", "source-dialog-title");
    dlg.innerHTML = [
      '<div class="proc-dlg">',
      '  <header class="proc-dlg-head">',
      '    <div class="proc-dlg-heading">',
      '      <h2 id="source-dialog-title" class="proc-dlg-title">원본</h2>',
      '      <span class="proc-dlg-task"></span>',
      '    </div>',
      '    <button type="button" class="proc-dlg-close" title="닫기 (Esc)">닫기</button>',
      '  </header>',
      '  <div class="src-dlg-tools">',
      '    <div class="src-toggle" role="group" aria-label="보기 방식">',
      '      <button type="button" data-view="rendered" aria-pressed="true">렌더링</button>',
      '      <button type="button" data-view="raw" aria-pressed="false">Raw</button>',
      '    </div>',
      '    <button type="button" class="src-copy" title="원본 텍스트를 그대로 복사">Raw 복사</button>',
      '    <a class="src-newtab" target="_blank" rel="noopener" title="원본 텍스트를 새 탭에서 열기">새 탭에서 Raw</a>',
      '    <span class="src-info" aria-live="polite"></span>',
      '  </div>',
      '  <div class="proc-dlg-body src-dlg-body"></div>',
      '</div>'
    ].join("");
    dlg.addEventListener("click", function (e) {
      if (e.target === dlg || (e.target.classList && e.target.classList.contains("proc-dlg-close"))) { dlg.close(); return; }
      var tb = e.target.closest ? e.target.closest(".src-toggle button") : null;
      if (tb && srcDlgState) { srcDlgState.view = tb.getAttribute("data-view"); renderSourceDialog(); return; }
      var cp = e.target.closest ? e.target.closest(".src-copy") : null;
      if (cp && srcDlgState && srcDlgState.text != null) {
        var done = function (ok) { cp.textContent = ok ? "복사했습니다" : "복사하지 못했습니다"; setTimeout(function () { cp.textContent = "Raw 복사"; }, 1500); };
        if (navigator.clipboard && navigator.clipboard.writeText) { navigator.clipboard.writeText(srcDlgState.text).then(function () { done(true); }, function () { done(false); }); }
        else { done(false); }
      }
    });
    dlg.addEventListener("close", function () { srcDlgState = null; });
    document.body.appendChild(dlg);
    return dlg;
  }

  function renderSourceDialog() {
    var dlg = document.getElementById("source-dialog");
    if (!dlg || !srcDlgState) return;
    var s = srcDlgState;
    dlg.querySelector(".proc-dlg-title").textContent = qaSourceTitle(s.kind, s.fromRecord);
    dlg.querySelector(".proc-dlg-task").textContent = s.task || "";
    var newTab = dlg.querySelector(".src-newtab");
    if (s.task) { newTab.setAttribute("href", qaSourceUrl(s.task, s.kind)); newTab.hidden = false; } else { newTab.removeAttribute("href"); newTab.hidden = true; }
    var body = dlg.querySelector(".src-dlg-body");
    var info = dlg.querySelector(".src-info");
    var btns = dlg.querySelectorAll(".src-toggle button");
    for (var i = 0; i < btns.length; i++) { btns[i].setAttribute("aria-pressed", btns[i].getAttribute("data-view") === s.view ? "true" : "false"); }
    body.innerHTML = "";
    if (s.error) {
      info.textContent = "";
      var err = document.createElement("p");
      err.className = "empty";
      err.textContent = s.error;
      body.appendChild(err);
      return;
    }
    if (s.text == null) {
      info.textContent = "불러오는 중...";
      var wait = document.createElement("p");
      wait.className = "empty";
      wait.textContent = "원본을 불러오는 중입니다...";
      body.appendChild(wait);
      return;
    }
    info.textContent = s.text.length.toLocaleString() + "자" + (s.view === "raw" && s.text.length > QA_SOURCE_RENDER_MAX ? " · 매우 커서 Raw 로 열었습니다(렌더링은 느릴 수 있음)" : "");
    if (s.notice) {
      var nt = document.createElement("p");
      nt.className = "src-notice";
      nt.textContent = s.notice;
      body.appendChild(nt);
    }
    if (s.view === "raw") {
      var pre = document.createElement("pre");
      pre.className = "src-raw";
      pre.textContent = s.text;
      body.appendChild(pre);
    } else {
      var content = document.createElement("div");
      content.className = "qa-content";
      body.appendChild(content);
      renderBody(content, s.text, s.cwd || "");
    }
    body.scrollTop = 0;
  }

  // o: { task, kind, cwd, key, useFile }. useFile 이면 원본 파일을 받아 보여 주고(기록이 잘려 있는 경우), 파일이 없으면 기록에 저장된 글로 대신한다.
  // 아니면 기록에 저장된 글(qaInlineTexts[key])을 그대로 보여 준다.
  function openSourceDialog(o) {
    var dlg = ensureSourceDialog();
    var inline = Object.prototype.hasOwnProperty.call(qaInlineTexts, o.key) ? qaInlineTexts[o.key] : null;
    var wantFile = Boolean(o.useFile && o.task);
    var url = wantFile ? qaSourceUrl(o.task, o.kind) : "";
    var st = { task: o.task || "", kind: o.kind, cwd: o.cwd || "", text: null, view: "rendered", error: "", notice: "", fromRecord: !wantFile };
    srcDlgState = st;
    if (!wantFile) {
      if (inline == null) { st.error = "기록에 저장된 내용을 찾을 수 없습니다."; }
      else { st.text = inline; st.view = qaSourceDefaultView(inline.length); }
    } else if (srcDlgCache[url] != null) {
      st.text = srcDlgCache[url]; st.view = qaSourceDefaultView(st.text.length);
    }
    renderSourceDialog();
    if (!dlg.open) dlg.showModal();
    if (!wantFile || st.text != null || st.error) return;
    var fallback = function (why) {
      if (srcDlgState !== st) return;   // 그 사이 닫았거나 다른 창을 열었다
      if (inline != null) {
        st.fromRecord = true; st.text = inline; st.view = qaSourceDefaultView(inline.length);
        st.notice = why + " 기록에 저장된 내용(" + inline.length.toLocaleString() + "자)을 보여 줍니다. 끝이 잘려 있을 수 있습니다.";
      } else { st.error = why; }
      renderSourceDialog();
    };
    fetch(url, { cache: "no-store" }).then(function (res) {
      return res.text().then(function (t) { return { ok: res.ok, status: res.status, text: t }; });
    }).then(function (r) {
      if (srcDlgState !== st) return;
      if (!r.ok) { fallback(r.status === 404 ? "원본 파일을 찾을 수 없습니다(이미 정리됐을 수 있습니다)." : "원본을 불러오지 못했습니다 (" + r.status + ")."); return; }
      srcDlgCache[url] = r.text; st.text = r.text; st.view = qaSourceDefaultView(r.text.length);
      renderSourceDialog();
    }).catch(function (e) {
      fallback("원본을 불러오지 못했습니다: " + (e && e.message ? e.message : e) + ".");
    });
  }

  // 이름 + 값 항목: 이름은 흐리게, 값은 진하게(맨 윗줄·토큰·시간·식별 줄이 같은 모양). 값 칸은 .mv 이다(1초마다 갱신하는 항목은 여기를 고친다).
  // 위임 기록의 접수(프롬프트 입력) 시각 글자("2026-11-09 19:32:22", 이 PC 시간대). 작업 ID(claude_<접수 시각 epoch>_N)에서 구하고, 없거나 값이 말이 안 되면 "".
  function submitTimeText(r) {
    var m = r && r.task_id ? /^claude_(\d{9,11})_\d+/.exec(String(r.task_id)) : null;
    if (!m) { return ""; }
    var d = new Date(Number(m[1]) * 1000);
    if (isNaN(d.getTime())) { return ""; }
    return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate()) + " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds());
  }

  function labeledMeta(label, value, cls, title) {
    var s = document.createElement("span");
    s.className = "meta-item lv" + (cls ? " " + cls : "");
    if (title) s.title = title;
    var l = document.createElement("span"); l.className = "ml"; l.textContent = label;
    var v = document.createElement("span"); v.className = "mv"; v.textContent = value;
    s.appendChild(l); s.appendChild(v);
    return s;
  }
  // 줄 머리말(실행 / 토큰 / 시간 / 식별): 네 줄의 내용이 같은 자리에서 시작하게 폭을 맞춘다
  function metaHead(text) {
    var s = document.createElement("span");
    s.className = "meta-head";
    s.textContent = text;
    return s;
  }

  function metaItem(text, cls, title) {
    var s = document.createElement("span");
    s.className = "meta-item" + (cls ? " " + cls : "");
    s.textContent = text;
    if (title) s.title = title;
    return s;
  }

  function metaExpandKey(dataKey, taskId) {
    return taskId ? String(taskId) : String(dataKey || "");
  }

  function buildModelRow(agyModel, claudeModel, claudeEffort, fellBack, subAgent, triedModels, isOk, models, srcInfo) {
    if (!agyModel && !claudeModel && !(subAgent && subAgent.model) && !(srcInfo && (srcInfo.model || srcInfo.client))) return null;
    var row = document.createElement("div");
    row.className = "meta model-meta";
    row.appendChild(metaHead("모델"));
    row.appendChild(buildCardModelMeta(agyModel, claudeModel, claudeEffort, fellBack, subAgent, triedModels, isOk, models, srcInfo));
    return row;
  }

  function syncMetaToggle(btn, open) {
    var label = open ? "식별 숨기기" : "식별 보기";
    btn.setAttribute("aria-expanded", open ? "true" : "false");
    btn.title = label;
    btn.setAttribute("aria-label", label);
  }

  // 식별 줄을 접이식 묶음(.meta-more)으로 감싸 카드에 붙이고, 실행 줄에 넣을 펼침 버튼을 돌려준다.
  function attachMetaMore(card, dataKey, taskId, rows) {
    var more = document.createElement("div");
    more.className = "meta-more";
    var moreId = "meta-more-" + (++metaMoreSeq);
    more.id = moreId;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]) more.appendChild(rows[i]);
    }
    var expandKey = metaExpandKey(dataKey, taskId);
    var isOpen = Boolean(expandedMeta[expandKey]);
    more.hidden = !isOpen;
    card.appendChild(more);

    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "meta-toggle";
    btn.setAttribute("aria-controls", moreId);
    btn.innerHTML = '<svg class="meta-toggle-chevron" width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4.5 2.5L8 6l-3.5 3.5"/></svg>';
    syncMetaToggle(btn, isOpen);
    btn.onclick = function () {
      var next = more.hidden;
      more.hidden = !next;
      if (next) { expandedMeta[expandKey] = true; }
      else { delete expandedMeta[expandKey]; }
      syncMetaToggle(btn, next);
    };
    return btn;
  }

  // 위임 카드에는 토큰 줄을 두지 않는다(토큰은 실측 통계의 질문 기록에서 본다). 서버가 대화 기록에서 계산해 주는 실제 실행 모델별 값만 모델 줄에 쓴다(받은 뒤에 채운다).
  var recordContexts = {};        // "<대화 id>|<마지막 단계 번호>" -> { cache, context, models }
  var recordContextRequested = {};
  var windowLimits = null;        // { claude:{five_hour,seven_day}, gemini:{five_hour,weekly} }

  function recordLastStep(r) {
    var steps = r && Array.isArray(r.process) ? r.process : [];
    var max = 0;
    steps.forEach(function (st) { var n = Number(st && st.n); if (!isNaN(n) && n > max) { max = n; } });
    // 과정의 마지막 단계는 마지막 도구 호출이다. 그 결과(+1) 다음의 최종 응답 턴(+2)까지가 이 호출의 몫이다(위임 기록의 입력·출력 합과 같아진다).
    return max > 0 ? max + 2 : 0;
  }
  function recordContextKey(r) { return r && r.session_id ? String(r.session_id) + "|" + recordLastStep(r) : ""; }

  // 진행 중(대기 · 실행) 위임의 토큰 블록용 임시 기록. agy 는 진행 정보(progress.tokens), Claude 는 pending 의 claude_usage 를 쓴다.
  // 값은 "지금까지" 이므로 _live 표시를 달아 title 에 알린다.
  function pendingTokenRecord(p) {
    var tk = p && p.progress && p.progress.tokens;
    var rec = { task_id: p && p.task_id, model: p && p.model, claude_usage: p && p.claude_usage, _live: true };
    if (tk && Number(tk.total) > 0) {
      rec.total_tokens = Number(tk.total);
      rec.input_tokens = Number(tk.input) || 0;
      rec.output_tokens = Number(tk.output) || 0;
      rec.thinking_tokens = Number(tk.thinking) || 0;
      rec._liveCtx = {
        cache: Number(tk.cache) || 0,
        context: Number(tk.context) || 0,
        models: Array.isArray(tk.models) ? tk.models : []
      };
    }
    return rec;
  }

  // 끝난 위임의 캐시 읽기·현재 컨텍스트·실제 실행 모델별 토큰을 서버(/api/qa/contexts)에 묻는다. 받으면 화면의 토큰 줄과 모델 줄을 다시 채운다.
  function requestRecordContexts(records) {
    var items = [];
    (Array.isArray(records) ? records : []).forEach(function (r) {
      if (!r || !r.session_id || !Number(r.total_tokens)) { return; }
      var key = recordContextKey(r);
      if (!key || recordContexts[key] || recordContextRequested[key]) { return; }
      recordContextRequested[key] = true;
      items.push({ id: String(r.session_id), max: recordLastStep(r), task_id: r.task_id ? String(r.task_id) : "" });
    });
    if (items.length === 0 || typeof fetch !== "function") { return Promise.resolve(false); }
    var chunks = [];
    for (var i = 0; i < items.length; i += 200) { chunks.push(items.slice(i, i + 200)); }
    return Promise.all(chunks.map(function (chunk) {
      return fetch("/api/qa/contexts", { method: "POST", headers: { "X-Samjil-Viewer": "1", "Content-Type": "application/json" }, body: JSON.stringify({ items: chunk }) })
        .then(function (res) { return res.ok ? res.json() : null; })
        .then(function (data) {
          var got = data && data.results ? data.results : {};
          chunk.forEach(function (it) {
            var key = it.id + "|" + it.max;
            if (got[key]) {
              recordContexts[key] = {
                cache: Number(got[key].cache) || 0,
                context: Number(got[key].context) || 0,
                models: Array.isArray(got[key].models) ? got[key].models : []
              };
            }
          });
          return true;
        })
        .catch(function () { chunk.forEach(function (it) { recordContextRequested[it.id + "|" + it.max] = false; }); return false; });
    })).then(function (rs) { return rs.some(Boolean); });
  }

  function refreshModelMetas() {
    var byKey = {};
    allItems.forEach(function (r) { byKey[tokenRecordKey(r)] = r; });
    var mNodes = document.querySelectorAll(".model-meta[data-model-task]");
    for (var j = 0; j < mNodes.length; j++) {
      var mr = byKey[mNodes[j].getAttribute("data-model-task")];
      if (!mr) continue;
      var mv = mNodes[j].querySelector(".mv");
      if (!mv) continue;
      var mCtx = (mr._liveCtx) || recordContexts[recordContextKey(mr)] || null;
      var mName = recordModel(mr) || null;
      var mAgent = mr.agent_model ? { model: mr.agent_model, effort: mr.agent_effort, type: mr.agent_type, desc: mr.agent_desc } : null;
      var mSrc = (mr.src_model || mr.src_client) ? { model: mr.src_model || "", effort: mr.src_effort || "", client: mr.src_client || "" } : null;
      var mOk = isOkStatus(mr.status);
      mv.innerHTML = cardModelHtml(mName, mr.claude_model, mr.claude_effort, false, mAgent, mr.tried_models, mOk, mCtx && mCtx.models, mSrc);
    }
  }

  // 세션 이름과, 클릭하면 전체 세션 ID를 복사하는 짧은 ID
  // taskId 를 주면 세션 이름 앞에 작업 번호를 둔다(맨 윗줄이 길어져 두 줄로 넘어가지 않게 세션 줄로 옮긴 것).
  function buildSessionMeta(sessionName, sessionId, taskId) {
    var sMeta = document.createElement("div");
    sMeta.className = "meta session-meta";
    sMeta.appendChild(metaHead("식별"));
    if (taskId) { sMeta.appendChild(labeledMeta("작업", taskId, "mono", "작업 ID")); }
    sMeta.appendChild(sessionName ? labeledMeta("세션", sessionName) : labeledMeta("세션", "없음(단발)", "dim", "@session 없이 보낸 단발성 위임입니다"));
    if (sessionId) {
      var sid = String(sessionId);
      var label = (sid.length > 8 ? sid.substring(0, 8) : sid);
      var sidEl = labeledMeta("ID", label, "mono copyable", "세션 ID " + sid + " (클릭하면 복사)");
      var sidVal = sidEl.querySelector(".mv");
      makeActivatable(sidEl, "세션 ID 복사");
      sidEl.onclick = function () {
        if (navigator.clipboard) {
          navigator.clipboard.writeText(sid).then(function () {
            sidVal.textContent = "복사했습니다";
            setTimeout(function () { sidVal.textContent = label; }, 1200);
          });
        }
      };
      sMeta.appendChild(sidEl);
    }
    return sMeta;
  }

  // 미리보기용으로 마크다운 "표시"를 걷어 낸다. 글자로 쓰인 _ * ~ 는 지우지 않는다:
  //   merge_intervals, __init__.py, ~/.samjil, src/*.ts, 2 * 3 은 그대로 남기고,
  //   **굵게**, *기울임*, _기울임_, ~~취소~~ 처럼 짝이 맞는 강조 표시만 벗긴다.
  // (예전에는 [*_`~] 를 전부 지워서 merge_intervals 가 mergeintervals 로, ~/.samjil 이 /.samjil 로 보였다.)
  function stripEmphasis(s) {
    return s
      .replace(/(^|[\s(\["'])\*\*(?=\S)([\s\S]*?\S)\*\*/g, "$1$2")
      .replace(/(^|[\s(\["'])\*(?=\S)([^*\n]*?\S)\*/g, "$1$2")
      .replace(/(^|[\s(\["'])~~(?=\S)([\s\S]*?\S)~~/g, "$1$2")
      // _기울임_ 은 단어 사이의 밑줄(snake_case)이 아닐 때만. __init__ 같은 이중 밑줄은 식별자로 보고 둔다.
      .replace(/(^|[^A-Za-z0-9_가-힣])_(?=\S)([^_\n]*?\S)_(?![A-Za-z0-9_가-힣])/g, "$1$2");
  }

  function cleanTextForPreview(str) {
    if (!str) return "";
    // `인라인 코드` 안은 마크다운이 아니므로 그대로 두고(백틱만 벗김), 바깥만 강조 표시를 벗긴다.
    var parts = String(str).replace(/^#+\s*/, "").split(/(`+[^`]*`+)/);
    for (var i = 0; i < parts.length; i++) {
      parts[i] = (i % 2 === 1) ? parts[i].replace(/^`+|`+$/g, "") : stripEmphasis(parts[i]);
    }
    return parts.join("")
      .replace(/`/g, "")
      .replace(/\[(.*?)\]\(.*?\)/g, "$1")
      .replace(/<[^>]*>/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  }

  function extractQuestionKeyword(text) {
    if (!text) return "";
    var lines = String(text).split("\n");
    var valid = [];

    for (var i = 0; i < lines.length; i++) {
      var t = lines[i].trim();
      if (!t) continue;
      // 워처 지시어 줄(@cwd / @session / @model)은 질문 내용이 아니다
      if (/^\ufeff?@(cwd|session|model):/i.test(t)) continue;
      if (t.indexOf("**읽기") === 0 || t.indexOf("**[읽기") === 0 || t.indexOf("<!--") === 0) continue;
      if (t.indexOf("```") === 0) continue;
      if (t.indexOf("|") === 0 && t.lastIndexOf("|") === t.length - 1) continue;

      var cleaned = cleanTextForPreview(t);
      if (cleaned) {
        valid.push(cleaned);
        if (valid.join(" ").length >= 60 || valid.length >= 2) break;
      }
    }

    if (valid.length > 0) return valid.join(" ");

    for (var j = 0; j < lines.length; j++) {
      var lt = lines[j].trim();
      if (lt.indexOf("|") === 0 && lt.lastIndexOf("|") === lt.length - 1) {
        var cols = lt.split("|").map(function (c) { return cleanTextForPreview(c); }).filter(Boolean);
        if (cols.length > 0 && cols[0] !== "항목" && cols[0].indexOf("---") === -1) {
          return cols[0];
        }
      }
    }

    return cleanTextForPreview(text).substring(0, 100);
  }

  function extractAnswerKeyword(text) {
    if (!text) return "";
    var lines = String(text).split("\n");
    var tableRows = [];
    for (var i = 0; i < lines.length; i++) {
      var t = lines[i].trim();
      if (t.indexOf("|") === 0 && t.lastIndexOf("|") === t.length - 1) {
        var cols = t.split("|").map(function (c) { return cleanTextForPreview(c); }).filter(Boolean);
        if (cols.length >= 2 && cols[0] !== "항목" && cols[0] !== "구분" && cols[0].indexOf("---") === -1) {
          var key = cols[0];
          var val = cols[1];
          if (key && val) tableRows.push(key + ": " + val);
        }
      }
    }
    if (tableRows.length > 0) return tableRows.slice(0, 2).join(" · ");

    var valid = [];
    for (var j = 0; j < lines.length; j++) {
      var lt = lines[j].trim();
      if (!lt || lt.indexOf("```") === 0 || lt.indexOf("---") === 0 || lt.indexOf("===") === 0 || lt.indexOf("<!--") === 0) continue;
      var cleaned = cleanTextForPreview(lt);
      if (cleaned) {
        valid.push(cleaned);
        if (valid.join(" ").length >= 60 || valid.length >= 2) break;
      }
    }
    if (valid.length > 0) return valid.join(" ");
    return cleanTextForPreview(text).substring(0, 100);
  }

  // ==========================================================================
  // 과정: agy 가 질문과 답변 사이에 한 일(부른 도구 목록). 기록(r.process)에서 읽고,
  // 기록에 없는 옛 위임은 펼칠 때 agy 대화 기록에서 읽어 온다(/api/delegate/process).
  // ==========================================================================

  // 한 줄 요약. 예) 도구 호출 23번 · 명령 실행 9 · 파일 읽기 6 · 파일 쓰기 3 외 1종
  function summarizeProcess(steps, live) {
    if (!steps || !steps.length) return live ? "아직 도구를 부르지 않았습니다" : "도구를 쓰지 않고 바로 답했습니다";
    var counts = {}, order = [];
    var totalCalls = 0;
    steps.forEach(function (st) {
      if (st && st.skipped) {
        totalCalls += Number(st.skipped) || 0;
        return;
      }
      totalCalls++;
      var k = progressToolLabel(st.tool) || "기타";
      if (!Object.prototype.hasOwnProperty.call(counts, k)) { counts[k] = 0; order.push(k); }
      counts[k]++;
    });
    order.sort(function (x, y) { return counts[y] - counts[x]; });
    var parts = order.slice(0, 3).map(function (k) { return k + " " + counts[k]; });
    return "도구 호출 " + totalCalls + "번 · " + parts.join(" · ") + (order.length > 3 ? " 외 " + (order.length - 3) + "종" : "");
  }

  // 작업 폴더(@cwd) 아래 경로는 폴더 이름을 빼고 보인다. 예) C:\workpp\src.py -> src.py (폴더 자체는 ".")
  // 폴더가 여러 개면 어느 폴더의 파일인지 알 수 있게 폴더 이름부터 보인다. 예) 폴더 C:\a\repo, D:\b\docs -> repo\src.py, docs\x.md (폴더 자체는 "repo")
  // 명령 안에 적힌 경로도 같은 규칙이다. work2 처럼 이름만 비슷한 폴더는 건드리지 않는다. 전체 경로는 마우스를 올리면 보인다.
  // cwd 는 폴더 문자열 하나나 폴더 배열이다.
  function shortenPathsForCwd(text, cwd) {
    var src = String(text == null ? "" : text);
    var bases = cwdListOf(cwd).map(function (c) { return c.replace(/[\\/]+$/, ""); }).filter(Boolean);
    if (!src || !bases.length) return src;
    var multi = bases.length > 1;
    // 한 폴더가 다른 폴더 안에 있으면 더 구체적인(긴) 폴더 기준으로 먼저 줄인다
    bases.sort(function (a, b) { return b.length - a.length; });
    var out = src;
    bases.forEach(function (base) {
      var esc = base.replace(/[.*+?^${}()|[\]\\\/]/g, function (ch) { return (ch === "\\" || ch === "/") ? "[\\\\/]" : "\\" + ch; });
      var re = new RegExp("(^|[\\s\"'(=])" + esc + "([\\\\/]+|(?=$|[\\s\"')]))", "gi");
      var name = multi ? base.split(/[\\/]/).pop() : "";
      out = out.replace(re, function (m, pre, sep) {
        if (!sep) return pre + (name || ".");
        return pre + (name ? name + sep : "");
      });
    });
    return out === "" ? "." : out;
  }

  // agy 가 그 단계에서 적은 말. say 는 도구를 부르며 알린 진행 설명, think 는 agy 의 생각(영어 원문)이다.
  // 클래스 접두어는 과정 목록 "proc", 진행 중 카드 "pg". 둘 다 없으면 빈 글.
  function buildNarrationHtml(prefix, say, think) {
    var out = "";
    if (say) out += '<span class="' + prefix + '-say"><b>설명</b> ' + escapeHtml(say) + '</span>';
    if (think) out += '<span class="' + prefix + '-think"><b>생각</b> ' + escapeHtml(think) + '</span>';
    return out;
  }

  function manageTaskActionLabel(action) {
    if (!action) return "";
    var act = String(action).trim().toLowerCase();
    if (act === "status") return "상태 확인";
    if (act === "kill" || act === "stop") return "중단";
    return String(action).trim();
  }

  function manageTaskStateLabel(state) {
    if (!state) return "";
    var st = String(state).trim().toUpperCase();
    if (st === "RUNNING") return "실행 중";
    if (st === "DONE") return "완료";
    if (st === "ERROR") return "실패";
    if (st === "CANCELLED") return "중단";
    return String(state).trim();
  }

  function findTaskCommand(steps, taskNo) {
    if (!Array.isArray(steps) || taskNo == null) return "";
    var tNo = Number(taskNo);
    var maxN = !isNaN(tNo) ? tNo - 1 : Infinity;
    var best = null;
    for (var i = 0; i < steps.length; i++) {
      var s = steps[i];
      if (!s) continue;
      var n = Number(s.n);
      if (s.tool === "run_command" || s.bg) {
        if (isNaN(n) || n <= maxN) {
          if (!best || (n >= Number(best.n))) {
            best = s;
          }
        }
      }
    }
    if (best && best.detail) {
      var d = String(best.detail).trim();
      return d.length > 100 ? d.substring(0, 100) : d;
    }
    return "";
  }

  function finishProcessGroup(grp, steps) {
    var actLabel = manageTaskActionLabel(grp.action) || "상태 확인";
    var taskNoStr = grp.task_no != null ? "#" + grp.task_no : "";
    var cmd = findTaskCommand(steps, grp.task_no);

    var stateText = "";
    if (grp.firstState && grp.lastState) {
      if (grp.firstState === grp.lastState) {
        stateText = manageTaskStateLabel(grp.firstState);
      } else {
        stateText = manageTaskStateLabel(grp.firstState) + " → " + manageTaskStateLabel(grp.lastState);
      }
    } else if (grp.lastState || grp.firstState) {
      stateText = manageTaskStateLabel(grp.lastState || grp.firstState);
    }

    var textParts = [];
    if (grp.count > 1) {
      textParts.push(actLabel + " ×" + grp.count + "회");
      if (grp.firstAt && grp.lastAt) {
        textParts.push(grp.firstAt === grp.lastAt ? grp.firstAt : (grp.firstAt + "~" + grp.lastAt));
      } else if (grp.firstAt) {
        textParts.push(grp.firstAt);
      }
    } else {
      textParts.push(actLabel);
    }

    if (stateText) {
      textParts.push(stateText);
    }

    var targetStr = (taskNoStr + (cmd ? " " + cmd : "")).trim();
    if (targetStr) {
      textParts.push(targetStr);
    }

    var detailText = textParts.join(" · ");
    var tip = [];
    if (grp.count > 1) {
      tip.push("첫 시각: " + (grp.firstAt || "—") + ", 끝 시각: " + (grp.lastAt || "—") + " (총 " + grp.count + "회)");
    } else {
      tip.push("도구: manage_task");
      tip.push("대상: " + actLabel + " " + taskNoStr);
    }
    if (cmd) {
      tip.push("명령: " + cmd);
    }

    var base = grp.origStep || {};
    return {
      n: grp.n != null ? grp.n : base.n,
      at: grp.firstAt || base.at,
      tool: "manage_task",
      detail: detailText,
      label: base.label || "",
      think: base.think || "",
      say: base.say || "",
      _isGrouped: true,
      _groupedTip: tip.join("\n")
    };
  }

  function groupProcessSteps(steps) {
    if (!Array.isArray(steps)) return [];
    var result = [];
    var currentGroup = null;

    for (var i = 0; i < steps.length; i++) {
      var st = steps[i];
      if (!st) continue;

      if (st.tool === "manage_task") {
        var action = "";
        var taskNo = st.task_no != null ? st.task_no : null;
        if (taskNo == null && st.detail) {
          var m = String(st.detail).match(/#?(\d+)/);
          if (m) taskNo = parseInt(m[1], 10);
        }
        var mAct = String(st.detail || "").match(/^([^\s#]+)/);
        if (mAct) action = mAct[1];

        if (currentGroup && currentGroup.tool === "manage_task" &&
            currentGroup.task_no === taskNo &&
            currentGroup.action === action) {
          currentGroup.count++;
          currentGroup.lastAt = st.at || currentGroup.lastAt;
          if (st.state) {
            currentGroup.lastState = st.state;
          }
          continue;
        } else {
          if (currentGroup) {
            result.push(finishProcessGroup(currentGroup, steps));
          }
          currentGroup = {
            tool: "manage_task",
            task_no: taskNo,
            action: action,
            count: 1,
            firstAt: st.at || "",
            lastAt: st.at || "",
            firstState: st.state || "",
            lastState: st.state || "",
            n: st.n,
            origStep: st
          };
          continue;
        }
      }

      if (currentGroup) {
        result.push(finishProcessGroup(currentGroup, steps));
        currentGroup = null;
      }
      result.push(st);
    }

    if (currentGroup) {
      result.push(finishProcessGroup(currentGroup, steps));
    }

    return result;
  }

  // 과정 창의 read_file / view_file 단계에 "읽은 범위 · 종류 · 이후 활동" 설명 문구를 만든다 (순수 함수)
  function describeReadStep(step, steps, index) {
    if (!step || (step.tool !== "read_file" && step.tool !== "view_file")) return "";
    var rawPath = "";
    if (step.path) {
      rawPath = String(step.path).trim();
    } else if (step.detail) {
      rawPath = String(step.detail).trim();
    }
    rawPath = rawPath.replace(/\s*\(\d+~\d+행\)\s*$/, "").trim();

    var rangeStr = "";
    if (step.range) {
      var r = step.range;
      var from = r.from != null ? Number(r.from) : null;
      var to = r.to != null ? Number(r.to) : null;
      var total = r.total != null ? Number(r.total) : null;
      if (from === 1 && to != null && total != null && to === total) {
        rangeStr = "전체 " + total + "줄";
      } else if (from != null && to != null) {
        if (total != null) {
          rangeStr = from + "~" + to + "행 / 전체 " + total + "줄";
        } else {
          rangeStr = from + "~" + to + "행";
        }
      } else if (total != null) {
        rangeStr = "전체 " + total + "줄";
      }
    }

    var kindStr = "파일";
    if (rawPath) {
      var normP = rawPath.replace(/\\/g, "/");
      if (/(?:^|\/)tests\//i.test(normP)) {
        kindStr = "시험 파일";
      } else if (/(?:^|\/)SKILL\.md$/i.test(normP) || /\.md$/i.test(normP)) {
        kindStr = "문서";
      } else if (/\.ps1$/i.test(normP)) {
        kindStr = "PowerShell 스크립트";
      } else if (/\.js$/i.test(normP)) {
        kindStr = "자바스크립트";
      } else if (/\.(?:css|html)$/i.test(normP)) {
        kindStr = "화면 파일";
      } else if (/\.json$/i.test(normP)) {
        kindStr = "설정·데이터";
      }
    }

    var actStr = "참고용으로 읽음";
    if (Array.isArray(steps) && typeof index === "number" && rawPath) {
      var curNorm = rawPath.replace(/\\/g, "/").toLowerCase();
      var hasWrite = false;
      var hasRead = false;
      for (var j = index + 1; j < steps.length; j++) {
        var nextSt = steps[j];
        if (!nextSt) continue;
        var nextP = "";
        if (nextSt.path) {
          nextP = String(nextSt.path).trim();
        } else if (nextSt.detail) {
          nextP = String(nextSt.detail).trim();
        }
        nextP = nextP.replace(/\s*\(\d+~\d+행\)\s*$/, "").trim();
        if (!nextP) continue;
        if (nextP.replace(/\\/g, "/").toLowerCase() === curNorm) {
          if (nextSt.tool === "write_to_file" || nextSt.tool === "write_file" || nextSt.tool === "replace_file_content") {
            hasWrite = true;
            break;
          } else if (nextSt.tool === "read_file" || nextSt.tool === "view_file") {
            hasRead = true;
          }
        }
      }
      if (hasWrite) {
        actStr = "이후 이 파일을 수정함";
      } else if (hasRead) {
        actStr = "다시 읽음";
      }
    }

    var parts = [];
    if (rangeStr) parts.push(rangeStr);
    parts.push(kindStr);
    parts.push(actStr);
    return parts.join(" · ");
  }

  // 과정 목록(<ol>). 제목 줄(번호 · 시각 · 도구 · 접기/펼치기 · 대상 · 라벨)은 항상 보이고,
  // 실제 작업 내용(body)·읽기 설명·설명/생각(say/think)은 기본으로 접혀 있다가 ▸ 버튼으로 펼친다.
  function buildProcessRowsHtml(steps, cwd, opts) {
    var procSteps = groupProcessSteps(steps);
    var openMap = (opts && opts.openMap) ? opts.openMap : null;
    var keyPrefix = (opts && opts.keyPrefix) ? String(opts.keyPrefix) : "";
    var hasSkipped = false;
    var totalCalls = 0;
    var CHEVRON_SVG = '<svg class="proc-toggle-chevron" width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4.5 2.5L8 6l-3.5 3.5"/></svg>';

    function renderStepBody(body) {
      if (!body || typeof body !== "object") return "";
      var parts = [];
      if (body.desc) {
        parts.push('<div class="proc-body-desc">' + escapeHtml(String(body.desc)) + '</div>');
      }
      if (Array.isArray(body.edits) && body.edits.length) {
        body.edits.forEach(function (ed) {
          if (!ed || typeof ed !== "object") return;
          var cap = "";
          if (ed.from != null && ed.to != null) {
            cap = (ed.from === ed.to) ? (ed.from + "행") : (ed.from + "~" + ed.to + "행");
          } else if (ed.from != null) {
            cap = ed.from + "행~";
          } else if (ed.to != null) {
            cap = "~" + ed.to + "행";
          }
          var lines = [];
          if (ed.old != null && String(ed.old) !== "") {
            String(ed.old).split(/\r?\n/).forEach(function (ln) {
              lines.push('<span class="proc-diff-del">- ' + escapeHtml(ln) + '</span>');
            });
          }
          if (ed.new != null && String(ed.new) !== "") {
            String(ed.new).split(/\r?\n/).forEach(function (ln) {
              lines.push('<span class="proc-diff-add">+ ' + escapeHtml(ln) + '</span>');
            });
          }
          if (lines.length || cap) {
            parts.push('<div class="proc-diff">' +
              (cap ? '<div class="proc-diff-cap">' + escapeHtml(cap) + '</div>' : '') +
              (lines.length ? '<pre class="proc-diff-code">' + lines.join("\n") + '</pre>' : '') +
              '</div>');
          }
        });
      }
      if (body.text != null && String(body.text) !== "") {
        parts.push('<pre class="proc-body-text">' + escapeHtml(String(body.text)) + '</pre>');
      }
      if (Array.isArray(body.args) && body.args.length) {
        var argRows = [];
        body.args.forEach(function (pair) {
          if (!Array.isArray(pair) || pair.length < 2) return;
          argRows.push('<div class="proc-arg"><dt>' + escapeHtml(String(pair[0])) + '</dt><dd>' + escapeHtml(String(pair[1])) + '</dd></div>');
        });
        if (argRows.length) {
          parts.push('<dl class="proc-args">' + argRows.join("") + '</dl>');
        }
      }
      return parts.join("");
    }

    var rows = procSteps.map(function (st, idx) {
      if (st && st.skipped) {
        hasSkipped = true;
        totalCalls += Number(st.skipped) || 0;
        return '<li class="proc-row proc-skipped"><span class="proc-skipped-text">… 중간 ' + (Number(st.skipped) || 0).toLocaleString() + '번 생략 …</span></li>';
      }
      totalCalls++;
      var tool = progressToolLabel(st.tool) || "기타";
      var shown = shortenPathsForCwd(st.detail, cwd);
      var tip = [];
      if (st._isGrouped && st._groupedTip) {
        tip.push(st._groupedTip);
      } else {
        if (st.tool) tip.push("도구: " + st.tool);
        if (st.detail) tip.push("대상: " + st.detail);
        if (shown !== st.detail && cwdListOf(cwd).length) {
          var tipCwds = cwdListOf(cwd);
          tip.push("작업 폴더(@cwd): " + tipCwds.join(", ") + (tipCwds.length > 1 ? " — 여러 폴더라 목록에는 폴더 이름부터 줄여 보입니다" : " — 목록에는 이 폴더 아래 경로만 줄여 보입니다"));
        }
        if (st.label) tip.push("agy 가 붙인 설명: " + st.label);
      }
      var readDesc = describeReadStep(st, procSteps, idx);
      var readDescHtml = readDesc ? '<div class="proc-read-desc">' + escapeHtml(readDesc) + '</div>' : "";
      var narrHtml = buildNarrationHtml("proc", st.say, st.think);
      var bodyHtml = renderStepBody(st.body);
      var innerBody = readDescHtml + narrHtml + bodyHtml;
      var hasBody = innerBody.length > 0;
      var rowKey = keyPrefix + "|" + String(st.n != null ? st.n : "") + "|" + String(idx);
      var bodyId = "proc-body-" + idx;
      var isOpen = Boolean(hasBody && openMap && openMap[rowKey]);
      var toggleHtml = hasBody
        ? '<button type="button" class="proc-toggle" aria-expanded="' + (isOpen ? "true" : "false") +
          '" aria-controls="' + bodyId + '" data-proc-row="' + escapeHtml(rowKey) +
          '" title="' + (isOpen ? "내용 숨기기" : "내용 보기") +
          '" aria-label="' + (isOpen ? "내용 숨기기" : "내용 보기") + '">' + CHEVRON_SVG + '</button>'
        : "";
      var bodyWrap = hasBody
        ? ' <div class="proc-body" id="' + bodyId + '"' + (isOpen ? '' : ' hidden') + '>' + innerBody + '</div>'
        : "";
      return '<li class="proc-row"' + (tip.length ? ' title="' + escapeHtml(tip.join("\n")) + '"' : '') + '>' +
        '<span class="proc-n">' + escapeHtml(String(st.n)) + '</span>' +
        '<span class="proc-at">' + escapeHtml(st.at || "") + '</span>' +
        '<span class="proc-tool">' + escapeHtml(tool) + (st.bg ? ' (백그라운드)' : '') + toggleHtml + '</span>' +
        '<span class="proc-text">' +
          (st.detail ? '<span class="proc-detail">' + escapeHtml(shown) + '</span>' : '') +
          (st.label ? ' <span class="proc-label">' + (st.detail ? '· ' : '') + escapeHtml(st.label) + '</span>' : '') +
          bodyWrap +
        '</span></li>';
    });
    var note = (hasSkipped || totalCalls > 1500 || (steps && steps.length > 1500))
      ? '<p class="proc-note">기록은 1,500번까지 그대로, 넘으면 앞 300번과 뒤 1,200번만 남깁니다.</p>'
      : "";
    return '<ol class="proc-list">' + rows.join("") + '</ol>' + note;
  }

  // 기록에 과정이 없는 옛 위임: 대화 id 별로 한 번만 읽어 와서 기억해 둔다(카드를 다시 그려도 다시 읽지 않는다).
  var processFetchCache = {};   // 대화 id -> { state: "loading" | "done" | "error", found, steps }

  function loadProcessFor(convId) {
    var c = processFetchCache[convId];
    if (c && c.state !== "error") return;
    processFetchCache[convId] = { state: "loading" };
    fetchJson("/api/delegate/process?id=" + encodeURIComponent(convId))
      .then(function (res) {
        processFetchCache[convId] = { state: "done", found: Boolean(res && res.found), steps: (res && Array.isArray(res.steps)) ? res.steps : [] };
      })
      .catch(function () { processFetchCache[convId] = { state: "error" }; })
      .then(function () { applyQaFilters(); });
  }

  // 카드의 "과정" 줄과 그것을 눌러 여는 창이 함께 쓰는 상태 계산. 단계 목록 자체는 여기서 그리지 않는다.
  // opts: { steps: 배열|null, convId: 대화 id, live: 진행 중, waiting: 아직 시작 안 함, cwd: 작업 폴더(경로를 줄여 보이는 기준) }
  // 반환: { steps: 배열|null, message, fetchId(창을 열 때 읽어 와야 하는 대화 id), error, summary(한 줄 요약),
  //         count(단계 수, 아직 모르면 null), openable(버튼을 눌러 볼 내용이 있거나 곧 생길 수 있는지) }
  function resolveProcessState(opts) {
    var steps = Array.isArray(opts.steps) ? opts.steps : null;
    var out = { steps: null, message: "", fetchId: "", error: false, summary: "", count: null, openable: true };
    if (!steps) {
      if (opts.waiting) {
        out.message = "아직 시작하지 않았습니다";
        out.openable = false;
      } else if (opts.convId) {
        var c = processFetchCache[opts.convId];
        if (c && c.state === "done" && c.found) { steps = c.steps; }
        else if (c && c.state === "done") { out.message = "agy 대화 기록이 남아 있지 않아 과정을 볼 수 없습니다"; out.openable = false; }
        else if (c && c.state === "loading") { out.message = "agy 대화 기록에서 읽어 오는 중입니다"; }
        else if (c && c.state === "error") { out.message = "과정을 불러오지 못했습니다"; out.fetchId = opts.convId; out.error = true; }
        else { out.message = "기록에 저장되지 않은 위임입니다. 누르면 agy 대화 기록에서 읽어 옵니다"; out.fetchId = opts.convId; }
      } else {
        out.message = "과정이 기록되지 않았습니다";
        out.openable = false;
      }
    }
    if (steps) {
      out.steps = steps;
      out.count = steps.length;
      out.summary = summarizeProcess(steps, opts.live);
      out.openable = steps.length > 0 || Boolean(opts.live);   // 도구를 안 쓴 완료 작업은 볼 것이 없다
    }
    else { out.summary = out.message; }
    return out;
  }

  // 완료 기록 / 대기·진행 작업에서 과정 창에 넘길 옵션을 만든다. 창이 열려 있는 동안 최신 데이터로 다시 만들 때도 쓴다.
  function recordProcessOpts(r, cwd) {
    var hasSession = Boolean(r && r.session);
    var sinceVal = "";
    if (hasSession) {
      sinceVal = (r.process && r.process.length && r.process[0].ts) ? r.process[0].ts : (r.timestamp || "");
    }
    return {
      steps: Array.isArray(r.process) ? r.process : null,
      convId: r.session_id || "",
      cwd: cwd != null ? cwd : extractImagesFromText(r.question).cwds,
      since: sinceVal
    };
  }
  function pendingProcessOpts(p, cwd) {
    var isProcessing = (p.state === "processing");
    var active = isProcessing || Boolean(p.interrupted);
    var convId = (active && (p.conversation_id || (p.progress && p.progress.conversation_id))) ? String(p.conversation_id || p.progress.conversation_id) : "";
    // 단계 목록은 목록 응답에 싣지 않고(가볍게), 대화 id 로 /api/delegate/process?since= 를 따라가 모은 것(liveProc)을 쓴다.
    // 옛 서버가 progress.steps 를 주면 그것을 쓴다.
    var lp = convId ? liveProc[convId] : null;
    var legacy = (active && p.progress && Array.isArray(p.progress.steps)) ? p.progress.steps : null;
    var hasSession = Boolean(p && p.session);
    return {
      steps: active ? (lp ? lp.steps : (legacy || [])) : null,
      live: isProcessing,
      waiting: !active,
      convId: convId,
      cwd: cwd != null ? cwd : (cwdListOf(p.cwd).length ? cwdListOf(p.cwd) : extractImagesFromText(p.question).cwds),
      since: hasSession ? (p.started_at || "") : ""
    };
  }

  // 카드 키(data-key)로 지금 가진 데이터에서 원본을 찾는다. 진행 중이던 작업이 끝나 기록으로 옮겨 갔으면 그쪽을 찾아 준다.
  function findProcessSource(key) {
    var i, id;
    if (key.indexOf("p:") === 0) {
      id = key.slice(2);
      for (i = 0; i < pendingItems.length; i++) {
        if (pendingItems[i] && pendingItems[i].task_id === id) return { key: key, taskId: id, opts: pendingProcessOpts(pendingItems[i]), pending: pendingItems[i], record: null };
      }
      key = "r:" + id;   // 끝났으면 완료 기록에서
    }
    for (i = 0; i < allItems.length; i++) {
      var r = allItems[i];
      if (r && ("r:" + (r.task_id || r.timestamp || "")) === key) return { key: key, taskId: r.task_id || "", opts: recordProcessOpts(r), pending: null, record: r };
    }
    return null;
  }

  // ---- 진행 중인 작업의 과정을 따라가기. 목록 응답(/api/delegate/pending)은 단계 수(progress.step_count)만 알려 주고,
  // 단계 자체는 단계 수가 늘었을 때만 /api/delegate/process?since=<마지막 단계 번호> 로 새 것만 받아 이어 붙인다.
  // 기록 파일이 안 바뀌었으면 서버가 파일을 다시 읽지 않고(읽은 위치를 기억), 화면도 요청하지 않는다. 작업이 끝나 목록에서 빠지면 기억을 비운다.
  var liveProc = {};   // 대화 id -> { steps, lastN, busy }

  function syncLiveProcess(list) {
    var keep = {};
    (list || []).forEach(function (p) {
      if (!p || !(p.state === "processing" || p.interrupted)) { return; }
      var id = p.conversation_id || (p.progress && p.progress.conversation_id);
      if (!id) { return; }
      id = String(id);
      keep[id] = true;
      var hasSession = Boolean(p.session);
      var lp = liveProc[id];
      if (!lp) { lp = liveProc[id] = { steps: [], lastN: -1, busy: false, started: (hasSession ? (p.started_at || "") : ""), session: p.session || "" }; }
      else if (hasSession && p.started_at && !lp.started) { lp.started = p.started_at; }
      var want = p.progress && p.progress.step_count != null ? Number(p.progress.step_count) : null;
      if (want != null && want > lp.steps.length) { fetchLiveProcess(id); }
    });
    Object.keys(liveProc).forEach(function (id) { if (!keep[id]) { delete liveProc[id]; } });
  }

  function fetchLiveProcess(id) {
    var lp = liveProc[id];
    if (!lp) { lp = liveProc[id] = { steps: [], lastN: -1, busy: false, started: "" }; }
    if (lp.busy) { return; }
    lp.busy = true;
    var startParam = (lp.session && lp.started) ? "&started=" + encodeURIComponent(lp.started) : "";
    fetchJson("/api/delegate/process?id=" + encodeURIComponent(id) + (lp.lastN >= 0 ? "&since=" + lp.lastN : "") + startParam)
      .then(function (res) {
        if (!liveProc[id]) { return; }   // 그 사이 작업이 끝났다
        var got = (res && Array.isArray(res.steps)) ? res.steps : [];
        var before = lp.steps.length;
        lp.steps = (res && res.reset) ? got.slice() : lp.steps.concat(got);
        lp.lastN = lp.steps.length ? lp.steps[lp.steps.length - 1].n : -1;
        if (lp.steps.length !== before || (res && res.reset)) {
          renderProcessDialog();
          updateProcessButtons();
        }
      })
      .catch(function () {})
      .then(function () { lp.busy = false; });
  }

  // 카드·핸드오프 줄의 "과정" 버튼에 단계 수를 제자리에서 갱신한다(카드를 다시 그리지 않는다).
  function updateProcessButtons() {
    var btns = document.querySelectorAll('.proc-open[data-proc-key^="p:"]');
    for (var i = 0; i < btns.length; i++) {
      var src = findProcessSource(btns[i].getAttribute("data-proc-key"));
      if (!src) { continue; }
      var st = resolveProcessState(src.opts);
      btns[i].title = st.summary;
      btns[i].setAttribute("aria-label", "과정 보기: " + st.summary);
      btns[i].disabled = !st.openable;
      var cnt = btns[i].querySelector(".proc-open-count");
      if (st.count != null) {
        if (!cnt) { cnt = document.createElement("span"); cnt.className = "proc-open-count"; btns[i].appendChild(cnt); }
        cnt.textContent = String(st.count);
      }
    }
  }

  // 카드 맨 윗줄 오른쪽의 "과정" 버튼. 질문/답변 줄과 달리 카드 안에 내용을 펼치지 않고, 누르면 창에서 단계 목록을 그린다.
  // 단계 수를 옆에 작게 보이고, 요약과 이유(볼 내용이 없을 때)는 마우스를 올리면 나온다.
  function buildProcessButton(key, opts) {
    var st = resolveProcessState(opts);
    var b = document.createElement("button");
    b.type = "button";
    b.className = "proc-open";
    b.setAttribute("data-proc-key", key);
    b.setAttribute("aria-haspopup", "dialog");
    b.title = st.summary;
    b.setAttribute("aria-label", "과정 보기: " + st.summary);
    b.disabled = !st.openable;
    var label = document.createElement("span");
    label.textContent = "과정";
    b.appendChild(label);
    if (st.count != null) {
      var cnt = document.createElement("span");
      cnt.className = "proc-open-count";
      cnt.textContent = String(st.count);
      b.appendChild(cnt);
    }
    return b;
  }

  // ---- 과정 번역("한글로 번역"). agy 의 생각·설명·라벨은 영어로 나올 때가 많다. 창에서 버튼을 눌렀을 때만 서버
  // (/api/delegate/translate)가 agy(quick 단계, 기본 gemini-4-hydrogen-low)로 옮기고, 결과는 서버에 캐시돼서 다음부터는 바로 보인다.
  var procTr = {};        // 대화 id -> { state: running|done|none|error|unavailable, message, items(단계 순번 -> label/think/say), model }
  var procTrView = {};    // 대화 id -> "orig" | "agy" | "browser": 사용자가 고른 보기(고르지 않았으면 있는 번역본)
  var procTrTimer = null;
  var procDialogConv = "";  // 지금 창에 보이는 과정의 대화 id
  var procDialogSince = ""; // 지금 창에 보이는 과정의 시작 시각(이어 보낸 세션 구분용)

  function hasHangul(s) { return /[\uAC00-\uD7A3]/.test(String(s == null ? "" : s)); }

  // 인용한 말: `코드`, "큰따옴표", “둥근 큰따옴표”, '작은따옴표'(don't 같은 아포스트로피는 제외). 인용문은 고정된 말이라
  // 한글이든 영어든 번역하지 않고 그대로 두고, "이미 한글인 글인가" 를 가를 때도 세지 않는다.
  var QUOTED_SPAN_SRC = "`[^`\\n]+`|\"[^\"\\n]+\"|\u201C[^\u201D\\n]+\u201D|(?<![A-Za-z0-9])'[^'\\n]+'(?![A-Za-z0-9])";
  function quotedSpanRe() { return new RegExp(QUOTED_SPAN_SRC, "g"); }

  // 인용문을 뺀 나머지 글
  function withoutQuotedSpans(s) { return String(s == null ? "" : s).replace(quotedSpanRe(), " "); }

  // 번역해야 하는 글인가: 인용문 밖에 한글이 없고, 인용문 밖에 번역할 영어(알파벳)가 있어야 한다.
  // 예) 영어 문장 안의 `04_샘플 이벤트.sql` 은 한글이 있어도 번역 대상이고, 한글 문장은 아니다.
  function needsTranslationText(s) {
    var rest = withoutQuotedSpans(s);
    return !hasHangul(rest) && /[A-Za-z]/.test(rest);
  }

  // 번역할 글(한글이 아닌 라벨·생각·설명)이 하나라도 있는지. items 를 주면 그 안에 이미 번역된 칸은 뺀다.
  function needsTranslation(steps, items) {
    if (!steps) return false;
    var names = ["label", "think", "say"];
    for (var i = 0; i < steps.length; i++) {
      var have = items ? items[String(i)] : null;
      for (var k = 0; k < names.length; k++) {
        var v = steps[i][names[k]];
        if (v && needsTranslationText(v) && !(have && have[names[k]])) return true;
      }
    }
    return false;
  }


  // 번역해 둔 라벨·생각·설명으로 단계 목록의 글을 바꾼 사본을 돌려준다(원본은 건드리지 않는다). 순번은 단계 목록의 위치다.
  function applyProcessTranslation(steps, items) {
    if (!items) return steps;
    return steps.map(function (st, i) {
      var ko = items[String(i)];
      if (!ko) return st;
      var c = {};
      for (var k in st) { if (Object.prototype.hasOwnProperty.call(st, k)) c[k] = st[k]; }
      if (ko.label) c.label = ko.label;
      if (ko.think) c.think = ko.think;
      if (ko.say) c.say = ko.say;
      return c;
    });
  }

  function procItemCount(items) { return items ? Object.keys(items).length : 0; }

  // 지금 보는 글: "orig"(원문) | "agy"(agy 번역) | "browser"(브라우저 번역). 고르지 않았으면 있는 번역본(agy 우선), 없으면 원문.
  function procTrViewOf(convId) {
    var nA = procItemCount(procTr[convId] && procTr[convId].items);
    var nB = procItemCount(procTrB[convId] && procTrB[convId].items);
    var v = procTrView[convId];
    if (v === "orig") return "orig";
    if (v === "agy" && nA) return "agy";
    if (v === "browser" && nB) return "browser";
    return nA ? "agy" : (nB ? "browser" : "orig");
  }

  function procTrItemsFor(convId, view) {
    if (view === "agy") return (procTr[convId] && procTr[convId].items) || null;
    if (view === "browser") return (procTrB[convId] && procTrB[convId].items) || null;
    return null;
  }

  // 창 위쪽의 번역 줄: 보기 전환(원문 / agy 번역 / 브라우저 번역)과 번역 실행 버튼 두 개(agy, 브라우저)와 안내.
  // 번역할 글이 없고 번역해 둔 것도 없으면 빈 글(줄을 숨긴다).
  function buildTranslateToolsHtml(convId, steps) {
    if (!convId || !steps || !steps.length) return "";
    var agy = procTr[convId] || null;
    var br = procTrB[convId] || null;
    var nA = procItemCount(agy && agy.items);
    var nB = procItemCount(br && br.items);
    var needA = needsTranslation(steps, agy && agy.items);
    var needB = needsTranslation(steps, br && br.items);
    if (!needsTranslation(steps) && !nA && !nB) return "";
    var view = procTrViewOf(convId);
    var out = [];

    // 보기 전환: 번역본이 하나라도 있을 때만
    if (nA || nB) {
      var views = [["orig", "원문"]];
      if (nA) views.push(["agy", "agy 번역"]);
      if (nB) views.push(["browser", "브라우저 번역"]);
      out.push('<span class="proc-tr-views" role="group" aria-label="보기">' + views.map(function (v) {
        return '<button type="button" class="proc-tr-btn proc-tr-view" data-act="view" data-view="' + v[0] + '" aria-pressed="' + (view === v[0] ? "true" : "false") + '">' + v[1] + '</button>';
      }).join("") + '</span>');
    }

    // agy 로 번역
    var aState = agy ? agy.state : "";
    if (aState === "running") {
      out.push('<button type="button" class="proc-tr-btn" disabled>agy 번역 중… (30초~1분)</button>');
    } else if (aState !== "unavailable" && aState !== "done" && needA) {
      out.push('<button type="button" class="proc-tr-btn" data-act="translate" title="agy(quick 단계 · hydrogen-low)가 번역합니다. 30초~1분 걸리고 agy 사용량을 씁니다. 결과는 서버에 저장됩니다.">' +
        (nA > 0 ? "agy로 새 단계 번역" : (aState === "error" ? "agy로 다시 시도" : "agy로 번역")) + '</button>');
    }

    // 브라우저로 번역
    var bState = br ? br.state : "";
    if (browserTranslatorSupported()) {
      if (bState === "running") {
        var pg = br.progress || {};
        out.push('<button type="button" class="proc-tr-btn" disabled>' +
          (pg.download >= 0 ? "언어 팩 내려받는 중 " + pg.download + "%" : "브라우저 번역 중… " + (pg.total ? pg.done + "/" + pg.total : "")) + '</button>');
      } else if (needB) {
        out.push('<button type="button" class="proc-tr-btn" data-act="translate-browser" title="이 브라우저의 내장 번역을 씁니다. 무료이고 빠르지만 품질이 낮을 수 있습니다. 처음에는 언어 팩을 내려받을 수 있습니다.">' +
          (nB > 0 ? "브라우저로 이어서 번역" : (bState === "error" ? "브라우저로 다시 시도" : "브라우저로 번역")) + '</button>');
      }
    }

    // 안내
    if (aState === "unavailable") out.push('<span class="proc-tr-note">' + escapeHtml((agy && agy.message) || "agy 로는 번역할 수 없습니다") + '.</span>');
    if (aState === "error" && agy.message) out.push('<span class="proc-tr-note">agy 번역 실패: ' + escapeHtml(agy.message) + '</span>');
    if (bState === "error" && br.message) out.push('<span class="proc-tr-note">브라우저 번역 실패: ' + escapeHtml(br.message) + '</span>');
    if (bState === "done" && br.message) out.push('<span class="proc-tr-note">' + escapeHtml(br.message) + '.</span>');
    if (view === "agy") out.push('<span class="proc-tr-note">AI(' + escapeHtml((agy && agy.model) || "agy") + ')가 번역한 글입니다.</span>');
    if (view === "browser") out.push('<span class="proc-tr-note">브라우저 내장 번역 결과입니다. 틀릴 수 있습니다.</span>');
    return out.join("");
  }

  function setProcessTranslation(convId, res, fallbackMessage) {
    var prev = procTr[convId] || {};
    if (res && typeof res === "object") {
      procTr[convId] = { state: res.state || "none", message: res.message || "", items: res.items || {}, model: res.model || prev.model || "" };
    } else {
      procTr[convId] = { state: "error", message: fallbackMessage || "", items: prev.items || {}, model: prev.model || "" };
    }
  }

  // 번역 중이면 3초마다 상태를 다시 읽는다(창이 이 대화를 보여 주는 동안만).
  function afterProcessTranslationChange(convId) {
    renderProcessDialog();
    if (procTrTimer) { clearTimeout(procTrTimer); procTrTimer = null; }
    var t = procTr[convId];
    var dlg = document.getElementById("process-dialog");
    if (t && t.state === "running" && dlg && dlg.open && procDialogConv === convId) {
      procTrTimer = setTimeout(function () { loadProcessTranslation(convId); }, 3000);
    }
  }

  function loadProcessTranslation(convId) {
    var sinceQ = procDialogSince ? "&since=" + encodeURIComponent(procDialogSince) : "";
    fetchJson("/api/delegate/translate?id=" + encodeURIComponent(convId) + sinceQ)
      .then(function (res) { setProcessTranslation(convId, res, "번역 상태를 읽지 못했습니다"); })
      .catch(function () { setProcessTranslation(convId, null, "번역 상태를 읽지 못했습니다"); })
      .then(function () { afterProcessTranslationChange(convId); });
  }

  function startProcessTranslation(convId) {
    var prev = procTr[convId] || {};
    procTr[convId] = { state: "running", message: "", items: prev.items || {}, model: prev.model || "" };
    renderProcessDialog();
    var sinceQ = procDialogSince ? "&since=" + encodeURIComponent(procDialogSince) : "";
    fetch("/api/delegate/translate?id=" + encodeURIComponent(convId) + sinceQ, { method: "POST", headers: { "X-Samjil-Viewer": "1" } })
      .then(function (r) { return r.text(); })
      .then(function (t) {
        if (t && t.charCodeAt(0) === 0xFEFF) { t = t.slice(1); }
        setProcessTranslation(convId, JSON.parse(t), "번역을 시작하지 못했습니다");
      })
      .catch(function () { setProcessTranslation(convId, null, "번역을 시작하지 못했습니다"); })
      .then(function () { afterProcessTranslationChange(convId); });
  }

  // ---- 브라우저 내장 번역(Translator API). 서버·agy 를 거치지 않고 이 화면이 직접 영어->한국어로 옮긴다. 무료이고 빠르지만
  // 품질이 낮을 수 있고, 지시("코드는 번역하지 마")를 줄 수 없어서 백틱 안의 코드는 번역 전에 자리표시자로 빼 두었다가 되돌린다.
  // 되돌리지 못한 글(자리표시자가 사라지거나 늘어남)은 번역본으로 쓰지 않고 원문을 둔다. 결과는 이 브라우저(localStorage)에만 남는다.
  var procTrB = {};   // 대화 id -> { state: running|done|error, message, items, progress: { done, total, download } }
  var BROWSER_TR_STORE = "samjil.processTranslation.browser.v1";
  var BROWSER_TR_KEEP = 40;   // 최근 대화 몇 개까지 기억할지

  // 인용문(백틱·따옴표로 감싼 코드/이름/말)을 XQ1X, XQ2X … 로 바꿔 둔다.
  function protectCodeSpans(text) {
    var codes = [];
    var out = String(text == null ? "" : text).replace(quotedSpanRe(), function (m) { codes.push(m); return "XQ" + codes.length + "X"; });
    return { text: out, codes: codes };
  }

  // 번역된 글의 자리표시자를 원래 코드로 되돌린다. 모델이 대소문자나 공백을 흐트러뜨려도(xq 1 x) 받아 준다.
  // 하나라도 없거나, 만든 적 없는 자리표시자가 있으면 null(쓰지 않는다).
  function restoreCodeSpans(text, codes) {
    var s = String(text == null ? "" : text);
    for (var i = 0; i < codes.length; i++) {
      var re = new RegExp("XQ\\s*" + (i + 1) + "\\s*X", "gi");
      if (!re.test(s)) return null;
      re.lastIndex = 0;
      (function (code) { s = s.replace(re, function () { return code; }); })(codes[i]);
    }
    return /XQ\s*\d+\s*X/i.test(s) ? null : s;
  }

  // 인용문(`top_words` 같은 코드 표기, 따옴표로 감싼 말)들. 번역 뒤에 이것들이 그대로 남아 있어야 번역을 쓴다.
  function codeSpansOf(text) { return String(text == null ? "" : text).match(quotedSpanRe()) || []; }

  // 번역기가 백틱만 떼고 이름은 그대로 둔 경우(top_words)도 코드가 남은 것으로 본다.
  function codesSurvive(src, out) {
    var codes = codeSpansOf(src);
    for (var i = 0; i < codes.length; i++) {
      var inner = codes[i].slice(1, -1);
      if (String(out).indexOf(codes[i]) < 0 && String(out).indexOf(inner) < 0) return false;
    }
    return true;
  }

  // 글을 문장 단위로 나눈다(마침표·물음표·느낌표 뒤의 공백). 한 문장이면 길이 1.
  function splitSentences(text) {
    return String(text == null ? "" : text).split(/(?<=[.!?])\s+/).filter(function (p) { return p.trim(); });
  }

  // 한 덩어리를 번역하고 코드 표기를 지킨다. 두 가지를 차례로 시도한다.
  //   1) 글을 그대로 번역한다. 모델이 백틱 안의 코드를 그대로 두는 일이 많아서, 코드 표기가 모두 남아 있으면 그것을 쓴다.
  //   2) 안 남았으면 코드를 자리표시자(XQ1X)로 바꿔 번역한 뒤 되돌린다(자리표시자가 흐트러지면 쓰지 않는다).
  // 반환: Promise<{ text: 번역 또는 null, reason: "" | "code"(코드 표기가 사라짐) | "empty"(빈 번역) | "error", message, sample }>
  function translateChunkKeepingCode(translator, text) {
    var raw = String(text);
    var sample = "";
    return Promise.resolve().then(function () { return translator.translate(raw); }).then(function (ko) {
      ko = String(ko == null ? "" : ko).trim();
      sample = ko;
      if (ko && codesSurvive(raw, ko)) return { text: ko, reason: "" };
      var pr = protectCodeSpans(raw);
      if (!pr.codes.length) return { text: null, reason: ko ? "code" : "empty", sample: sample };
      return Promise.resolve(translator.translate(pr.text)).then(function (ko2) {
        var restored = restoreCodeSpans(ko2, pr.codes);
        if (restored && restored.trim()) return { text: restored.trim(), reason: "" };
        return { text: null, reason: "code", sample: String(ko2 == null ? "" : ko2).trim() || sample };
      });
    }).catch(function (err) {
      return { text: null, reason: "error", message: (err && err.message) ? err.message : String(err), sample: sample };
    });
  }

  // 한 칸의 글을 번역한다. 통째로 안 되면 문장별로 나눠 되는 문장만 번역하고 나머지 문장은 원문으로 둔다(칸 하나에 한글과 영어가 섞인다).
  function translateTextWithBrowser(translator, text) {
    return translateChunkKeepingCode(translator, text).then(function (r) {
      if (r.text) return r;
      var parts = splitSentences(text);
      if (parts.length < 2) return r;
      var out = [], got = 0, chain = Promise.resolve();
      parts.forEach(function (p) {
        chain = chain.then(function () {
          return translateChunkKeepingCode(translator, p).then(function (q) {
            if (q.text) { got++; out.push(q.text); } else { out.push(p); }
          });
        });
      });
      return chain.then(function () { return got ? { text: out.join(" "), reason: "", partial: true } : r; });
    });
  }

  // 번역기(translator.translate(글) -> Promise<글>)로 단계 목록의 한글 아닌 칸을 번역한다. existing 에 이미 있는 칸은 건너뛴다.
  // 반환: Promise<{ items, failed, total, partial(문장 일부만 번역한 칸 수), reasons: { code, empty, error }, firstError, sample }>.
  // 한 칸이 실패해도 나머지는 계속한다.
  function translateStepsWithBrowser(steps, existing, translator, onProgress) {
    var jobs = [];
    var fields = ["label", "think", "say"];
    steps.forEach(function (st, i) {
      fields.forEach(function (f) {
        var v = st[f];
        var have = existing && existing[String(i)] && existing[String(i)][f];
        if (v && needsTranslationText(v) && !have) jobs.push({ i: String(i), f: f, text: String(v) });
      });
    });
    var items = {};
    Object.keys(existing || {}).forEach(function (k) { items[k] = {}; Object.keys(existing[k]).forEach(function (f) { items[k][f] = existing[k][f]; }); });
    var res = { items: items, failed: 0, total: jobs.length, partial: 0, reasons: { code: 0, empty: 0, error: 0 }, firstError: "", sample: "" };
    var done = 0;
    var chain = Promise.resolve();
    jobs.forEach(function (j) {
      chain = chain.then(function () {
        return translateTextWithBrowser(translator, j.text).then(function (r) {
          if (r.text) {
            if (!items[j.i]) items[j.i] = {};
            items[j.i][j.f] = r.text;
            if (r.partial) res.partial++;
          } else {
            res.failed++;
            res.reasons[r.reason] = (res.reasons[r.reason] || 0) + 1;
            if (r.reason === "error" && !res.firstError) res.firstError = r.message || "";
            if (r.reason === "code" && !res.sample) res.sample = (r.sample || "").slice(0, 80);
          }
        }).then(function () {
          done++;
          if (onProgress) onProgress(done, jobs.length);
        });
      });
    });
    return chain.then(function () { return res; });
  }

  // 번역이 끝난 뒤 사용자에게 보일 안내(실패한 칸이 있을 때 이유를 함께). 실패한 칸이 없으면 빈 글.
  function browserTranslationMessage(res) {
    var bits = [];
    if (res.reasons.code) bits.push("번역에서 코드 표기가 사라진 칸 " + res.reasons.code + (res.sample ? " (번역기가 돌려준 글 예: \"" + res.sample + "\")" : ""));
    if (res.reasons.empty) bits.push("빈 번역 " + res.reasons.empty);
    if (res.reasons.error) bits.push("번역기 오류 " + res.reasons.error + (res.firstError ? " (" + res.firstError + ")" : ""));
    var detail = bits.length ? " — " + bits.join(", ") : "";
    if (res.total > 0 && res.failed === res.total) return "브라우저 번역이 모든 글에서 실패했습니다" + detail;
    if (res.failed) return res.failed + "칸은 번역을 쓸 수 없어 원문으로 두었습니다" + detail;
    if (res.partial) return res.partial + "칸은 일부 문장만 번역했습니다";
    return "";
  }

  function withTimeout(promise, ms, message) {
    return new Promise(function (resolve, reject) {
      var t = setTimeout(function () { reject(new Error(message)); }, ms);
      Promise.resolve(promise).then(function (v) { clearTimeout(t); resolve(v); }, function (e) { clearTimeout(t); reject(e); });
    });
  }

  function browserTranslatorSupported() { return typeof Translator !== "undefined"; }

  // 번역기를 만든다. 언어 팩이 없으면 내려받는다(진행률은 onDownload). 이 브라우저가 못 하면 이유를 담아 reject.
  function createBrowserTranslator(onDownload) {
    if (!browserTranslatorSupported()) return Promise.reject(new Error("이 브라우저는 내장 번역(Translator API)을 지원하지 않습니다"));
    var opts = { sourceLanguage: "en", targetLanguage: "ko" };
    return withTimeout(Translator.availability(opts), 10000, "브라우저가 번역 가능 여부에 답하지 않습니다. 이 브라우저에서는 쓸 수 없는 것 같습니다")
      .then(function (av) {
        if (av === "unavailable") throw new Error("이 브라우저는 영어→한국어 번역을 지원하지 않습니다");
        var create = Translator.create({
          sourceLanguage: opts.sourceLanguage, targetLanguage: opts.targetLanguage,
          monitor: function (m) { m.addEventListener("downloadprogress", function (e) { if (onDownload) onDownload(Math.round((e.loaded || 0) * 100)); }); }
        });
        return withTimeout(create, 180000, "번역 모델 준비가 끝나지 않았습니다. 다시 눌러 주세요");
      });
  }

  function loadBrowserTranslations() {
    try {
      var raw = window.localStorage.getItem(BROWSER_TR_STORE);
      var obj = raw ? JSON.parse(raw) : {};
      return (obj && typeof obj === "object") ? obj : {};
    } catch (e) { return {}; }
  }

  function saveBrowserTranslation(convId, items) {
    try {
      var all = loadBrowserTranslations();
      all[convId] = { t: Date.now(), items: items };
      var ids = Object.keys(all).sort(function (a, b) { return (all[b].t || 0) - (all[a].t || 0); });
      ids.slice(BROWSER_TR_KEEP).forEach(function (id) { delete all[id]; });
      window.localStorage.setItem(BROWSER_TR_STORE, JSON.stringify(all));
    } catch (e) { /* 저장을 못 해도(비공개 창 등) 이번 화면에서는 번역본이 보인다 */ }
  }

  // 창을 열 때 이 브라우저에 저장해 둔 번역이 있으면 불러온다.
  function restoreBrowserTranslation(convId) {
    if (procTrB[convId] && procTrB[convId].items) return;
    var saved = loadBrowserTranslations()[convId];
    if (saved && saved.items && Object.keys(saved.items).length) procTrB[convId] = { state: "done", message: "", items: saved.items, progress: null };
  }

  function startBrowserTranslation(convId, steps) {
    var prev = procTrB[convId] || {};
    var existing = prev.items || {};
    procTrB[convId] = { state: "running", message: "", items: existing, progress: { done: 0, total: 0, download: -1 } };
    renderProcessDialog();
    var token = procTrB[convId];
    function progress(p) { if (procTrB[convId] === token) { token.progress = p; renderProcessDialog(); } }
    createBrowserTranslator(function (pct) { progress({ done: 0, total: 0, download: pct }); })
      .then(function (translator) {
        return translateStepsWithBrowser(steps, existing, translator, function (d, t) { progress({ done: d, total: t, download: -1 }); })
          .then(function (res) { try { if (translator.destroy) translator.destroy(); } catch (e) {} return res; });
      })
      .then(function (res) {
        var allFailed = res.total > 0 && res.failed === res.total;
        procTrB[convId] = { state: allFailed ? "error" : "done", message: browserTranslationMessage(res), items: res.items, progress: null };
        if (!allFailed) saveBrowserTranslation(convId, res.items);
      })
      .catch(function (err) {
        procTrB[convId] = { state: "error", message: (err && err.message) ? err.message : "브라우저 번역에 실패했습니다", items: existing, progress: null };
      })
      .then(function () { renderProcessDialog(); });
  }

  var procDialogKey = "";   // 지금 열려 있는 과정 창의 카드 키("" 이면 닫힘)
  var procDialogSteps = null;  // 지금 창에 보이는 단계 목록(브라우저 번역 버튼이 쓴다)
  var procDialogLast = "";  // 마지막으로 그린 내용(같으면 다시 그리지 않아 스크롤과 선택이 유지된다)
  var procExpandedRows = {};  // 과정 창에서 사용자가 펼친 행 키(convId|taskId + "|" + n + "|" + idx -> true)

  function syncProcExpandAllBtn(dlg) {
    if (!dlg) return;
    var allBtn = dlg.querySelector(".proc-expand-all");
    if (!allBtn) return;
    var toggles = dlg.querySelectorAll(".proc-dlg-body .proc-toggle");
    if (!toggles.length) return;
    var allOpen = true;
    for (var i = 0; i < toggles.length; i++) {
      if (toggles[i].getAttribute("aria-expanded") !== "true") { allOpen = false; break; }
    }
    allBtn.textContent = allOpen ? "모두 접기" : "모두 펼치기";
    allBtn.setAttribute("data-open", allOpen ? "true" : "false");
  }

  function ensureProcessDialog() {
    var dlg = document.getElementById("process-dialog");
    if (dlg) return dlg;
    dlg = document.createElement("dialog");
    dlg.id = "process-dialog";
    dlg.setAttribute("aria-labelledby", "process-dialog-title");
    dlg.innerHTML = [
      '<div class="proc-dlg">',
      '  <header class="proc-dlg-head">',
      '    <div class="proc-dlg-heading">',
      '      <h2 id="process-dialog-title" class="proc-dlg-title">과정</h2>',
      '      <span class="proc-dlg-task"></span>',
      '    </div>',
      '    <button type="button" class="proc-dlg-close" title="닫기 (Esc)">닫기</button>',
      '  </header>',
      '  <div class="proc-dlg-health live-health" hidden></div>',
      '  <p class="proc-dlg-sum"></p>',
      '  <p class="proc-dlg-cwd"></p>',
      '  <div class="proc-dlg-tools" hidden></div>',
      '  <div class="proc-dlg-body"></div>',
      '</div>'
    ].join("");
    dlg.addEventListener("click", function (e) {
      if (e.target === dlg || (e.target.classList && e.target.classList.contains("proc-dlg-close"))) { dlg.close(); return; }
      var toggle = e.target.closest ? e.target.closest(".proc-toggle") : null;
      if (toggle) {
        var rowKey = toggle.getAttribute("data-proc-row") || "";
        var ctrlId = toggle.getAttribute("aria-controls") || "";
        var bodyEl = ctrlId ? document.getElementById(ctrlId) : null;
        var nextOpen = toggle.getAttribute("aria-expanded") !== "true";
        if (rowKey) {
          if (nextOpen) procExpandedRows[rowKey] = true;
          else delete procExpandedRows[rowKey];
        }
        toggle.setAttribute("aria-expanded", nextOpen ? "true" : "false");
        toggle.title = nextOpen ? "내용 숨기기" : "내용 보기";
        toggle.setAttribute("aria-label", nextOpen ? "내용 숨기기" : "내용 보기");
        if (bodyEl) bodyEl.hidden = !nextOpen;
        procDialogLast = "";
        syncProcExpandAllBtn(dlg);
        return;
      }
      var expandAll = e.target.closest ? e.target.closest(".proc-expand-all") : null;
      if (expandAll) {
        var wantOpen = expandAll.getAttribute("data-open") !== "true";
        var toggles = dlg.querySelectorAll(".proc-dlg-body .proc-toggle");
        for (var ti = 0; ti < toggles.length; ti++) {
          var tb = toggles[ti];
          var rk = tb.getAttribute("data-proc-row") || "";
          var cid = tb.getAttribute("aria-controls") || "";
          var bel = cid ? document.getElementById(cid) : null;
          if (rk) {
            if (wantOpen) procExpandedRows[rk] = true;
            else delete procExpandedRows[rk];
          }
          tb.setAttribute("aria-expanded", wantOpen ? "true" : "false");
          tb.title = wantOpen ? "내용 숨기기" : "내용 보기";
          tb.setAttribute("aria-label", wantOpen ? "내용 숨기기" : "내용 보기");
          if (bel) bel.hidden = !wantOpen;
        }
        procDialogLast = "";
        syncProcExpandAllBtn(dlg);
        return;
      }
      var retry = e.target.closest ? e.target.closest(".proc-retry") : null;
      if (retry) { loadProcessFor(retry.getAttribute("data-conv")); return; }
      var trBtn = e.target.closest ? e.target.closest(".proc-tr-btn") : null;
      if (trBtn && procDialogConv) {
        var act = trBtn.getAttribute("data-act");
        if (act === "translate") { startProcessTranslation(procDialogConv); }
        else if (act === "translate-browser") { startBrowserTranslation(procDialogConv, procDialogSteps || []); }
        else if (act === "view") { procTrView[procDialogConv] = trBtn.getAttribute("data-view"); renderProcessDialog(); }
      }
    });
    dlg.addEventListener("close", function () {
      procDialogKey = ""; procDialogLast = ""; procDialogConv = ""; procDialogSince = "";
      if (procTrTimer) { clearTimeout(procTrTimer); procTrTimer = null; }
    });
    document.body.appendChild(dlg);
    return dlg;
  }

  // 창 내용을 지금 데이터로 그린다. 진행 중인 작업은 5초마다 새로 고칠 때 새 단계가 이어서 붙는다.
  function renderProcessDialog() {
    if (!procDialogKey) return;
    var dlg = document.getElementById("process-dialog");
    if (!dlg || !dlg.open) return;
    var src = findProcessSource(procDialogKey);
    if (!src) { dlg.close(); return; }
    procDialogKey = src.key;
    var st = resolveProcessState(src.opts);

    var convId = src.opts.convId || "";
    procDialogConv = convId;
    procDialogSince = src.opts.since || "";
    var rowKeyPrefix = convId || src.taskId || procDialogKey || "";
    var html;
    if (st.steps && st.steps.length) {
      procDialogSteps = st.steps;
      var viewItems = procTrItemsFor(convId, procTrViewOf(convId));
      html = buildProcessRowsHtml(viewItems ? applyProcessTranslation(st.steps, viewItems) : st.steps, src.opts.cwd, { openMap: procExpandedRows, keyPrefix: rowKeyPrefix });
    } else if (st.steps) {
      html = '<p class="proc-empty">' + escapeHtml(st.summary) + '.</p>';
    } else {
      html = '<p class="proc-empty">' + escapeHtml(st.message) + '.</p>' +
        (st.error ? '<button type="button" class="proc-retry" data-conv="' + escapeHtml(st.fetchId) + '">다시 시도</button>' : "");
    }
    // 창 맨 위의 상태: 진행 중인 작업은 1초마다 tickHealthElements 가 고치고, 끝난 작업은 기록의 결과를 보인다.
    var healthEl = dlg.querySelector(".proc-dlg-health");
    var dlgHealth = null;
    if (src.pending) {
      dlgHealth = delegateRunHealth(src.pending, Date.now(), watcherAliveNow());
      healthEl.setAttribute("data-health-task", src.taskId);
    } else {
      healthEl.removeAttribute("data-health-task");
      if (src.record) {
        var recOk = isOkStatus(src.record);
        dlgHealth = { kind: recOk ? "done" : "failed", label: recOk ? "끝남" : "실패", detail: recOk ? "" : String(src.record.status || "") };
      }
    }
    if (dlgHealth) {
      healthEl.setAttribute("data-kind", dlgHealth.kind);
      healthEl.setAttribute("data-sig", dlgHealth.label + "|" + dlgHealth.detail);
      healthEl.innerHTML = healthInnerHtml(dlgHealth);
    }
    healthEl.hidden = !dlgHealth;

    var toolsHtml = buildTranslateToolsHtml(convId, st.steps);
    if (html.indexOf('class="proc-toggle"') >= 0) {
      var allExpanded = html.indexOf('class="proc-toggle" aria-expanded="false"') === -1;
      var expandAllBtn = '<button type="button" class="proc-tr-btn proc-expand-all" data-open="' + (allExpanded ? "true" : "false") + '">' + (allExpanded ? "모두 접기" : "모두 펼치기") + '</button>';
      toolsHtml = toolsHtml ? (toolsHtml + expandAllBtn) : expandAllBtn;
    }
    var head = [src.taskId, st.summary, src.opts.live ? "live" : "", cwdListOf(src.opts.cwd).join("|"), toolsHtml].join("\u0001");
    if (procDialogLast === head + "\u0002" + html) return;
    procDialogLast = head + "\u0002" + html;

    dlg.querySelector(".proc-dlg-task").textContent = src.taskId;
    dlg.querySelector(".proc-dlg-sum").textContent = st.summary + (src.opts.live && st.steps ? " · 새 단계가 생기면 자동으로 이어 붙습니다" : "");
    var cwdEl = dlg.querySelector(".proc-dlg-cwd");
    var dlgCwds = cwdListOf(src.opts.cwd);
    cwdEl.textContent = (dlgCwds.length && st.steps && st.steps.length)
      ? (dlgCwds.length === 1
        ? "작업 폴더 " + dlgCwds[0] + " 아래 경로는 폴더 이름을 빼고 보입니다."
        : "작업 폴더 " + dlgCwds.length + "개: " + dlgCwds.join(", ") + " — 이 폴더들 아래 경로는 폴더 이름부터 보입니다.")
      : "";
    cwdEl.hidden = !cwdEl.textContent;
    var toolsEl = dlg.querySelector(".proc-dlg-tools");
    toolsEl.innerHTML = toolsHtml;
    toolsEl.hidden = !toolsHtml;
    var body = dlg.querySelector(".proc-dlg-body");
    var top = body.scrollTop;
    // 진행 중인 작업을 맨 아래까지 보고 있었으면 새 단계가 붙을 때 따라 내려간다. 위쪽을 읽고 있었으면 그 자리를 지킨다.
    var atBottom = body.scrollHeight - top - body.clientHeight < 24;
    body.innerHTML = html;
    body.scrollTop = (src.opts.live && atBottom) ? body.scrollHeight : top;
  }

  function openProcessDialog(key) {
    var src = findProcessSource(key);
    if (!src) return;
    var dlg = ensureProcessDialog();
    procDialogKey = src.key;
    procDialogLast = "";
    procDialogSince = src.opts.since || "";
    // 기록에 과정이 없는 옛 위임만, 창을 여는 지금 한 번 읽어 온다(카드를 그릴 때는 읽지 않는다)
    var st = resolveProcessState(src.opts);
    if (st.fetchId) loadProcessFor(st.fetchId);
    if (src.opts.convId) restoreBrowserTranslation(src.opts.convId);
    if (!dlg.open) dlg.showModal();
    renderProcessDialog();
    // 번역해 둔 것이 있는지 서버에서 한 번 읽는다(작은 응답). 번역을 시작하는 것은 사용자가 버튼을 눌렀을 때뿐이다.
    if (src.opts.convId) loadProcessTranslation(src.opts.convId);
  }

  function qaDiagnoseItem(r) {
    if (!r || typeof r !== "object") return null;
    var st = String(r.status || "").trim().toUpperCase();
    if (st !== "ERROR" && st !== "CANCELLED" && st !== "BLOCKED") return null;
    if (r.diagnosis && (r.diagnosis.label || r.diagnosis.root_cause || r.diagnosis.recommendation)) {
      return r.diagnosis;
    }
    var ans = String(r.answer || "").toLowerCase();
    var note = String(r.account_note || "").toLowerCase();
    if (st === "CANCELLED") {
      if (ans.indexOf("timeout") >= 0 || ans.indexOf("시간 초과") >= 0 || ans.indexOf("watchdog") >= 0 || ans.indexOf("멈춤") >= 0) {
        return { category: "timeout", label: "시간 초과/중단", root_cause: "응답 대기 시간 초과 또는 워치독에 의해 취소되었습니다.", recommendation: "작업을 더 작은 단위로 나누거나 제한 시간을 늘려 재시도하세요." };
      }
      return { category: "cancelled", label: "작업 취소", root_cause: "사용자 또는 상위 세션에 의해 작업이 취소되었습니다.", recommendation: "중단 시점 이후 작업이 필요하면 새 위임으로 이어서 실행하세요." };
    }
    if (st === "BLOCKED") {
      return { category: "blocked", label: "실행 차단", root_cause: "권한, 샌드박스 또는 접근 제한으로 작업이 차단되었습니다.", recommendation: "대상 경로 권한 또는 실행 환경 제약을 확인하세요." };
    }
    if (ans.indexOf("지정한 @model 을 쓸 수 없습니다") >= 0 || ans.indexOf("is not recognized as a known model") >= 0 || ans.indexOf("invalid model selection") >= 0 || ans.indexOf("알 수 없는 모델") >= 0) {
      return { category: "stale_model_catalog", label: "모델 카탈로그 불일치", root_cause: "지정한 모델명 또는 로컬 모델 카탈로그가 현재 지원 목록과 일치하지 않습니다.", recommendation: "models.json 모델 카탈로그를 재동기화하고 사용 가능한 모델명을 확인하세요." };
    }
    if (ans.indexOf("끝내지 못하고 사라졌습니다") >= 0 || ans.indexOf("강제 종료됐을 수 있습니다") >= 0 || ans.indexOf("비정상 종료") >= 0) {
      return { category: "worker_crash_or_exit", label: "워커 비정상 종료", root_cause: "실행 중인 워커 프로세스가 예기치 않게 종료되었습니다.", recommendation: "워커 로그와 시스템 상태를 확인하고 워처를 재시작하세요." };
    }
    if (ans.indexOf("429") >= 0 || ans.indexOf("quota") >= 0 || ans.indexOf("rate limit") >= 0 || ans.indexOf("한도") >= 0 || note.indexOf("한도") >= 0) {
      return { category: "quota", label: "할당량/한도 초과", root_cause: "모델 요청 한도(429/quota)에 도달했습니다.", recommendation: "다른 모델 또는 부계정 슬롯으로 전환하거나 잠시 후 재시도하세요." };
    }
    if (ans.indexOf("timeout") >= 0 || ans.indexOf("timed out") >= 0 || ans.indexOf("시간 초과") >= 0 || ans.indexOf("최대 대기 시간") >= 0 || ans.indexOf("후에도 멈춤") >= 0) {
      return { category: "timeout", label: "실행 시간 초과", root_cause: "모델 또는 명령 실행이 제한 시간 내에 끝나지 않았습니다.", recommendation: "프롬프트 범위를 줄이고 단계별로 나누어 위임하세요." };
    }
    return { category: "error", label: "실행 오류", root_cause: "위임 실행 중 오류가 발생했습니다.", recommendation: "답변 본문과 과정 로그에서 실패 원인을 확인하세요." };
  }

  function buildCard(r) {
    var st = (r.status == null ? "" : String(r.status)).trim();
    var isOk = isOkStatus(r);
    var isErr = (st !== "" && !isOk);

    var card = document.createElement("div");
    card.className = "card" + (isErr ? " err" : "");
    card.setAttribute("data-key", "r:" + (r.task_id || r.timestamp || ""));

    var meta = document.createElement("div");
    meta.className = "meta";
    meta.appendChild(metaHead("실행"));
    // 보이는 시각은 프롬프트를 입력(접수)한 시각이다. 작업 ID(claude_<접수 시각 epoch>_N)에서 구하고, 없으면(옛 기록 · 핸드오프) 완료 시각을 그대로 쓴다. 완료 시각은 마우스를 올리면 보인다.
    var submitText = submitTimeText(r);
    meta.appendChild(labeledMeta("", String(submitText || r.timestamp || "").replace(/^\d{4}-/, ""), "ts", submitText ? "접수(프롬프트 입력) 시각 " + submitText + " · 완료 시각 " + (r.timestamp || "") : "완료 시각 " + (r.timestamp || "")));

    if (st) {
      meta.appendChild(badge("status-" + (isOk ? "ok" : "err"), st.toUpperCase() === "CANCELLED" ? "취소" : st));
    } else {
      meta.appendChild(badge("status-unknown", "상태 미기록"));
    }

    var modelName = recordModel(r) || null;
    var isSession = Boolean(r.session || r.session_id || r.model === "(session)");
    var rAgent = r.agent_model ? { model: r.agent_model, effort: r.agent_effort, type: r.agent_type, desc: r.agent_desc } : null;
    if (r.elapsed_sec) {
      var elSec = Number(r.elapsed_sec);
      meta.appendChild(labeledMeta("소요", formatDuration(elSec), "elapsed", "실제 실행 시간: " + r.elapsed_sec + "초"));
    }
    // 끝난 위임에도 접수부터 실행 시작까지 기다린 시간을 남긴다(진행·대기 중 카드의 "대기 N" 과 같은 모양).
    // 서버가 작업 ID 의 접수 시각으로 계산한 근사값이다.
    if (r.wait_sec !== null && r.wait_sec !== undefined && Number(r.wait_sec) >= 1) {
      meta.appendChild(labeledMeta("대기", formatDuration(Number(r.wait_sec)), "elapsed", "접수부터 실행 시작까지 기다린 시간(오차 약 10초): " + r.wait_sec + "초"));
    }
    if (r.attempts && Number(r.attempts) > 1) { meta.appendChild(metaItem("시도 " + r.attempts + "회")); }
    // 위임 경로: 대부분은 inbox 파일 위임(bridge)이라 따로 표시하지 않고, Claude 가 antigravity MCP 로 직접 부른 기록만 "MCP" 로 표시한다.
    if (viaMcp(r)) { meta.appendChild(metaItem("MCP", "src-mcp", "위임 경로: Claude 가 antigravity MCP 로 직접 호출한 기록")); }
    if ((r.account && String(r.account).toLowerCase() !== "primary") || r.fallback_from) {
      var rAcctWrap = document.createElement("span");
      rAcctWrap.innerHTML = usageAccountBadgeHtml(r.account, r.fallback_from);
      if (rAcctWrap.firstElementChild) {
        if (r.account_note) rAcctWrap.firstElementChild.title = String(r.account_note);
        meta.appendChild(rAcctWrap.firstElementChild);
      }
    }
    card.appendChild(meta);

    var rCtx = (r && r._liveCtx) || recordContexts[recordContextKey(r)] || null;
    var rSrc = (r.src_model || r.src_client) ? { model: r.src_model || "", effort: r.src_effort || "", client: r.src_client || "" } : null;
    var modelRow = buildModelRow(modelName, r.claude_model, r.claude_effort, false, rAgent, r.tried_models, isOk, rCtx && rCtx.models, rSrc);
    if (modelRow) {
      modelRow.setAttribute("data-model-task", tokenRecordKey(r));
      card.appendChild(modelRow);
    }

    var dataKey = card.getAttribute("data-key");
    var metaToggleBtn = attachMetaMore(card, dataKey, r.task_id, [
      buildSessionMeta(r.session, r.session_id, r.task_id)   // 식별 줄: 모든 카드에(세션이 없으면 "세션 없음")
    ]);

    var diag = (typeof qaDiagnoseItem === "function") ? qaDiagnoseItem(r) : null;
    if (diag) {
      var stLower = String(r.status || "").trim().toLowerCase();
      var diagBox = document.createElement("div");
      diagBox.className = "qa-diag-box" + (stLower === "cancelled" ? " is-cancelled" : (stLower === "blocked" ? " is-blocked" : ""));
      diagBox.innerHTML =
        '<div class="qa-diag-head"><span class="qa-diag-label">' + escapeHtml(diag.label || diag.category || "진단") + '</span></div>' +
        (diag.root_cause ? '<div class="qa-diag-cause">' + escapeHtml(diag.root_cause) + '</div>' : '') +
        (diag.recommendation ? '<div class="qa-diag-rec">권장: ' + escapeHtml(diag.recommendation) + '</div>' : '');
      card.appendChild(diagBox);
    }

    var dq = document.createElement("details");
    dq.className = "qa q";
    var sq = document.createElement("summary");
    var qBadge = document.createElement("span");
    qBadge.className = "qa-type-badge q-type";
    qBadge.textContent = "질문";
    sq.appendChild(qBadge);

    var qKw = extractQuestionKeyword(splitTruncationNote(r.question).text);   // 잘림 안내 문구는 요약 줄에 보이지 않게 뗀다
    if (qKw) {
      var qKwSpan = document.createElement("span");
      qKwSpan.className = "qa-preview-keyword";
      qKwSpan.textContent = qKw;
      qKwSpan.title = qKw;
      sq.appendChild(qKwSpan);
    }
    dq.appendChild(sq);

    var qb = document.createElement("div");
    qb.className = "body";
    var qImgInfo = extractImagesFromText(r.question);
    var qGallery = createImageGallery(qImgInfo.images, qImgInfo.cwd);
    if (qGallery) qb.appendChild(qGallery);
    var qContent = document.createElement("div");
    qContent.className = "qa-content";
    qb.appendChild(qContent);
    renderQaText(qContent, r.question, qImgInfo.cwd, r, "question");
    dq.appendChild(qb);
    card.appendChild(dq);

    meta.appendChild(metaToggleBtn);
    meta.appendChild(buildProcessButton(dataKey, recordProcessOpts(r, qImgInfo.cwds)));

    var da = document.createElement("details");
    da.className = "qa a";
    var sa = document.createElement("summary");
    var aBadge = document.createElement("span");
    aBadge.className = "qa-type-badge a-type";
    aBadge.textContent = "답변";
    sa.appendChild(aBadge);

    var aKw = extractAnswerKeyword(splitTruncationNote(r.answer).text);
    if (aKw) {
      var aKwSpan = document.createElement("span");
      aKwSpan.className = "qa-preview-keyword";
      aKwSpan.textContent = aKw;
      aKwSpan.title = aKw;
      sa.appendChild(aKwSpan);
    }
    da.appendChild(sa);

    var ab = document.createElement("div");
    ab.className = "body";
    var aImgInfo = extractImagesFromText(r.answer);
    var aGallery = createImageGallery(aImgInfo.images, qImgInfo.cwd || aImgInfo.cwd);
    if (aGallery) ab.appendChild(aGallery);
    var aContent = document.createElement("div");
    aContent.className = "qa-content";
    ab.appendChild(aContent);
    renderQaText(aContent, r.answer, qImgInfo.cwd || aImgInfo.cwd, r, "answer");
    da.appendChild(ab);
    card.appendChild(da);

    return card;
  }

  // 마지막 활동이 이 시간(초) 이상 없으면 "조용함" 표시로 바꾼다. 워처의 멈춤 판정(300초)보다 먼저 눈치챌 수 있게 짧게 둔다.
  var PROGRESS_QUIET_SEC = 120;

  // 진행 중인 위임의 진행 상황 줄. 서버가 agy 대화 기록에서 읽은 단계/최근 동작/마지막 활동 시각을 보여 준다.
  // agy 도구 이름 -> 한글 설명. 영어 라벨(Checking target directory 등)만으로는 무슨 일을 하는지 알 수 없어서 덧붙인다.
  // agy 대화 기록 131개, 도구 호출 2,287건에서 나온 12종이다. 모르는 도구는 이름을 그대로 보인다.
  function progressToolLabel(name) {
    var m = {
      run_command: "명령 실행",
      view_file: "파일 읽기",
      read_file: "파일 읽기",
      write_to_file: "파일 쓰기",
      write_file: "파일 쓰기",
      replace_file_content: "파일 일부 수정",
      edit_file: "파일 일부 수정",
      list_dir: "폴더 목록 보기",
      find_by_name: "파일 이름 찾기",
      grep_search: "파일 내용 검색",
      search_web: "웹 검색",
      read_url_content: "웹 페이지 읽기",
      manage_task: "작업 관리",
      schedule: "잠시 대기",
      generate_image: "이미지 생성",
      swarm: "스웜 관리",
      post_message: "스웜 보드 게시",
      read_board: "스웜 보드 읽기",
      swarm_wait: "스웜 대기",
      run_workflow: "워크플로 실행",
      invoke_subagent: "서브에이전트 호출",
      manage_subagents: "서브에이전트 관리",
      send_message: "에이전트 메시지",
      exit_plan_mode: "계획 완료"
    };
    if (!name) return "";
    return Object.prototype.hasOwnProperty.call(m, name) ? m[name] : name;
  }

  // "지금:" 줄. 한글 도구 설명 + 실제 대상(명령, 파일, 폴더) + agy 가 붙인 영어 라벨 순서로 보여 준다.
  // 예) 지금: 명령 실행 Get-Location · Checking target directory
  // 서버가 tool/detail 을 주지 않는 옛 서버면 영어 라벨만 보인다(기존 동작).
  function buildProgressActionHtml(pg, cwd) {
    var tool = progressToolLabel(pg.tool);
    if (!tool && !pg.detail && !pg.action && !pg.say && !pg.thinking) return "";
    var pieces = [];
    if (tool) pieces.push('<span class="pg-tool">' + escapeHtml(tool) + (pg.background ? ' (백그라운드)' : '') + '</span>');
    if (pg.detail) pieces.push('<span class="pg-detail">' + escapeHtml(shortenPathsForCwd(pg.detail, cwdListOf(cwd).length ? cwd : pg.cwd)) + '</span>');
    if (pg.action) pieces.push('<span class="pg-label">' + ((tool || pg.detail) ? '· ' : '') + escapeHtml(pg.action) + '</span>');
    var html = '지금: ' + pieces.join(' ');
    // 줄이 길어 잘리면 마우스를 올려 전체를 본다
    var tip = [];
    if (pg.tool) tip.push("도구: " + pg.tool);
    if (pg.detail) tip.push("대상: " + pg.detail);
    if (pg.cwd) tip.push("실행 폴더: " + pg.cwd);
    if (pg.action) tip.push("agy 가 붙인 설명: " + pg.action);
    return '<div class="pg-action" title="' + escapeHtml(tip.join("\n")) + '">' + html + '</div>' +
      buildNarrationHtml("pg", pg.say, pg.thinking);
  }

  function buildProgressHtml(pg, cwd) {
    if (!pg) return "";
    var parts = [];
    if (pg.step != null) {
      parts.push('<span class="pg-step" title="' +
        escapeHtml("agy 대화 기록의 번호입니다. 도구를 부르는 것과 그 결과가 각각 한 단계로 세어져서, 실제로 한 일의 수보다 큽니다.") +
        '">' + escapeHtml(String(pg.step)) + '단계 진행</span>');
    }
    if (pg.last_activity_ms) {
      parts.push('<span class="pg-idle" data-ms="' + escapeHtml(String(pg.last_activity_ms)) + '">' +
        formatDuration((Date.now() - pg.last_activity_ms) / 1000) + ' 전 활동</span>');
    }
    var action = buildProgressActionHtml(pg, cwd);
    return '<div class="pending-progress">' + (parts.length ? '<div class="pg-line">' + parts.join('<span class="pg-sep">·</span>') + '</div>' : "") + action + '</div>';
  }

  // ==========================================================================
  // 진행 상태: 위임·핸드오프 작업이 지금 "진행 중인지, 조용한지, 멈춘 것으로 보이는지, 끝났는지"를 한 곳에서 판정해 같은 모양으로 보인다.
  // 판정은 서버가 준 값(마지막 활동 시각, 멈춤 기준 stall_seconds, 백그라운드 대기 waiting_background, 실행 표시만 남은 interrupted)과
  // 워처가 떠 있는지로 한다. 시각은 화면이 1초마다 다시 계산해서, 서버 응답이 없는 사이에도 "조용함"이 "멈춘 것으로 보임"으로 넘어간다.
  // ==========================================================================

  var HEALTH_STALL_DEFAULT_SEC = 300;   // 서버가 기준을 안 주면 워처의 기본값(AGY_STALL_SECONDS)

  function watcherAliveNow() {
    return systemStatus ? Boolean(systemStatus.watcherAlive) : null;   // 아직 모르면 null
  }

  function healthStallMinutes(sec) {
    var m = Math.round(sec / 6) / 10;   // 소수 한 자리
    return (m === Math.floor(m) ? String(m) : m.toFixed(1)) + "분";
  }

  // 위임 작업 하나(/api/delegate/pending 의 항목)의 상태. 반환 { kind: running|quiet|stalled|queued, label, detail, idleSec }
  function delegateRunHealth(p, nowMs, watcherAlive) {
    var pg = (p && p.progress) || {};
    var startedMs = p && p.started_at ? Date.parse(String(p.started_at).replace(" ", "T")) : NaN;
    var lastMs = pg.last_activity_ms ? Number(pg.last_activity_ms) : (isNaN(startedMs) ? 0 : startedMs);
    var idle = lastMs ? Math.max(0, (nowMs - lastMs) / 1000) : 0;
    var idleText = lastMs ? "마지막 활동 " + formatDuration(idle) + " 전" : "";
    var stall = Number(pg.stall_seconds) > 0 ? Number(pg.stall_seconds) : HEALTH_STALL_DEFAULT_SEC;
    var join = function (parts) { return parts.filter(Boolean).join(" · "); };

    if (p && p.interrupted) {
      return { kind: "stalled", label: "중단된 것으로 보임", idleSec: idle,
        detail: join(["작업자 프로세스가 사라졌습니다", idleText, watcherAlive === false ? "워처도 꺼져 있습니다" : ""]) };
    }
    if (!p || p.state !== "processing") {
      return { kind: "queued", label: "대기 중", idleSec: 0,
        detail: watcherAlive === false ? "워처가 꺼져 있어 시작하지 못하고 있습니다" : "" };
    }
    if (watcherAlive === false && idle >= 60) {
      return { kind: "stalled", label: "멈춘 것으로 보임", idleSec: idle, detail: join(["워처가 꺼져 있습니다", idleText]) };
    }
    var probe = p && p.probe_state ? String(p.probe_state).trim() : "";
    var askCount = p && Number(p.ask_count) > 0 ? Number(p.ask_count) : 0;
    if (probe === "checking") {
      return { kind: "quiet", label: "확인 중", idleSec: idle, detail: healthStallMinutes(stall) + " 넘게 새 단계가 없어 생각 중인지 확인하고 있습니다" };
    }
    if (probe === "thinking") {
      return { kind: "running", label: "생각 중", idleSec: idle, detail: "모델 응답을 기다리는 중" };
    }
    if (probe === "tool running") {
      return { kind: "running", label: "명령 실행 중", idleSec: idle, detail: "" };
    }
    if (probe === "asked") {
      var askNum = askCount > 0 ? askCount : 1;
      return { kind: "quiet", label: "진행 상황 묻는 중 (" + askNum + "/2)", idleSec: idle, detail: "멈춘 실행을 끝내고 같은 대화에 이어서 물었습니다" };
    }
    if (idle >= stall && !pg.waiting_background) {
      return { kind: "stalled", label: "멈춘 것으로 보임", idleSec: idle, detail: join([idleText, healthStallMinutes(stall) + " 넘게 새 단계가 없습니다"]) };
    }
    if (pg.waiting_background && idle >= PROGRESS_QUIET_SEC) {
      return { kind: "running", label: "진행 중", idleSec: idle, detail: join(["오래 걸리는 명령이 끝나기를 기다리는 중", idleText]) };
    }
    if (idle >= PROGRESS_QUIET_SEC) {
      var grace = Number(pg.stall_grace_seconds) > 0 ? Number(pg.stall_grace_seconds) : stall;
      return { kind: "quiet", label: "조용함", idleSec: idle, detail: join([idleText, healthStallMinutes(stall) + " 넘게 조용하면 생각 중인지 확인하고, " + healthStallMinutes(stall + grace) + "이면 같은 대화에 진행 상황을 묻습니다"]) };
    }
    return { kind: "running", label: "진행 중", idleSec: idle, detail: "" };   // 단계 수·마지막 활동은 바로 아래 진행 줄(pg-line)에 있어 되풀이하지 않는다
  }

  // 핸드오프 메시지가 위임된 작업 번호. 같은 메시지를 다시 위임한 적이 있으면 아직 안 끝난 것, 없으면 가장 마지막 것.
  function handoffDispatchOf(channelData, num) {
    var list = channelData && channelData.auto && Array.isArray(channelData.auto.dispatches) ? channelData.auto.dispatches : [];
    var pick = null;
    for (var i = 0; i < list.length; i++) {
      var d = list[i];
      if (!d || String(d.num) !== String(num) || !d.taskId) { continue; }
      if (!pick || !d.done || pick.done) { pick = d; }   // 안 끝난 것을 우선하고, 같으면 나중 것
    }
    return pick;
  }

  // 채널 이름 -> 위임 작업 ID 에 들어가는 이름(펌프의 ConvertTo-HandoffSafeName 과 같은 규칙: 이름에 못 쓰는 글자는 -, 앞뒤 - 제거, 40자).
  function handoffSafeChannelName(name) {
    var s = String(name == null ? "" : name).replace(/[^A-Za-z0-9가-힣_-]+/g, "-").replace(/^-+|-+$/g, "");
    if (!s) { s = "channel"; }
    if (s.length > 40) { s = s.slice(0, 40).replace(/^-+|-+$/g, ""); }
    return s;
  }

  // 메시지 번호를 처리한 위임 작업 ID. 채널 상태의 위임 연결(auto.dispatches, 최근 30건)에서 찾고, 밀려났으면 위임 기록에서
  // 작업 ID 모양(handoff_<채널>_<번호>_<시각>)으로 찾는다(records 는 최근 것이 앞). 없으면 "".
  function handoffTaskIdOf(channelData, channelName, num, records) {
    if (num == null || num === "") { return ""; }
    var disp = handoffDispatchOf(channelData, num);
    if (disp && disp.taskId) { return String(disp.taskId); }
    var prefix = "handoff_" + handoffSafeChannelName(channelName) + "_" + String(num) + "_";
    var list = Array.isArray(records) ? records : [];
    for (var i = 0; i < list.length; i++) {
      var id = list[i] && list[i].task_id ? String(list[i].task_id) : "";
      if (id.indexOf(prefix) === 0) { return id; }
    }
    return "";
  }

  // 끝난 메시지 카드에 "과정" 버튼을 붙일 위임 작업 ID(위임 기록이 있는 것만). 없으면 "".
  //   Claude 가 보낸(c2a) 메시지가 처리됨·확인함·보류일 때: 그 메시지를 처리한 위임.
  //   agy 가 쓴 회신(a2c): 그 회신이 답한 메시지(답장대상)를 처리한 위임.
  //   보냄·읽음인 c2a 는 진행 줄(handoffLiveOf)이 과정 버튼을 맡는다.
  function handoffFinishedTaskId(channelData, channelName, m, records) {
    if (!m) { return ""; }
    var num = null;
    if (m.dir === "c2a" && (m.status === "처리됨" || m.status === "확인함" || m.status === "보류")) { num = m.num; }
    else if (m.dir === "a2c" && m.replyTo) { num = m.replyTo; }
    else { return ""; }
    var id = handoffTaskIdOf(channelData, channelName, num, records);
    if (!id) { return ""; }
    var list = Array.isArray(records) ? records : [];
    for (var i = 0; i < list.length; i++) { if (list[i] && list[i].task_id === id) { return id; } }
    return "";
  }

  // 워처 펌프(handoff-pump.ps1 의 Get-HandoffMaxAgeHours)가 자동 위임하는 메시지의 최대 나이 기본값(시간). AGY_HANDOFF_MAX_AGE_HOURS 로 바꾼 PC 에서는 안내가 어긋날 수 있다.
  var HANDOFF_AUTO_MAX_AGE_HOURS = 2;

  // 메시지의 보낸 시각(밀리초). 목록의 시각은 "2026-09-22 15:15" 처럼 이 PC 의 현지 시각이다. 못 읽으면 0.
  function handoffMessageTimeMs(msg) {
    var t = msg && msg.time ? String(msg.time).trim() : "";
    var m = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})/.exec(t);
    if (!m) { return 0; }
    var d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), 0, 0);
    var ms = d.getTime();
    return isNaN(ms) ? 0 : ms;
  }

  // 핸드오프 메시지 한 건의 진행 표시. Claude 가 보낸(c2a) 메시지가 보냄·읽음(또는 자동 처리 실패로 보류)일 때만 있다. 없으면 null.
  //   보냄: agy 가 아직 가져가지 않음(워처가 꺼져 있거나 자동 이어가기가 꺼져 있으면 그렇게 알린다)
  //   읽음: 위임됨 -> 위임 작업(pending)의 상태를 그대로. 작업이 끝났으면 "회신을 정리하는 중", 위임 기록이 없으면 확인 중
  //   반환 { kind, label, detail, taskId, pending(진행 중인 위임 항목 또는 null), canOpen(과정 창을 열 수 있는가) }
  function handoffLiveOf(channelData, msg, pendingList, records, watcherAlive, nowMs) {
    if (!msg || msg.dir !== "c2a") { return null; }
    var status = msg.status;
    if (status !== "보냄" && status !== "읽음") { return null; }
    var auto = channelData && channelData.auto;
    var disp = handoffDispatchOf(channelData, msg.num);

    if (status === "보냄" && !disp) {
      // 워처의 핸드오프 펌프는 보낸 지 HANDOFF_AUTO_MAX_AGE_HOURS 시간이 지난 메시지를 자동으로 위임하지 않는다(옛 요청을 뒤늦게 시키지 않으려는 안전장치).
      // 다른 이유(워처 꺼짐 등)로 기다리는 것처럼 보이지 않게, 먼저 이것부터 알린다.
      var sentMs = handoffMessageTimeMs(msg);
      if (sentMs && nowMs && (nowMs - sentMs) > HANDOFF_AUTO_MAX_AGE_HOURS * 3600000) {
        return { kind: "stalled", label: "자동 위임 안 됨", detail: "보낸 지 " + HANDOFF_AUTO_MAX_AGE_HOURS + "시간이 지난 메시지는 자동으로 agy 에게 넘기지 않습니다. 더 필요하면 새 메시지로 다시 보내고, 아니면 상태를 '보류'로 바꾸세요", taskId: "", pending: null, canOpen: false };
      }
      if (auto && auto.enabled === false) { return { kind: "queued", label: "아직 안 넘어감", detail: "이 채널은 자동 이어가기가 꺼져 있어 agy 가 가져가지 않습니다", taskId: "", pending: null, canOpen: false }; }
      if (auto && auto.halted) { return { kind: "stalled", label: "멈춤", detail: "자동 이어가기가 멈춰 있어 agy 에게 넘어가지 않았습니다", taskId: "", pending: null, canOpen: false }; }
      if (watcherAlive === false) { return { kind: "stalled", label: "가져가지 못함", detail: "워처가 꺼져 있습니다. 워처를 켜면 자동으로 이어집니다", taskId: "", pending: null, canOpen: false }; }
      return { kind: "queued", label: "agy 가 가져가기를 기다림", detail: "자동 이어가기가 켜져 있으면 몇 초 안에 agy 에게 넘어갑니다", taskId: "", pending: null, canOpen: false };
    }
    if (!disp) { return null; }   // 읽음인데 위임 기록이 없는 메시지(손으로 읽음으로 바꾼 것)

    var p = null;
    for (var i = 0; i < (pendingList || []).length; i++) { if (pendingList[i] && pendingList[i].task_id === disp.taskId) { p = pendingList[i]; break; } }
    if (p) {
      var h = delegateRunHealth(p, nowMs, watcherAlive);
      return { kind: h.kind, label: h.label, detail: h.detail, taskId: disp.taskId, pending: p, canOpen: true };
    }
    var rec = null;
    for (var j = 0; j < (records || []).length; j++) { if (records[j] && records[j].task_id === disp.taskId) { rec = records[j]; break; } }
    if (rec) {
      var ok = isOkStatus(rec);
      return { kind: ok ? "done" : "failed", label: ok ? "agy 작업 끝남" : "agy 작업 실패", detail: ok ? "회신 메시지를 정리하는 중입니다" : "회신 메시지에 실패 사유가 남습니다", taskId: disp.taskId, pending: null, canOpen: true };
    }
    if (watcherAlive === false) { return { kind: "stalled", label: "멈춘 것으로 보임", detail: "워처가 꺼져 있습니다", taskId: disp.taskId, pending: null, canOpen: false }; }
    return { kind: "queued", label: "상태 확인 중", detail: "위임한 작업이 대기열에도 기록에도 아직 보이지 않습니다", taskId: disp.taskId, pending: null, canOpen: false };
  }

  // 상태 표시 한 덩어리의 안쪽: 점 · 이름 · 설명. 카드 머리 배지와 별개로 설명까지 보이는 곳(진행 중 카드 본문, 핸드오프 줄, 과정 창)에서 쓴다.
  function healthInnerHtml(h) {
    return '<span class="live-dot" aria-hidden="true"></span><b class="live-label">' + escapeHtml(h.label) + '</b>' +
      (h.detail ? '<span class="live-detail">' + escapeHtml(h.detail) + '</span>' : '');
  }

  // 위임 작업 하나를 가리키는 상태 표시(배지·덩어리)를 1초마다 새로 계산해 고친다. 서버 응답이 없는 사이에도 시간이 흐르면 상태가 바뀌어야 해서다.
  function tickHealthElements() {
    var nodes = document.querySelectorAll("[data-health-task]");
    if (!nodes.length) { return; }
    var now = Date.now();
    var alive = watcherAliveNow();
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      var tid = el.getAttribute("data-health-task");
      var p = null;
      for (var k = 0; k < pendingItems.length; k++) { if (pendingItems[k] && pendingItems[k].task_id === tid) { p = pendingItems[k]; break; } }
      if (!p) { continue; }
      var h = delegateRunHealth(p, now, alive);
      if (el.classList.contains("badge")) {
        el.className = "badge " + healthBadgeClass(h.kind);
        el.textContent = h.label;
        el.title = h.detail;
      } else {
        el.setAttribute("data-kind", h.kind);
        var sig = h.label + "|" + h.detail;
        if (el.getAttribute("data-sig") !== sig) { el.innerHTML = healthInnerHtml(h); el.setAttribute("data-sig", sig); }
      }
      var cardEl = el.closest ? el.closest(".card.pending-card") : null;
      if (cardEl) { cardEl.setAttribute("data-health", h.kind); }
      var barEl = document.querySelector('.pending-progress-bar[data-health-bar-task="' + tid + '"]');
      if (barEl) {
        var nextBarState = getPendingBarState(h.kind, (p.state === "processing"), Boolean(p.interrupted));
        barEl.className = "pending-progress-bar " + nextBarState;
      }
    }
  }

  function getPendingBarState(healthKind, isProcessing, isInterrupted) {
    if (isInterrupted) return "idle";
    if (!isProcessing) return "idle";
    if (healthKind === "running" || healthKind === "active" || healthKind === "quiet") return "running";
    return "idle";
  }

  function healthBadgeClass(kind) {
    if (kind === "stalled") { return "status-pending-stalled"; }
    if (kind === "quiet") { return "status-pending-quiet"; }
    if (kind === "queued") { return "status-pending-queued"; }
    return "status-pending-processing";
  }

  // 대기 중인 작업이 왜 기다리는지 두 가지로 가른다(워처의 Test-TaskConflict / 동시 실행 수와 같은 규칙).
  //  - 같은 세션·폴더: 세션 이름이 같고(비어 있지 않고) 폴더가 겹치는 앞 작업이 있다. 폴더가 비어 있으면 겹치는 것으로 본다.
  //  - 동시 실행 수: 위 이유가 없는데도 기다리면 동시에 돌릴 수 있는 수가 찬 것이다.
  function pendingWaitReasonHtml(p) {
    function key(c) { return String(c || "").replace(/\//g, "\\").replace(/\\+$/, "").toLowerCase(); }
    function overlap(a, b) {
      var A = cwdListOf(a).map(key).filter(Boolean), B = cwdListOf(b).map(key).filter(Boolean);
      if (!A.length || !B.length) return true;
      for (var i = 0; i < A.length; i++) for (var j = 0; j < B.length; j++) {
        if (A[i] === B[j] || A[i].indexOf(B[j] + "\\") === 0 || B[j].indexOf(A[i] + "\\") === 0) return true;
      }
      return false;
    }
    var running = 0, blockers = [];
    for (var i = 0; i < pendingItems.length; i++) {
      var q = pendingItems[i];
      if (!q || q.task_id === p.task_id) continue;
      if (q.state === "processing") running++;
      var ahead = q.state === "processing" || String(q.created || "") < String(p.created || "");
      if (ahead && p.session && q.session === p.session && overlap(p.cwd, q.cwd)) blockers.push(q);
    }
    var out = [];
    if (blockers.length) {
      out.push('<b>같은 세션·폴더의 앞 작업</b> ' + blockers.length + '건이 먼저 끝나야 합니다(세션 ' + escapeHtml(p.session) + ').');
    }
    if (!blockers.length || running >= 5) {
      out.push('<b>동시에 돌릴 수 있는 수</b>가 찼습니다(지금 ' + running + '건 실행 중).');
    }
    return out.join("<br>");
  }

  function buildPendingCard(p, queueIndex) {
    var isProcessing = (p.state === "processing");
    var health = delegateRunHealth(p, Date.now(), watcherAliveNow());
    var card = document.createElement("div");
    card.className = "card pending-card" + (isProcessing ? " processing" : " queued") + (p.interrupted ? " interrupted" : "");
    card.setAttribute("data-key", "p:" + (p.task_id || ""));
    card.setAttribute("data-health", health.kind);

    var meta = document.createElement("div");
    meta.className = "meta";
    meta.appendChild(metaHead("실행"));
    meta.appendChild(labeledMeta("", String(p.created || "").replace(/^\d{4}-/, ""), "ts", "접수 시각 " + (p.created || "")));

    // 상태 배지는 진행 중 / 조용함 / 멈춘 것으로 보임 / 중단된 것으로 보임 / 대기 중 중 하나. 1초마다 tickHealthElements 가 다시 판정한다.
    var waitIcon = getCardWaitIcon(health.kind, isProcessing, Boolean(p.interrupted));
    var stateBadge = badge(healthBadgeClass(health.kind), health.label);
    if (waitIcon) {
      stateBadge.innerHTML = '<svg class="icon icon-wait" aria-hidden="true"><use href="#i-' + waitIcon + '"/></svg>' + escapeHtml(health.label);
    }
    stateBadge.title = health.detail;
    if (p.task_id && (isProcessing || p.interrupted)) { stateBadge.setAttribute("data-health-task", p.task_id); }
    meta.appendChild(stateBadge);

    if ((p.account && String(p.account).toLowerCase() !== "primary") || p.fallback_from) {
      var pAcctWrap = document.createElement("span");
      pAcctWrap.innerHTML = usageAccountBadgeHtml(p.account, p.fallback_from);
      if (pAcctWrap.firstElementChild) meta.appendChild(pAcctWrap.firstElementChild);
    }

    var pAgent = p.agent_model ? { model: p.agent_model, effort: p.agent_effort, type: p.agent_type, desc: p.agent_desc } : null;

    if (isProcessing) {
      var createdTime = parseLocalTime(p.created);
      var actualStartTime = p.started_at ? parseLocalTime(p.started_at) : createdTime;
      var startTime = actualStartTime || createdTime;

      // 1. 실제 실행 시간 라이브 배지 (1초마다 자동 갱신)
      if (startTime) {
        var elapsedSec = Math.max(0, (Date.now() - startTime.getTime()) / 1000);
        var live = labeledMeta("소요", formatDuration(elapsedSec), "elapsed live-elapsed", "실제 실행 경과 시간 (실행 시작: " + (p.started_at || p.created || "") + ")");
        live.setAttribute("data-start", String(startTime.getTime()));
        live.setAttribute("data-label-prefix", "");
        meta.appendChild(live);
      }

      // 2. 대기 시간 배지 (5초 이상 대기열에 있었던 경우 함께 표시)
      if (createdTime && actualStartTime) {
        var waitSec = Math.max(0, Math.floor((actualStartTime.getTime() - createdTime.getTime()) / 1000));
        if (waitSec >= 5) {
          var totalSec = Math.floor((Date.now() - createdTime.getTime()) / 1000);
          var waitBadge = labeledMeta("대기", formatDuration(waitSec), "wait-time", "대기열 대기: " + formatDuration(waitSec) + " (접수: " + (p.created || "") + " / 실행 시작: " + (p.started_at || "") + " / 총 경과: " + formatDuration(totalSec) + ")");
          meta.appendChild(waitBadge);
        }
      }

    } else if (!p.interrupted) {
      // 대기 중인 카드는 대기 경과 시간 표시
      var cTime = parseLocalTime(p.created);
      if (cTime) {
        var waitSec = Math.max(0, Math.floor((Date.now() - cTime.getTime()) / 1000));
        var waitLive = labeledMeta("대기 중", formatDuration(waitSec), "elapsed live-elapsed", "대기열 대기 시간 (접수: " + (p.created || "") + ")");
        waitLive.setAttribute("data-start", String(cTime.getTime()));
        waitLive.setAttribute("data-label-prefix", "");
        meta.appendChild(waitLive);
      }
    }

    // 대기·진행 중인 작업은 모두 inbox 파일 위임(bridge)이라 경로를 따로 표시하지 않는다(MCP 호출은 끝난 뒤에 기록으로만 남는다).
    card.appendChild(meta);

    var pendRec = pendingTokenRecord(p);
    var pSrc = (p.src_model || p.src_client) ? { model: p.src_model || "", effort: p.src_effort || "", client: p.src_client || "" } : null;
    var modelRow = buildModelRow(p.model, p.claude_model, p.claude_effort, false, pAgent, p.tried_models, true, pendRec._liveCtx && pendRec._liveCtx.models, pSrc);
    if (modelRow) card.appendChild(modelRow);

    var dataKey = card.getAttribute("data-key");
    var metaToggleBtn = attachMetaMore(card, dataKey, p.task_id, [
      buildSessionMeta(p.session, p.session_id, p.task_id)   // 식별 줄: 모든 카드에(세션이 없으면 "세션 없음")
    ]);

    var dq = document.createElement("details");
    dq.className = "qa q";
    var sq = document.createElement("summary");
    var qBadge = document.createElement("span");
    qBadge.className = "qa-type-badge q-type";
    qBadge.textContent = "질문";
    sq.appendChild(qBadge);

    var qKw = extractQuestionKeyword(p.question);
    if (qKw) {
      var qKwSpan = document.createElement("span");
      qKwSpan.className = "qa-preview-keyword";
      qKwSpan.textContent = qKw;
      sq.appendChild(qKwSpan);
    }
    dq.appendChild(sq);

    var qb = document.createElement("div");
    qb.className = "body";
    var qImgInfo = extractImagesFromText(p.question);
    var effCwds = cwdListOf(p.cwd);              // 서버가 준 폴더 목록(옛 서버는 문자열 하나)
    if (!effCwds.length) effCwds = qImgInfo.cwds;   // 없으면 질문 맨 위의 @cwd 줄들
    var effectiveCwd = effCwds[0] || "";            // 상대 경로 이미지는 첫 번째 폴더 기준으로 찾는다
    var qGallery = createImageGallery(qImgInfo.images, effectiveCwd);
    if (qGallery) qb.appendChild(qGallery);
    var qContent = document.createElement("div");
    qContent.className = "qa-content";
    renderBody(qContent, p.question, effectiveCwd);
    qb.appendChild(qContent);
    dq.appendChild(qb);
    card.appendChild(dq);

    meta.appendChild(metaToggleBtn);
    meta.appendChild(buildProcessButton(dataKey, pendingProcessOpts(p, effCwds)));

    var da = document.createElement("details");
    da.className = "qa a qa-pending-a";
    var sa = document.createElement("summary");
    var aBadge = document.createElement("span");
    aBadge.className = "qa-type-badge a-type";
    aBadge.textContent = "답변";
    sa.appendChild(aBadge);

    var aKwSpan = document.createElement("span");
    aKwSpan.className = "qa-preview-keyword";
    if (isProcessing) {
      aKwSpan.textContent = health.kind === "stalled" ? "멈춘 것으로 보임" : "응답을 만드는 중";
    } else if (p.interrupted) {
      aKwSpan.textContent = "중단된 것으로 보임";
    } else {
      if (waitIcon) {
        aKwSpan.innerHTML = '<svg class="icon icon-wait" aria-hidden="true"><use href="#i-' + waitIcon + '"/></svg>차례를 기다리는 중';
      } else {
        aKwSpan.textContent = "차례를 기다리는 중";
      }
    }
    sa.appendChild(aKwSpan);

    if (!waitIcon) {
      var barState = getPendingBarState(health.kind, isProcessing, Boolean(p.interrupted));
      var bar = document.createElement("span");
      bar.className = "pending-progress-bar " + barState;
      bar.setAttribute("aria-hidden", "true");
      if (p.task_id) { bar.setAttribute("data-health-bar-task", p.task_id); }
      var track = document.createElement("span");
      track.className = "pending-progress-track";
      bar.appendChild(track);
      sa.appendChild(bar);
    }

    da.appendChild(sa);

    var ab = document.createElement("div");
    ab.className = "body pending-body";
    var modelText = p.model ? " " + escapeHtml(p.model) + " 모델로" : "";
    var liveTask = (isProcessing || p.interrupted) && p.task_id ? ' data-health-task="' + escapeHtml(p.task_id) + '"' : '';
    ab.innerHTML = [
      (isProcessing || p.interrupted ? '<div class="live-health" data-kind="' + health.kind + '"' + liveTask + ' data-sig="' + escapeHtml(health.label + "|" + health.detail) + '">' + healthInnerHtml(health) + '</div>' : ''),
      '<div class="pending-status-wrap ' + escapeHtml(p.state) + '">',
      (isProcessing ? '  <span class="pending-spinner" aria-hidden="true"></span><span>agy가' + modelText + ' 응답을 만들고 있습니다. 끝나면 이 자리에 답변이 나옵니다.</span>' :
       p.interrupted ? '  <span>이 작업은 실행 중이라는 표시 파일만 남아 있고 작업자 프로세스는 없습니다. 아래는 마지막으로 확인된 진행 상황입니다.</span>' :
                      '  <span>' + pendingWaitReasonHtml(p) + ' 조건이 풀리면' + modelText + ' 자동으로 실행됩니다.</span>'),
      '</div>',
      ((isProcessing || p.interrupted) ? buildProgressHtml(p.progress, effCwds) : "")
    ].join("");
    da.appendChild(ab);
    card.appendChild(da);

    return card;
  }

  // ==========================================================================
  // 3. 에이전트 협의 메인 뷰 (Handoff Messages Thread Rendering)
  // ==========================================================================

  function renderHandoffView() {
    var tree = buildHandoffTree(handoffChannels, claudeTree);
    var titles = findHandoffNodeTitles(tree, currentHandoffProject, currentHandoffSession);

    var displayTitle = "전체 프로젝트";
    if (currentHandoffProject) {
      if (currentHandoffSession) {
        displayTitle = titles.sessionTitle;
      } else {
        displayTitle = titles.projectName;
      }
    }
    if (els.handoffCurrentProjectTitle) {
      els.handoffCurrentProjectTitle.textContent = displayTitle;
    }

    // BRIEF.md 요약 아코디언 카드: 연결 안 됨 아래의 채널 세션(c:<채널>)을 골랐을 때만 그 채널의 brief를 보인다.
    if (els.handoffBriefCard && els.briefProjectName && els.handoffBriefContent) {
      var isChannelSession = (currentHandoffProject === QA_UNLINKED && currentHandoffSession && currentHandoffSession.indexOf("c:") === 0);
      var briefChannelName = isChannelSession ? currentHandoffSession.slice(2) : "";
      var briefChannelData = briefChannelName ? handoffChannels[briefChannelName] : null;

      if (briefChannelData && briefChannelData.brief && briefChannelData.brief.trim()) {
        els.briefProjectName.textContent = briefChannelData.name || briefChannelName;
        renderMarkdownBody(els.handoffBriefContent, briefChannelData.brief);
        els.handoffBriefCard.style.display = "block";
      } else {
        els.handoffBriefCard.style.display = "none";
      }
    }

    renderHandoffMessages();
  }

  function toggleHandoffMessage(cardEl, channel, msg, fileName) {
    var bodyEl = cardEl.querySelector(".handoff-card-body");
    if (!bodyEl) return;
    var headerEl = cardEl.querySelector(".handoff-card-header");
    var num = msg && msg.num != null ? msg.num : "";
    var openKey = channel + "/" + num;
    var isOpen = (bodyEl.style.display !== "none");
    if (isOpen) {
      bodyEl.style.display = "none";
      cardEl.classList.remove("is-open");
      if (headerEl) headerEl.setAttribute("aria-expanded", "false");
      delete openHandoffNums[openKey];
      return;
    }
    bodyEl.style.display = "block";
    cardEl.classList.add("is-open");
    if (headerEl) headerEl.setAttribute("aria-expanded", "true");
    openHandoffNums[openKey] = true;

    if (bodyEl.dataset.loaded === "true") return;

    if (!fileName) {
      fileName = handoffMsgFileOf(msg, handoffChannels[channel]);
    }
    if (!fileName) {
      bodyEl.innerHTML = '<p class="empty">메시지 파일(msg/' + escapeHtml(num) + '-*.md)을 찾을 수 없습니다.</p>';
      bodyEl.dataset.loaded = "true";
      return;
    }

    var cacheKey = channel + "/" + fileName;
    if (handoffMessageCache[cacheKey]) {
      renderMarkdownBody(bodyEl, handoffMessageCache[cacheKey]);
      bodyEl.dataset.loaded = "true";
      return;
    }

    bodyEl.innerHTML = '<div class="handoff-card-body-loading">메시지 본문을 불러오는 중...</div>';
    fetchText("/api/handoff/message?project=" + encodeURIComponent(channel) + "&file=" + encodeURIComponent(fileName))
      .then(function (markdown) {
        handoffMessageCache[cacheKey] = markdown;
        if (openHandoffNums[openKey]) {
          renderMarkdownBody(bodyEl, markdown);
          bodyEl.dataset.loaded = "true";
        }
      })
      .catch(function (err) {
        bodyEl.innerHTML = '<p class="empty">본문 로드 실패: ' + escapeHtml(err.message) + '</p>';
      });
  }

  function renderMarkdownBody(targetEl, markdown) {
    try {
      // 메시지 머리말(--- 번호/방향/시각/제목 ---)은 카드 머리에 이미 표시하므로 본문에서 뺀다.
      // 그대로 두면 marked 가 구분선과 큰 제목으로 그려 버린다.
      var body = String(markdown || "").replace(/^﻿?---\r?\n[\s\S]*?\r?\n---\r?\n/, "");
      targetEl.innerHTML = renderMarkdownWithMath(body);
      postProcessMarkdownElements(targetEl);
    } catch (e) {
      targetEl.innerHTML = "<pre>" + escapeHtml(markdown) + "</pre>";
    }
  }

  // 머리 범례와 방향 필터의 이름을 지금 보는 메시지들의 최근 모델로(없으면 Claude/agy).
  function updateHandoffPartyLabels(items) {
    var msgs = (items || []).map(function (it) {
      var data = it && it.channel ? handoffChannels[it.channel] : null;
      return data ? handoffEnrichMessages([it.msg], handoffDispatchResolver(data, allItems, pendingItems))[0] : it.msg;
    });
    var latest = handoffLatestNames(msgs);
    var claudeName = latest.claude || "Claude";
    var agyName = latest.agy || "agy";
    if (els.handoffLegendClaude) els.handoffLegendClaude.textContent = claudeName + " 보냄";
    if (els.handoffLegendAgy) els.handoffLegendAgy.textContent = agyName + " 보냄";
    if (els.handoffDirFilter) {
      for (var i = 0; i < els.handoffDirFilter.options.length; i++) {
        var o = els.handoffDirFilter.options[i];
        if (o.value === "c2a") o.textContent = claudeName + " → " + agyName;
        else if (o.value === "a2c") o.textContent = agyName + " → " + claudeName;
      }
    }
  }

  // 자동 이어가기 상태 줄: 보는 메시지가 속한 채널마다 한 줄. 상태는 /api/handoff/project 의 auto.
  function handoffAutoText(auto, nowMs) {
    if (!auto) return null;
    if (!auto.enabled) return { state: "꺼짐", detail: "이 채널은 agy 가 자동으로 답하지 않습니다.", kind: "off" };
    if (auto.halted) return { state: "멈춤 · 사용자 확인 필요", detail: auto.haltedReason || "자동 왕복 한도에 도달했습니다.", kind: "halted" };
    var flight = Array.isArray(auto.inFlight) && auto.inFlight.length ? auto.inFlight[0] : null;
    if (flight) {
      var started = Date.parse(String(flight.at || "").replace(" ", "T"));
      var mins = isNaN(started) ? null : Math.max(0, Math.round(((nowMs || Date.now()) - started) / 60000));
      return { state: "켜짐 · agy 처리 중", detail: "#" + flight.num + (mins == null ? "" : " · " + mins + "분 경과") + " · 왕복 " + auto.rounds + "/" + auto.maxRounds, kind: "busy" };
    }
    return { state: "켜짐", detail: "왕복 " + auto.rounds + "/" + auto.maxRounds + " (최근 " + auto.windowMinutes + "분) · Claude 메시지에 agy 가 자동으로 답합니다.", kind: "on" };
  }

  // 지금 보는 메시지들이 속한 채널마다 자동 이어가기 상태 한 줄. 채널이 여럿이면 멈춤 > 처리 중 > 꺼짐 > 켜짐 순으로, 최대 limit 줄만 보이고 나머지는 개수만 알린다.
  function handoffAutoRows(items, channelsMap, nowMs, limit) {
    var order = [];
    var seen = {};
    (items || []).forEach(function (it) { if (it && it.channel && !seen[it.channel]) { seen[it.channel] = true; order.push(it.channel); } });
    var rank = { halted: 0, busy: 1, off: 2, on: 3 };
    var rows = [];
    order.forEach(function (ch, i) {
      var data = channelsMap ? channelsMap[ch] : null;
      var txt = data ? handoffAutoText(data.auto, nowMs) : null;
      if (txt) rows.push({ channel: ch, kind: txt.kind, state: txt.state, detail: txt.detail, enabled: !!data.auto.enabled, order: i });
    });
    if (rows.length > 1) {
      rows.sort(function (x, y) { return (rank[x.kind] - rank[y.kind]) || (x.order - y.order); });
    }
    var max = limit > 0 ? limit : 5;
    return { rows: rows.slice(0, max), hidden: Math.max(0, rows.length - max), multi: rows.length > 1 };
  }

  function renderHandoffAutoBar(items) {
    if (!els.handoffAutoBar) return;
    var res = handoffAutoRows(items, handoffChannels, Date.now(), 5);
    if (res.rows.length === 0) { els.handoffAutoBar.style.display = "none"; els.handoffAutoBar.innerHTML = ""; return; }
    var html = res.rows.map(function (r) {
      return '<div class="auto-bar" data-channel="' + escapeHtml(r.channel) + '" data-kind="' + r.kind + '">' +
        (res.multi ? '<span class="auto-channel">' + escapeHtml(r.channel) + '</span>' : "") +
        '<span class="auto-state">자동 이어가기 · ' + escapeHtml(r.state) + '</span>' +
        '<span class="auto-detail">' + escapeHtml(r.detail) + '</span>' +
        '<span class="auto-actions">' +
        (r.kind === "halted" ? '<button type="button" class="text-btn" data-act="reset">한도 초기화</button>' : "") +
        '<button type="button" class="text-btn" data-act="' + (r.enabled ? "off" : "on") + '">' + (r.enabled ? "끄기" : "켜기") + '</button>' +
        '</span></div>';
    }).join("");
    if (res.hidden > 0) html += '<div class="auto-more">외 ' + res.hidden + '개 채널은 채널을 골라 보면 나옵니다.</div>';
    els.handoffAutoBar.innerHTML = html;
    els.handoffAutoBar.style.display = "";
  }

  function postHandoffAuto(channel, action, rowEl) {
    if (!channel) return;
    fetch("/api/handoff/auto?name=" + encodeURIComponent(channel) + "&action=" + encodeURIComponent(action), { method: "POST", headers: { "X-Samjil-Viewer": "1" } })
      .then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return loadHandoffProjects(true);
      })
      .catch(function (err) {
        var d = rowEl ? rowEl.querySelector(".auto-detail") : null;
        if (d) d.textContent = "요청에 실패했습니다: " + err.message;
      });
  }

  // 핸드오프 메시지 카드 머리 아래의 진행 줄: 보냄·읽음 상태의 c2a 가 지금 어디쯤인지(상태 · 지금 하는 일 · 과정 버튼). 해당 없으면 null.
  function handoffLiveFor(channel, m) {
    var live = handoffLiveOf(handoffChannels[channel], m, pendingItems, allItems, watcherAliveNow(), Date.now());
    return live;
  }

  function handoffLiveSig(live) {
    if (!live) { return ""; }
    var pg = (live.pending && live.pending.progress) || {};
    return JSON.stringify([live.kind, live.label, live.taskId, live.canOpen, pg.step, pg.last_activity_ms, pg.tool, pg.detail, pg.say, pg.thinking, live.pending ? live.pending.state : ""]);
  }

  function buildHandoffLiveEl(channel, m, live) {
    var el = document.createElement("div");
    el.className = "handoff-live";
    el.setAttribute("data-channel", channel);
    el.setAttribute("data-num", m.num);
    el.setAttribute("data-sig", handoffLiveSig(live));

    var top = document.createElement("div");
    top.className = "handoff-live-top";
    var h = document.createElement("div");
    h.className = "live-health";
    h.setAttribute("data-kind", live.kind);
    h.setAttribute("data-sig", live.label + "|" + live.detail);
    if (live.pending && live.taskId) { h.setAttribute("data-health-task", live.taskId); }
    h.innerHTML = healthInnerHtml(live);
    top.appendChild(h);
    if (live.canOpen && live.taskId) {
      var key = "p:" + live.taskId;
      var src = findProcessSource(key);
      top.appendChild(buildProcessButton(key, src ? src.opts : { steps: null, waiting: true }));
    }
    el.appendChild(top);

    if (live.pending && live.pending.progress) {
      var wrap = document.createElement("div");
      wrap.innerHTML = buildProgressHtml(live.pending.progress, cwdListOf(live.pending.cwd));
      while (wrap.firstChild) { el.appendChild(wrap.firstChild); }
    }
    return el;
  }

  // 새로 불러온 대기열로 진행 줄을 제자리에서 고친다(카드 전체를 다시 그리지 않아 펼친 본문과 스크롤이 그대로다). 줄이 새로 생기거나 사라져야 하면 다시 그린다.
  function refreshHandoffLive() {
    if (currentNav !== "handoff" || !els.handoffCards) { return; }
    var cards = els.handoffCards.querySelectorAll(".handoff-card");
    var needRender = false;
    for (var i = 0; i < cards.length; i++) {
      var card = cards[i];
      var ch = card.dataset.channel, num = card.dataset.num;
      var data = handoffChannels[ch];
      var msg = null;
      if (data && Array.isArray(data.messages)) {
        for (var k = 0; k < data.messages.length; k++) { if (String(data.messages[k].num) === String(num)) { msg = data.messages[k]; break; } }
      }
      // 끝난 메시지의 "과정" 버튼은 위임 기록이 늦게 들어오면 나중에 생긴다: 있어야 하는데 없거나 그 반대면 다시 그린다
      var wantDone = msg ? handoffFinishedTaskId(data, ch, msg, allItems) : "";
      var hasDone = Boolean(card.querySelector(":scope > .handoff-card-header .proc-open"));
      if (Boolean(wantDone) !== hasDone) { needRender = true; break; }
      var live = msg ? handoffLiveFor(ch, msg) : null;
      var cur = card.querySelector(":scope > .handoff-live");
      if (!live && !cur) { continue; }
      if (!live || !cur) { needRender = true; break; }
      if (cur.getAttribute("data-sig") !== handoffLiveSig(live)) {
        card.replaceChild(buildHandoffLiveEl(ch, msg, live), cur);
      }
    }
    if (needRender) { renderHandoffMessages(); }
  }

  function renderHandoffMessages() {
    if (!els.handoffCards) return;

    var items = handoffMessagesOf(handoffChannels, claudeTree, currentHandoffProject, currentHandoffSession);
    updateHandoffPartyLabels(items);
    renderHandoffAutoBar(items);

    var q = (els.handoffSearch ? els.handoffSearch.value : "").trim().toLowerCase();
    var dirFilter = els.handoffDirFilter ? els.handoffDirFilter.value : "";
    var statusFilter = els.handoffStatusFilter ? els.handoffStatusFilter.value : "";

    var filteredItems = items.filter(function (it) {
      var m = it.msg;
      if (!m) return false;
      if (dirFilter && m.dir !== dirFilter) return false;
      if (statusFilter && m.status !== statusFilter) return false;
      if (q) {
        var match = (m.num && String(m.num).toLowerCase().indexOf(q) >= 0) ||
                    (m.title && m.title.toLowerCase().indexOf(q) >= 0) ||
                    (m.time && m.time.indexOf(q) >= 0) ||
                    (m.status && m.status.indexOf(q) >= 0);
        if (!match) return false;
      }
      return true;
    });

    if (els.handoffCurrentProjectCount) {
      els.handoffCurrentProjectCount.textContent = "메시지 " + filteredItems.length + "개";
    }

    var sortedItems = filteredItems.slice().reverse();

    if (sortedItems.length === 0) {
      if (items.length === 0) {
        els.handoffCards.innerHTML = '<p class="empty">표시할 메시지가 없습니다.</p>';
      } else {
        els.handoffCards.innerHTML = '<p class="empty">조건에 일치하는 핸드오프 메시지가 없습니다.</p>';
      }
      updateTopbarMeta();
      return;
    }

    var frag = document.createDocumentFragment();
    sortedItems.forEach(function (it) {
      var m = it.msg;
      var channel = it.channel;
      var fileName = it.file;
      var openKey = channel + "/" + m.num;

      var card = document.createElement("div");
      var party = dirParty(m.dir);
      card.className = "handoff-card" + (party ? " from-" + party : "");
      card.dataset.num = m.num;
      card.dataset.channel = channel;

      // agy 가 쓴 회신(a2c)에는 그 회신을 만든 호출(답장대상 c2a)이 쓴 토큰을 보인다. Claude 쪽 사용량은 채널에 기록이 없어 보이지 않는다.
      var usageText = (m.dir === "a2c" && m.replyTo) ? handoffUsageText(handoffUsageFor(channel)[m.replyTo]) : null;
      // Claude 가 보낸 c2a 에는 그 메시지를 만든 Claude 호출의 사용량(근사)을 보인다. 값은 세션 기록에서 서버가 읽어 오고, 오기 전에는 칩이 없다가 도착하면 다시 그린다.
      var claudeText = claudeUsageText(claudeUsageFor(channel, m));

      // [#번호][제목 / 보낸 쪽 → 받는 쪽][토큰, 시각, 상태 진행 표시]
      var header = document.createElement("div");
      header.className = "handoff-card-header";
      header.innerHTML = [
        '<span class="handoff-num">#' + escapeHtml(m.num) + '</span>',
        '<div class="handoff-card-header-left">',
        '  <span class="handoff-title" title="' + escapeHtml(m.title || "") + '"><span class="handoff-channel">' + escapeHtml(channel) + '</span>' + escapeHtml(m.title || "(제목 없음)") + '</span>',
        '  <span class="handoff-dir">' + dirLabelHtml(m.dir, m, channel) + '</span>',
        '</div>',
        // 오른쪽도 왼쪽(제목 / 방향)처럼 두 줄: 윗줄 [과정 버튼] [토큰], 아랫줄 [시각] [상태 진행 표시]. 윗줄이 비어도 아랫줄은 늘 아래에 맞춘다.
        '<div class="handoff-card-header-right">',
        '  <div class="hh-top">',
        (usageText ? '    <span class="handoff-tokens" title="' + escapeHtml(usageText.title) + '">' + escapeHtml(usageText.chip) + '</span>' : ''),
        (claudeText ? '    <span class="handoff-tokens is-claude" title="' + escapeHtml(claudeText.title) + '">' + escapeHtml(claudeText.chip) + '</span>' : ''),
        '  </div>',
        '  <div class="hh-bottom">',
        '    <span class="handoff-time">' + escapeHtml(m.time || "") + '</span>',
        '    ' + stepsHtml(m.status),
        '  </div>',
        '</div>'
      ].join("");
      makeActivatable(header);
      header.setAttribute("aria-expanded", openHandoffNums[openKey] ? "true" : "false");

      // 끝난 메시지(처리됨·확인함·agy 회신)도 위임 기록이 있으면 "과정" 버튼으로 agy 가 한 일을 볼 수 있다. 기록이 없는 메시지에는 버튼을 만들지 않는다.
      var doneTaskId = handoffFinishedTaskId(handoffChannels[channel], channel, m, allItems);
      var doneSrc = doneTaskId ? findProcessSource("r:" + doneTaskId) : null;
      if (doneSrc) {
        var topEl = header.querySelector(".handoff-card-header-right .hh-top");
        if (topEl) { topEl.insertBefore(buildProcessButton("r:" + doneTaskId, doneSrc.opts), topEl.firstChild); }
      }

      var body = document.createElement("div");
      body.className = "handoff-card-body md";

      if (openHandoffNums[openKey]) {
        body.style.display = "block";
        card.classList.add("is-open");
        if (fileName) {
          var cacheKey = channel + "/" + fileName;
          if (handoffMessageCache[cacheKey]) {
            renderMarkdownBody(body, handoffMessageCache[cacheKey]);
            body.dataset.loaded = "true";
          } else {
            body.innerHTML = '<div class="handoff-card-body-loading">메시지 본문을 불러오는 중...</div>';
            fetchText("/api/handoff/message?project=" + encodeURIComponent(channel) + "&file=" + encodeURIComponent(fileName))
              .then(function (md) {
                handoffMessageCache[cacheKey] = md;
                if (openHandoffNums[openKey]) {
                  renderMarkdownBody(body, md);
                  body.dataset.loaded = "true";
                }
              })
              .catch(function (err) {
                body.innerHTML = '<p class="empty">본문 로드 실패: ' + escapeHtml(err.message) + '</p>';
              });
          }
        } else {
          body.innerHTML = '<p class="empty">메시지 파일(msg/' + escapeHtml(m.num) + '-*.md)을 찾을 수 없습니다.</p>';
          body.dataset.loaded = "true";
        }
      } else {
        body.style.display = "none";
      }

      header.addEventListener("click", function (ev) {
        if (ev.target && ev.target.closest && ev.target.closest(".proc-open")) { return; }   // 과정 버튼은 카드를 펴고 접지 않고 창만 연다
        toggleHandoffMessage(card, channel, m, fileName);
      });

      card.appendChild(header);
      if (claudeText) { card.appendChild(buildClaudeUsageEl(claudeText)); }
      if (usageText) { card.appendChild(buildHandoffUsageEl(usageText)); }   // 닫힌 카드에서는 CSS 로 숨긴다(펼칠 때 다시 그리지 않으므로 늘 넣어 둔다)
      var liveInfo = handoffLiveFor(channel, m);
      if (liveInfo) { card.appendChild(buildHandoffLiveEl(channel, m, liveInfo)); }
      card.appendChild(body);
      frag.appendChild(card);
    });

    els.handoffCards.innerHTML = "";
    els.handoffCards.appendChild(frag);
    updateTopbarMeta();
  }

  function getCardWaitIcon(state, isProcessing, isInterrupted) {
    if (state === "waiting") return "hourglass";
    if (state === "queued" && !isProcessing && !isInterrupted) return "hourglass";
    return null;
  }

  // ==========================================================================
  // Full Refresh Cycle
  // ==========================================================================

  var lastClaudeTreeKey = "";

  function claudeTreeKeyOf(data) {
    if (!data || typeof data !== "object") return "";
    var pParts = [];
    var projects = Array.isArray(data.projects) ? data.projects : [];
    for (var i = 0; i < projects.length; i++) {
      var p = projects[i] || {};
      var sParts = [];
      var sessions = Array.isArray(p.sessions) ? p.sessions : [];
      for (var j = 0; j < sessions.length; j++) {
        var s = sessions[j] || {};
        sParts.push([s.id || "", s.title || "", s.cwd || "", s.lastActivity || "", s.archived ? 1 : 0, s.forkOf || ""].join("~"));
      }
      pParts.push((p.id || "") + ":" + (p.name || "") + "[" + sParts.join(",") + "]");
    }
    var uParts = [];
    var ungrouped = Array.isArray(data.ungrouped) ? data.ungrouped : [];
    for (var u = 0; u < ungrouped.length; u++) {
      var us = ungrouped[u] || {};
      uParts.push([us.id || "", us.title || "", us.cwd || "", us.lastActivity || "", us.archived ? 1 : 0].join("~"));
    }
    var tl = data.taskLinks || {};
    var tlKeys = Object.keys(tl).sort();
    var tlParts = [];
    for (var t = 0; t < tlKeys.length; t++) { tlParts.push(tlKeys[t] + "=" + tl[tlKeys[t]]); }

    var hl = data.handoffLinks || {};
    var hlKeys = Object.keys(hl).sort();
    var hlParts = [];
    for (var h = 0; h < hlKeys.length; h++) { hlParts.push(hlKeys[h] + "=" + hl[hlKeys[h]]); }

    var agParts = [];
    var agyProjects = Array.isArray(data.agyProjects) ? data.agyProjects : [];
    for (var ai = 0; ai < agyProjects.length; ai++) {
      var ap = agyProjects[ai] || {};
      var asParts = [];
      var asess = Array.isArray(ap.sessions) ? ap.sessions : [];
      for (var aj = 0; aj < asess.length; aj++) {
        var as = asess[aj] || {};
        asParts.push([as.id || "", as.title || "", as.cwd || "", as.lastActivity || "", as.archived ? 1 : 0].join("~"));
      }
      agParts.push((ap.id || "") + ":" + (ap.name || "") + "[" + asParts.join(",") + "]");
    }

    return [pParts.join("|"), uParts.join("|"), tlParts.join(","), hlParts.join(","), agParts.join("|")].join("#");
  }

  function loadClaudeTree() {
    return fetchJson("/api/claude/tree").then(function (data) {
      if (data && typeof data === "object") {
        var newKey = claudeTreeKeyOf(data);
        var changed = (newKey !== lastClaudeTreeKey);
        lastClaudeTreeKey = newKey;
        claudeTree = data;
        return { tree: claudeTree, changed: changed };
      }
      return { tree: claudeTree, changed: false };
    }).catch(function () {
      return { tree: claudeTree, changed: false };
    });
  }

  function refresh(force) {
    if (force || !lastQuotaLoadAt || (Date.now() - lastQuotaLoadAt >= QUOTA_AUTO_RELOAD_MS)) {
      loadAccountQuotas();
    }
    return Promise.all([
      loadSystemStatus(),
      loadAllQa(force),
      loadPending(),
      loadClaudeTree()
    ]).then(function (results) {
      var qaRes = results[1] || { changed: false };
      var pList = results[2] || [];
      var treeRes = results[3] || { changed: false };

      var pKey = pendingKeyOf(pList);
      var pChanged = (pKey !== lastPendingKey);
      lastPendingKey = pKey;
      pendingItems = pList;
      syncLiveProcess(pList);

      var qaNeedsRender = Boolean(force || qaRes.changed || pChanged || treeRes.changed);

      if (qaNeedsRender) {
        populateModelFilter();
      }
      // 사이드바 트리는 스크롤을 보존하며 상대 시간("3분 전" 등)을 매번 최신으로 갱신한다
      renderQaTree();
      renderQuickSessions();

      if (currentNav === "dashboard") {
        renderDashboard();
      } else if (currentNav === "qa") {
        if (qaNeedsRender) {
          applyQaFilters();
        } else {
          updateQaHeader();
          renderProcessDialog();
        }
      }
      updateTopbarMeta();
    }).catch(function (err) {
      console.warn("Refresh error:", err);
      if (els.topbarCount) {
        els.topbarCount.textContent = "갱신 실패: " + err.message;
      }
      if (currentNav === "dashboard") { renderNow(); }
    });
  }

  function scheduleAutoRefresh() {
    if (refreshTimer) { clearInterval(refreshTimer); refreshTimer = null; }
    if (els.autoRefresh && els.autoRefresh.checked) {
      refreshTimer = setInterval(function () { refresh(false); }, AUTO_REFRESH_MS);
    }
  }

  // ==========================================================================
  // Task Focus & Hash Routing Helpers
  // ==========================================================================

  function showTaskNotice(msg, keepMs) {
    var id = "task-focus-notice";
    var prev = document.getElementById(id);
    if (prev && prev.parentNode) prev.parentNode.removeChild(prev);
    var div = document.createElement("div");
    div.id = id;
    div.className = "top-toast";
    div.textContent = msg;
    document.body.appendChild(div);
    if (keepMs === 0) { return; }
    setTimeout(function () {
      div.style.opacity = "0";
      setTimeout(function () { if (div.parentNode) div.parentNode.removeChild(div); }, 350);
    }, keepMs || 4000);
  }
  function hideTaskNotice() {
    var prev = document.getElementById("task-focus-notice");
    if (prev && prev.parentNode) prev.parentNode.removeChild(prev);
  }

  var focusQaTimer = null;
  function focusQaTask(taskId) {
    if (!taskId) return;
    if (focusQaTimer) {
      clearInterval(focusQaTimer);
      focusQaTimer = null;
    }
    if (currentNav !== "qa") {
      switchNav("qa", false);
    }

    // 1. 그 카드가 보이도록 필터를 모두 푼다: 프로젝트 · 세션 · agy 칩 선택을 전체로
    if (els.qaSearch) { els.qaSearch.value = ""; }
    if (els.modelFilter) { els.modelFilter.value = ""; }
    if (els.statusFilter) { els.statusFilter.value = ""; }
    selectQaSession("", "");
    currentQaAgy = "";
    renderQaAgyChips();
    applyQaFilters();

    // 2. 카드 목록이 개수 제한 · 더 보기로 잘라 그린다면, 그 작업이 들어가도록 늘려서 그린다
    function ensureRendered() {
      if (!Array.isArray(filteredQa)) return;
      for (var i = 0; i < filteredQa.length; i++) {
        if (filteredQa[i] && filteredQa[i].task_id === taskId) {
          while (shownQaCount <= i && shownQaCount < filteredQa.length) {
            renderMoreQa();
          }
          break;
        }
      }
    }

    // 3. .card[data-key="r:<id>"] 또는 .card[data-key="p:<id>"] 를 0.25초마다 최대 8초 찾는다
    function findCard() {
      ensureRendered();
      if (!els.cards) return null;
      var cards = els.cards.querySelectorAll(".card[data-key]");
      var targetR = "r:" + taskId;
      var targetP = "p:" + taskId;
      for (var j = 0; j < cards.length; j++) {
        var k = cards[j].getAttribute("data-key");
        if (k === targetR || k === targetP) {
          return cards[j];
        }
      }
      return null;
    }

    function onFound(card) {
      updateHash(true);
      card.scrollIntoView({ block: "center" });
      card.classList.add("card-focus");
      setTimeout(function () {
        card.classList.remove("card-focus");
      }, 4000);
    }

    var immediate = findCard();
    if (immediate) {
      onFound(immediate);
      return;
    }

    // 새 창 · 새로고침이면 위임 기록을 처음부터 받느라 몇 초 걸린다: 찾는 동안 어느 작업으로 가는지 알리고 30초까지 기다린다
    showTaskNotice("작업 " + taskId + " 카드를 불러오는 중…", 0);
    var start = Date.now();
    focusQaTimer = setInterval(function () {
      var card = findCard();
      if (card) {
        clearInterval(focusQaTimer);
        focusQaTimer = null;
        hideTaskNotice();
        onFound(card);
        return;
      }
      if (Date.now() - start >= 30000) {
        clearInterval(focusQaTimer);
        focusQaTimer = null;
        updateHash(true);
        showTaskNotice("작업 " + taskId + " 카드를 찾지 못했습니다(보관 기간이 지났을 수 있음)");
      }
    }, 250);
  }

  // ==========================================================================
  // Event Bindings & Initializers
  // ==========================================================================

  function bindEvents() {
    // 스크롤 복원 중 사용자 조작 감지 시 복원 중단
    window.addEventListener("wheel", handleUserScrollAttempt, { passive: true });
    window.addEventListener("touchmove", handleUserScrollAttempt, { passive: true });
    window.addEventListener("keydown", function (e) {
      var k = e.key;
      if (k === "ArrowUp" || k === "ArrowDown" || k === "PageUp" || k === "PageDown" || k === "Home" || k === "End" || k === " ") {
        handleUserScrollAttempt();
      }
    });
    if (els.mainScroll) {
      els.mainScroll.addEventListener("scroll", function () {
        if (!isProgrammaticScroll && activeRestore) {
          handleUserScrollAttempt();
        }
      }, { passive: true });
      els.mainScroll.addEventListener("wheel", handleUserScrollAttempt, { passive: true });
      els.mainScroll.addEventListener("touchmove", handleUserScrollAttempt, { passive: true });
    }

    // 사이드바 브랜드/로고 클릭 시 루트(대시보드) 이동
    if (els.sidebarBrand) {
      els.sidebarBrand.addEventListener("click", function (e) {
        if (e.ctrlKey || e.metaKey || e.shiftKey || e.button === 1) {
          return;
        }
        e.preventDefault();
        if (currentNav === "dashboard") {
          if (els.viewDashboard) els.viewDashboard.scrollTo({ top: 0, behavior: "smooth" });
          window.scrollTo({ top: 0, behavior: "smooth" });
          return;
        }
        switchNav("dashboard");
        if (els.viewDashboard) els.viewDashboard.scrollTo({ top: 0 });
        window.scrollTo({ top: 0 });
      });
    }

    // 1차 네비게이션 버튼
    if (els.navBtnDashboard) els.navBtnDashboard.addEventListener("click", function () { switchNav("dashboard"); });
    if (els.navBtnQa) els.navBtnQa.addEventListener("click", function () { switchNav("qa"); });
    if (els.navBtnHandoff) els.navBtnHandoff.addEventListener("click", function () { switchNav("handoff"); });
    if (els.navBtnStats) els.navBtnStats.addEventListener("click", function () { switchNav("stats"); });
    if (els.usageRefresh) els.usageRefresh.addEventListener("click", function () {
      usageRowsVisibleCount = USAGE_PAGE_SIZE;
      loadUsageStats(true);
      loadUsageDiagnostics();
      loadAccountQuotas();
    });
    if (els.dashQuotasRefresh) els.dashQuotasRefresh.addEventListener("click", triggerAccountQuotasRefresh);
    if (els.statsQuotasRefresh) els.statsQuotasRefresh.addEventListener("click", triggerAccountQuotasRefresh);
    if (els.sidebarQuotas) {
      els.sidebarQuotas.addEventListener("click", function (e) {
        var refreshBtn = e.target && e.target.closest ? e.target.closest("#sidebar-quotas-refresh") : null;
        if (refreshBtn) {
          e.stopPropagation();
          triggerAccountQuotasRefresh();
          return;
        }
        var chip = e.target && e.target.closest ? e.target.closest(".sidebar-quota-chip") : null;
        if (chip) {
          switchNav("stats");
        }
      });
    }
    if (els.usageClientFilter) els.usageClientFilter.addEventListener("change", function () {
      usageClientFilter = els.usageClientFilter.value || "";
      usageRowsVisibleCount = USAGE_PAGE_SIZE;
      renderUsageStats();
    });
    if (els.usageLoadmore50) els.usageLoadmore50.addEventListener("click", function () {
      usageRowsVisibleCount += USAGE_PAGE_SIZE;
      renderUsageStats();
    });
    if (els.usageLoadmoreAll) els.usageLoadmoreAll.addEventListener("click", function () {
      usageRowsVisibleCount = Infinity;
      renderUsageStats();
    });
    if (els.usageDiagBriefToggle) els.usageDiagBriefToggle.addEventListener("click", function () {
      if (!els.usageDiagBrief) return;
      var nextHidden = !els.usageDiagBrief.hidden;
      els.usageDiagBrief.hidden = nextHidden;
      els.usageDiagBriefToggle.textContent = nextHidden ? "지시문 보기" : "지시문 접기";
    });
    if (els.usageDiagCopy) els.usageDiagCopy.addEventListener("click", function () {
      var text = (usageDiagnosticsData && usageDiagnosticsData.fix_brief) ? usageDiagnosticsData.fix_brief : "";
      if (!text) return;
      var done = function () {
        var orig = els.usageDiagCopy.textContent;
        els.usageDiagCopy.textContent = "복사됨 ✓";
        setTimeout(function () { els.usageDiagCopy.textContent = orig; }, 1800);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done).catch(function () {});
      } else {
        var ta = document.createElement("textarea");
        ta.value = text;
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand("copy"); done(); } catch (e) {}
        document.body.removeChild(ta);
      }
    });
    if (els.usageDiagGroups) els.usageDiagGroups.addEventListener("click", function (e) {
      var btn = e.target && e.target.closest ? e.target.closest(".usage-diag-ack") : null;
      if (!btn) return;
      e.preventDefault();
      e.stopPropagation();
      if (btn.disabled) return;
      var cat = btn.getAttribute("data-category") || "";
      var label = btn.getAttribute("data-label") || cat;
      var cnt = btn.getAttribute("data-unacked") || "0";
      if (!cat) return;
      if (!window.confirm(label + " " + cnt + "건을 처리됨으로 표시할까요?")) return;
      btn.disabled = true;
      var prevErr = btn.nextElementSibling && btn.nextElementSibling.getAttribute && btn.nextElementSibling.getAttribute("data-ack-err") === "1" ? btn.nextElementSibling : null;
      if (prevErr && prevErr.parentNode) prevErr.parentNode.removeChild(prevErr);
      fetch("/api/qa/diagnostics/ack", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Samjil-Viewer": "1" },
        body: JSON.stringify({ category: cat })
      }).then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.json();
      }).then(function () {
        return loadUsageDiagnostics();
      }).catch(function () {
        btn.disabled = false;
        var errSpan = document.createElement("span");
        errSpan.setAttribute("data-ack-err", "1");
        errSpan.style.color = "var(--err)";
        errSpan.textContent = "실패";
        btn.insertAdjacentElement("afterend", errSpan);
      });
    });
    Array.prototype.forEach.call(document.querySelectorAll(".usage-day-btn"), function (btn) {
      btn.addEventListener("click", function () {
        var d = parseInt(btn.dataset.days, 10);
        if (d === usageDays) return;
        usageDays = d;
        usageData = null;
        usageRowsVisibleCount = USAGE_PAGE_SIZE;
        renderUsageStats();
        updateBreadcrumbs();
        loadUsageStats(false);
      });
    });

    // 사이드바 토글 버튼 (데스크톱 접기 / 모바일 햄버거)
    if (els.sidebarCollapseBtn) {
      els.sidebarCollapseBtn.addEventListener("click", function () {
        if (els.appSidebar) {
          var isCollapsed = els.appSidebar.classList.toggle("collapsed");
          try { localStorage.setItem("samjil_sidebar_collapsed", isCollapsed ? "true" : "false"); } catch (e) {}
        }
      });
    }

    if (els.topbarMenuToggle) {
      els.topbarMenuToggle.addEventListener("click", function () {
        if (els.appSidebar) {
          var isOpen = els.appSidebar.classList.toggle("open");
          if (els.sidebarBackdrop) els.sidebarBackdrop.classList.toggle("open", isOpen);
        }
      });
    }
    if (els.sidebarBackdrop) {
      els.sidebarBackdrop.addEventListener("click", function () {
        if (els.appSidebar) els.appSidebar.classList.remove("open");
        els.sidebarBackdrop.classList.remove("open");
      });
    }

    // 대시보드 내 "모두 보기" 링크
    if (els.btnViewAllQa) {
      els.btnViewAllQa.addEventListener("click", function () {
        selectQaProject("");
        switchNav("qa");
      });
    }

    // QA 세션 사이드바 검색 및 필터
    if (els.qaSourceTabs) {
      els.qaSourceTabs.addEventListener("click", function (e) {
        var btn = e.target && e.target.closest ? e.target.closest("[data-qa-source]") : null;
        if (!btn) return;
        var nextSrc = btn.getAttribute("data-qa-source") || "all";
        if (nextSrc === qaSource) return;
        qaSource = nextSrc;
        Array.prototype.forEach.call(els.qaSourceTabs.querySelectorAll("[data-qa-source]"), function (b) {
          var active = b.getAttribute("data-qa-source") === qaSource;
          b.classList.toggle("active", active);
          b.setAttribute("aria-selected", active ? "true" : "false");
        });
        currentQaProject = "";
        currentQaSession = "";
        currentQaAgy = "";
        renderQaTree();
        updateBreadcrumbs();
        updateHash();
        applyQaFilters();
      });
    }
    if (els.qaDiagChip) {
      els.qaDiagChip.addEventListener("click", function () {
        if (!els.statusFilter) return;
        els.statusFilter.value = (els.statusFilter.value === "ERROR") ? "" : "ERROR";
        applyQaFilters();
      });
    }
    if (els.qaSessionSearch) els.qaSessionSearch.addEventListener("input", renderQaTree);
    if (els.modelFilter) els.modelFilter.addEventListener("change", applyQaFilters);
    if (els.statusFilter) els.statusFilter.addEventListener("change", applyQaFilters);
    if (els.qaSearch) els.qaSearch.addEventListener("input", applyQaFilters);
    if (els.loadMoreBtn) els.loadMoreBtn.addEventListener("click", renderMoreQa);

    // Handoff 사이드바 검색 및 필터
    if (els.handoffProjectSearch) els.handoffProjectSearch.addEventListener("input", renderHandoffTree);
    if (els.handoffDirFilter) els.handoffDirFilter.addEventListener("change", renderHandoffMessages);
    if (els.handoffAutoBar) els.handoffAutoBar.addEventListener("click", function (ev) {
      var btn = ev.target && ev.target.closest ? ev.target.closest("button[data-act]") : null;
      var row = btn ? btn.closest(".auto-bar") : null;
      if (btn && row) postHandoffAuto(row.getAttribute("data-channel"), btn.getAttribute("data-act"), row);
    });
    if (els.handoffStatusFilter) els.handoffStatusFilter.addEventListener("change", renderHandoffMessages);
    if (els.handoffSearch) els.handoffSearch.addEventListener("input", renderHandoffMessages);

    // 푸터 새로고침 & 자동 갱신
    if (els.refreshBtn) els.refreshBtn.addEventListener("click", function () { refresh(true); });
    if (els.cards) {
      els.cards.addEventListener("click", function (e) {
        var procBtn = e.target && e.target.closest ? e.target.closest(".proc-open") : null;
        if (procBtn) { openProcessDialog(procBtn.getAttribute("data-proc-key")); return; }
        var srcLink = e.target && e.target.closest ? e.target.closest(".src-open") : null;
        if (srcLink) {
          // 링크(a)의 수정키·가운데 클릭은 브라우저 기본(새 탭에서 Raw)
          if (srcLink.tagName === "A" && (e.ctrlKey || e.metaKey || e.shiftKey || e.altKey || e.button)) { return; }
          e.preventDefault();
          openSourceDialog({
            task: srcLink.getAttribute("data-src-task"), kind: srcLink.getAttribute("data-src-kind"), cwd: srcLink.getAttribute("data-src-cwd"),
            key: srcLink.getAttribute("data-src-key"), useFile: srcLink.getAttribute("data-src-file") === "1"
          });
          return;
        }
        var sumEl = e.target && e.target.closest ? e.target.closest("summary") : null;
        var d = sumEl ? sumEl.parentNode : null;
        if (!d || !d.classList || !d.classList.contains("qa") || !d.parentNode || !d.parentNode.getAttribute("data-key")) return;
        qaOpenOverrides[qaSectionKey(d)] = !d.open;
      });
    }
    if (els.watcherStartBtn) els.watcherStartBtn.addEventListener("click", startWatcher);
    if (els.updateRunBtn) els.updateRunBtn.addEventListener("click", startUpdate);
    if (els.autoRefresh) els.autoRefresh.addEventListener("change", scheduleAutoRefresh);

    // role="button" 으로 표시한 div 항목은 Enter/Space 로도 누를 수 있게 한다.
    document.addEventListener("keydown", function (e) {
      if (e.key !== "Enter" && e.key !== " ") return;
      var t = e.target;
      if (!t || t.tagName === "BUTTON" || t.tagName === "INPUT" || t.tagName === "SELECT" || t.tagName === "TEXTAREA") return;
      if (t.getAttribute && t.getAttribute("role") === "button") {
        e.preventDefault();
        t.click();
      }
    });

    // 브라우저 해시 변경 감지 (뒤로가기/앞으로가기)
    function applyHashRoute() {
      var parsed = parseHash();
      if (parsed.nav !== currentNav) {
        switchNav(parsed.nav, false);
      }
      if (parsed.nav === "qa") {
        if (parsed.task) {
          focusQaTask(parsed.task);
        } else {
          var projChanged = (parsed.project !== currentQaProject);
          var sessChanged = (parsed.session !== currentQaSession);
          var agyChanged = (parsed.agy !== currentQaAgy);
          if (projChanged || sessChanged || agyChanged) {
            if (projChanged || sessChanged) {
              selectQaSession(parsed.session, parsed.project);
            }
            currentQaAgy = parsed.agy || "";
            renderQaAgyChips();
            applyQaFilters();
          }
        }
      }

      if (hashRouting && !parsed.task && typeof restoreScrollForHash === "function") {
        restoreScrollForHash(window.location.hash || "#/" + parsed.nav);
      }
    }

    function handleHistoryNavigation() {
      var targetH = (window.location && window.location.hash) ? window.location.hash : "#/dashboard";
      if (targetH === lastHandledHash) return;
      hashRouting = true;
      try {
        if (typeof saveCurrentScroll === "function") {
          saveCurrentScroll(lastKnownHash);
        }
        lastKnownHash = targetH;
        lastHandledHash = targetH;
        applyHashRoute();
      } finally {
        hashRouting = false;
      }
    }

    window.addEventListener("hashchange", handleHistoryNavigation);
    window.addEventListener("popstate", handleHistoryNavigation);
    document.addEventListener("visibilitychange", function () {
      if (document.visibilityState === "visible" && (!lastQuotaLoadAt || Date.now() - lastQuotaLoadAt >= QUOTA_AUTO_RELOAD_MS)) {
        loadAccountQuotas();
      }
    });
    window.addEventListener("focus", function () {
      if (!lastQuotaLoadAt || Date.now() - lastQuotaLoadAt >= QUOTA_AUTO_RELOAD_MS) {
        loadAccountQuotas();
      }
    });
  }

  // 초기화 실행
  initTheme();
  initImagePopups();
  initTreeSortSelects();
  bindEvents();

  // 이전 사이드바 접힘 상태 복원
  try {
    if (localStorage.getItem("samjil_sidebar_collapsed") === "true" && els.appSidebar) {
      els.appSidebar.classList.add("collapsed");
    }
  } catch (e) {}

  // 초기 라우트 파싱
  var initialRoute = parseHash();
  if (initialRoute.nav === "qa") {
    if (initialRoute.session) { currentQaSession = initialRoute.session; }
    if (initialRoute.project) { currentQaProject = initialRoute.project; }
    if (initialRoute.agy) { currentQaAgy = initialRoute.agy; }
  }

  // 최초 네비게이션 적용
  switchNav(initialRoute.nav, false);

  if (initialRoute.nav === "qa" && initialRoute.task) {
    focusQaTask(initialRoute.task);
  }

  // 최초 데이터 로드 및 타이머 시작
  refresh(true).then(scheduleAutoRefresh);
})();
