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
    navBtnStats:          document.getElementById("nav-btn-stats"),
    navBtnQa:             document.getElementById("nav-btn-qa"),
    navBtnHandoff:        document.getElementById("nav-btn-handoff"),

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
    qaTreeSort:           document.getElementById("qa-tree-sort"),
    modelFilter:          document.getElementById("modelfilter"),
    statusFilter:         document.getElementById("statusfilter"),

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
    watcherPulseDot:      document.getElementById("watcher-pulse-dot"),
    watcherStatusText:    document.getElementById("watcher-status-text"),
    watcherStartBtn:      document.getElementById("watcher-start"),
    watcherStartMsg:      document.getElementById("watcher-start-msg"),
    autoRefresh:          document.getElementById("autorefresh"),
    refreshBtn:           document.getElementById("refresh"),

    // 상단 탑바
    topbarCategory:       document.getElementById("topbar-category"),
    topbarCurrent:        document.getElementById("topbar-current"),
    topbarCount:          document.getElementById("topbar-count"),
    topbarUpdated:        document.getElementById("topbar-updated"),

    // 메인 뷰 패널들
    viewDashboard:        document.getElementById("view-dashboard"),
    viewStats:            document.getElementById("view-stats"),
    viewQa:               document.getElementById("view-qa"),
    viewHandoff:          document.getElementById("view-handoff"),
    mainScroll:           document.getElementById("main-content-scroll"),

    // 통계 뷰 내부 엘리먼트
    statsUpdatedTime:     document.getElementById("stats-updated-time"),
    statsRefreshBtn:      document.getElementById("stats-refresh-btn"),
    statsEmptyRefreshBtn: document.getElementById("stats-empty-refresh-btn"),
    statsTableToggle:     document.getElementById("stats-table-toggle"),
    statsCollectBanner:   document.getElementById("stats-collect-banner"),
    statsCollectTitle:    document.getElementById("stats-collect-title"),
    statsCollectDesc:     document.getElementById("stats-collect-desc"),
    statsCollectFill:     document.getElementById("stats-collect-fill"),
    statsEmptyState:      document.getElementById("stats-empty-state"),
    statsContentWrap:     document.getElementById("stats-content-wrap"),
    statsHeroSaved:       document.getElementById("stats-hero-saved"),
    statsHeroDesc:        document.getElementById("stats-hero-desc"),
    statsSumSuccess:      document.getElementById("stats-sum-success"),
    statsSumAccuracy:     document.getElementById("stats-sum-accuracy"),
    statsSumFormula:      document.getElementById("stats-sum-formula"),
    statsSumCache:        document.getElementById("stats-sum-cache"),
    statsSumTime:         document.getElementById("stats-sum-time"),
    chartTasksView:       document.getElementById("chart-tasks-view"),
    tableTasksView:       document.getElementById("table-tasks-view"),
    chartSavingsView:     document.getElementById("chart-savings-view"),
    tableSavingsView:     document.getElementById("table-savings-view"),
    chartAccuracyView:    document.getElementById("chart-accuracy-view"),
    tableAccuracyView:    document.getElementById("table-accuracy-view"),
    chartScatterView:     document.getElementById("chart-scatter-view"),
    tableScatterView:     document.getElementById("table-scatter-view"),
    chartTimeAccuracyView: document.getElementById("chart-time-accuracy-view"),
    tableTimeAccuracyView: document.getElementById("table-time-accuracy-view"),
    statsScatterCrossover: document.getElementById("stats-scatter-crossover"),
    statsRecentTbody:     document.getElementById("stats-recent-tbody"),
    statsTooltip:         document.getElementById("stats-tooltip"),

    // 대시보드 내부 엘리먼트
    dashNow:              document.getElementById("dash-now"),
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
    chipQaSaved:          document.getElementById("chip-qa-saved"),
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
  var currentNav = "dashboard"; // "dashboard" | "stats" | "qa" | "handoff"
  var statsData = null;
  var statsDays = 30;
  var statsTableView = false;
  var lastStatsFetchAt = 0;
  var isStatsHovering = false;
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

  var filteredQa = [];          // 필터 적용된 완료 QA
  var filteredPending = [];     // 필터 적용된 pending
  var shownQaCount = 0;         // 현재 렌더링된 카드 수
  var qaSeq = 0;                // 위임 기록 API 에서 마지막으로 받은 갱신 번호
  var lastPendingKey = "";      // pending 변경 감지 키
  var refreshTimer = null;
  var watcherStarting = false;   // 켜기 요청 후 켜질 때까지 true
  var isServerOnline = false;
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

  // 같은 모델로 끝난 위임 기록(최근 30건)의 실행 시간: 중앙값(med)과 느린 쪽 90번째 백분위(p90), 초 단위. 표본이 3건 미만이면 null.
  // 진행 중 카드의 "완료 예정"을 어림하는 데 쓴다: 이어가는 세션이나 큰 작업은 이보다 훨씬 오래 걸릴 수 있다.
  function typicalRunSec(model, excludeTaskId) {
    if (!model) return null;
    var xs = [];
    for (var i = 0; i < allItems.length && xs.length < 30; i++) {
      var r = allItems[i];
      if (r && r.model === model && r.elapsed_sec != null && !(excludeTaskId && r.task_id === excludeTaskId)) {
        var v = Number(r.elapsed_sec);
        if (isFinite(v) && v > 0) xs.push(v);
      }
    }
    if (xs.length < 3) return null;
    xs.sort(function (a, b) { return a - b; });
    var mid = Math.floor(xs.length / 2);
    return {
      med: xs.length % 2 ? xs[mid] : (xs[mid - 1] + xs[mid]) / 2,
      p90: xs[Math.min(xs.length - 1, Math.ceil(xs.length * 0.9) - 1)]
    };
  }

  // 진행 중 카드의 예정 위상: 예정 시간(estSec) 안이면 {over:false, sec:남은 시간}, 넘으면 {over:true, sec:넘긴 시간}.
  function etaPhase(startMs, estSec, nowMs) {
    var el = (nowMs - startMs) / 1000;
    return el < estSec ? { over: false, sec: estSec - el } : { over: true, sec: el - estSec };
  }

  // 진행 중 카드의 예상 항목을 지금 시각으로 다시 그린다. 예정 시간은 이 작업을 처음 본 때 기억해 둔 값이다.
  // 끝난 카드와 같은 모양 "예상 [처음 예정 ±차이]" 이고 차이만 강조한다.
  //  - 예정 시간 안: "[12분 28초 −6분 40초]" — 남은 시간(초록)이 줄어든다
  //  - 넘으면: "[12분 28초 +3분 05초]" — 넘긴 시간(주황)이 늘어난다
  function paintEta(el, nowMs) {
    var start = Number(el.getAttribute("data-start"));
    var initMed = Number(el.getAttribute("data-init-med")) || Number(el.getAttribute("data-med"));
    var ph = etaPhase(start, initMed, nowMs);
    var host = el.querySelector(".mv") || el;
    var lab = el.querySelector(".ml");
    el.classList.remove("eta-over");
    if (lab) lab.textContent = "예상";
    el.classList.add("eta-done");
    host.textContent = "";
    host.appendChild(document.createTextNode("[" + formatDuration(initMed) + " "));
    var val = document.createElement("strong");
    val.className = "eta-done-val " + (ph.over ? "over" : "under");
    val.textContent = (ph.over ? "+" : "−") + formatDuration(ph.sec);
    host.appendChild(val);
    host.appendChild(document.createTextNode("]"));
  }

  // 끝난 카드: 실제 실행 시간(actualSec)을 예상 시간(estSec)과 비교한다. 5초 미만 차이는 표시하지 않는다(null).
  // 예상보다 길면 {over:true, label:"예상 초과", text:"+14분 20초"}, 짧으면 {over:false, label:"예상 미만", text:"−2분 05초"}.
  function runVsEstimate(actualSec, estSec) {
    var d = actualSec - estSec;
    if (!isFinite(d) || !(estSec > 0) || Math.abs(d) < 5) return null;
    return d > 0 ? { over: true, label: "예상 초과", text: "+" + formatDuration(d) } : { over: false, label: "예상 미만", text: "−" + formatDuration(-d) };
  }
  // 진행 중에 이 브라우저가 기억해 둔 처음 예정 시간(초). 없으면 null(읽기만 하고 새로 저장하지 않는다).
  function etaStoredMed(taskId) {
    try {
      var v = Number(window.localStorage.getItem("samjil-eta-init:" + taskId));
      return isFinite(v) && v > 0 ? v : null;
    } catch (e) { return null; }
  }

  // 처음 계산한 완료 예정(initEnd)과 지금 계산한 완료 예정(liveEnd)의 차이. 5초 미만이면 보이지 않는다(null).
  // 늦어지면 {up:true, text:"▲ 3분 12초"}, 당겨지면 {up:false, text:"▼ 1분 05초"}.
  function etaDelta(initEndMs, liveEndMs) {
    var d = (liveEndMs - initEndMs) / 1000;
    if (!isFinite(d) || Math.abs(d) < 5) return null;
    return { up: d > 0, text: (d > 0 ? "▲ " : "▼ ") + formatDuration(Math.abs(d)) };
  }
  // 이 작업을 처음 본 때의 보통 시간(초)을 브라우저에 기억해 둔다(새로고침해도 유지). 저장소를 못 쓰면 지금 값을 처음 값으로 본다.
  function etaInitialMed(taskId, medNow) {
    var key = "samjil-eta-init:" + taskId;
    try {
      var v = Number(window.localStorage.getItem(key));
      if (isFinite(v) && v > 0) return v;
      window.localStorage.setItem(key, String(medNow));
    } catch (e) {}
    return medNow;
  }

  // 차이 항목의 글자·색·설명을 지금 시각 기준으로 다시 정한다. 차이가 없으면 숨긴다.
  function paintEtaDelta(el, nowMs) {
    var start = Number(el.getAttribute("data-start")), med = Number(el.getAttribute("data-med"));
    var initEnd = start + Number(el.getAttribute("data-init-med")) * 1000;
    var liveEnd = start + med * 1000;
    // 예정 시간을 넘긴 뒤에는 "[예정 +넘긴 시간]" 이 대신 말해 주므로 차이 항목은 숨긴다
    var dl = nowMs >= initEnd ? null : etaDelta(initEnd, liveEnd);
    if (!dl) { el.hidden = true; el.textContent = ""; return; }
    var hm = function (ms) { var d = new Date(ms); return pad2(d.getHours()) + ":" + pad2(d.getMinutes()); };
    el.hidden = false;
    el.textContent = dl.text;
    el.classList.toggle("up", dl.up);
    el.classList.toggle("down", !dl.up);
    el.title = "처음 예상 " + hm(initEnd) + " → 지금 예상 " + hm(liveEnd) + (dl.up ? ": 처음 예상보다 늦어지고 있습니다." : ": 처음 예상보다 빨라졌습니다.");
  }

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

  function isOkStatus(r) {
    if (!r || r.status == null) return false;
    return String(r.status).trim() === "OK";
  }


  function pendingKeyOf(list) {
    if (!list || !list.length) { return ""; }
    return list.map(function (p) {
      var pg = p.progress || {};
      var tok = (pg.tokens && pg.tokens.total) ? pg.tokens.total : 0;
      return [
        p.task_id || "",
        p.state || "",
        p.model || "",
        p.started_at || "",
        pg.step != null ? pg.step : "",
        pg.last_activity_ms || "",
        tok
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

    if (path === "#/stats") {
      var d = parseInt(params.days, 10);
      if (d !== 7 && d !== 30 && d !== 60) d = 30;
      return { nav: "stats", days: d, session: "", project: "" };
    }
    if (path === "#/qa") {
      return { nav: "qa", session: params.session || "", project: params.project || "", agy: params.agy || "" };
    }
    var matchHandoff = path.match(/^#\/handoff$/);
    if (matchHandoff) {
      return { nav: "handoff", session: params.session || "", project: params.project || "" };
    }
    return { nav: "dashboard", session: "", project: "" };
  }

  function updateHash(replace) {
    var newHash = "#/" + currentNav;
    if (currentNav === "stats") {
      if (statsDays && statsDays !== 30) {
        newHash += "?days=" + statsDays;
      }
    } else if (currentNav === "qa") {
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
    } else if (currentNav === "handoff") {
      var hParts = [];
      if (currentHandoffProject) {
        hParts.push("project=" + encodeURIComponent(currentHandoffProject));
      }
      if (currentHandoffSession) {
        hParts.push("session=" + encodeURIComponent(currentHandoffSession));
      }
      if (hParts.length > 0) {
        newHash += "?" + hParts.join("&");
      }
    }
    if (window.location.hash !== newHash) {
      if (replace === true || hashRouting) {
        history.replaceState(null, "", newHash);
      } else {
        history.pushState(null, "", newHash);
      }
    }
  }

  function switchNav(nav, updateUrl) {
    if (nav !== "dashboard" && nav !== "qa" && nav !== "handoff" && nav !== "stats") {
      nav = "dashboard";
    }
    currentNav = nav;

    // 1차 네비게이션 버튼 활성화
    [els.navBtnDashboard, els.navBtnStats, els.navBtnQa, els.navBtnHandoff].forEach(function (btn) {
      if (btn) {
        var isActive = (btn.dataset.nav === nav);
        btn.classList.toggle("active", isActive);
        btn.setAttribute("aria-selected", isActive ? "true" : "false");
      }
    });

    // 2차 서브 패널 전환
    if (els.subDashboard) els.subDashboard.style.display = (nav === "dashboard" ? "flex" : "none");
    if (els.subQa) els.subQa.style.display = (nav === "qa" ? "flex" : "none");
    if (els.subHandoff) els.subHandoff.style.display = (nav === "handoff" ? "flex" : "none");

    // 메인 뷰 전환
    if (els.viewDashboard) els.viewDashboard.style.display = (nav === "dashboard" ? "block" : "none");
    if (els.viewStats) els.viewStats.style.display = (nav === "stats" ? "block" : "none");
    if (els.viewQa) els.viewQa.style.display = (nav === "qa" ? "block" : "none");
    if (els.viewHandoff) els.viewHandoff.style.display = (nav === "handoff" ? "block" : "none");

    // 상단 브레드크럼 및 상태 갱신
    updateBreadcrumbs();
    updateTopbarMeta();

    if (updateUrl !== false) {
      updateHash();
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
    } else if (nav === "stats") {
      fetchAndRenderStats(false);
    } else if (nav === "qa") {
      applyQaFilters();
    } else if (nav === "handoff") {
      renderHandoffView();
    }
  }

  function updateBreadcrumbs() {
    if (!els.topbarCategory || !els.topbarCurrent) return;

    if (currentNav === "dashboard") {
      els.topbarCategory.textContent = "홈";
      els.topbarCurrent.textContent = "대시보드";
    } else if (currentNav === "stats") {
      els.topbarCategory.textContent = "홈";
      els.topbarCurrent.textContent = "통계";
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
    } else if (currentNav === "handoff") {
      els.topbarCategory.textContent = "에이전트 협의";
      if (!currentHandoffProject) {
        els.topbarCurrent.textContent = "전체 프로젝트";
      } else {
        var hTree = buildHandoffTree(handoffChannels, claudeTree);
        var hTitles = findHandoffNodeTitles(hTree, currentHandoffProject, currentHandoffSession);
        if (!currentHandoffSession) {
          els.topbarCurrent.textContent = hTitles.projectName;
        } else {
          els.topbarCurrent.textContent = hTitles.projectName + " / " + hTitles.sessionTitle;
        }
      }
    }
  }

  function updateTopbarMeta() {
    if (!els.topbarCount || !els.topbarUpdated) return;

    if (currentNav === "dashboard") {
      els.topbarCount.textContent = "총 " + allItems.length + "건 위임 / " + handoffProjects.length + "개 프로젝트";
    } else if (currentNav === "stats") {
      els.topbarCount.textContent = "토큰·위임 통계 (" + statsDays + "일)";
    } else if (currentNav === "qa") {
      var count = filteredQa.length + filteredPending.length;
      els.topbarCount.textContent = count + "건 표시 중 (전체 " + allItems.length + "건)";
    } else if (currentNav === "handoff") {
      var hMsgs = handoffMessagesOf(handoffChannels, claudeTree, currentHandoffProject, currentHandoffSession);
      els.topbarCount.textContent = hMsgs.length + "개 메시지";
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
        return status;
      })
      .catch(function () {
        isServerOnline = false;
        systemStatus = null;
        if (els.watcherPulseDot) els.watcherPulseDot.classList.add("offline");
        if (els.watcherStatusText) {
          els.watcherStatusText.textContent = "뷰어 서버 연결 끊김";
        }
        updateWatcherStartButton(null);
        return null;
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
      var items = (since === 0) ? recs : mergeQaRecords(allItems, recs);

      if (since > 0 && items.length !== total) {
        qaSeq = 0;
        return loadAllQa(true);
      }
      var changed = Boolean(force) || recs.length > 0 || items.length !== allItems.length;
      if (!changed) { return { changed: false }; }

      items.sort(function (a, b) {
        return String((b && b.timestamp) || "").localeCompare(String((a && a.timestamp) || ""));
      });
      allItems = items;
      qaSeq = (res && typeof res.seq === "number") ? res.seq : qaSeq;
      requestSavedFileSizes(items).then(function (got) { if (got) { refreshSavedViews(); } });
      requestRecordContexts(items).then(function (got) { if (got) { refreshTokenMetas(); } });
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
      if (r.status && String(r.status).trim() !== "OK") {
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
    }
    // 대기·진행 중인 작업(완료 기록과 달리 timestamp 가 없고 state 가 있다)은 작업 폴더로 세션을 짐작해 본다
    if (item && item.state && !item.timestamp) {
      var guessed = qaGuessSessionByCwd(item, tree);
      if (guessed) return guessed;
    }
    var sName = (item && item.session != null && String(item.session).trim() !== "") ? String(item.session) : "";
    return {
      projectId: QA_UNLINKED,
      projectName: "연결 안 됨",
      sessionId: "u:" + (sName ? sName : "__none__"),
      sessionTitle: sName ? sName : "단발성 (세션 없음)"
    };
  }

  function buildQaTree(records, pendings, tree) {
    var recs = Array.isArray(records) ? records : [];
    var pends = Array.isArray(pendings) ? pendings : [];

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

    var ungroupedNode = null;
    if (tree && Array.isArray(tree.ungrouped) && tree.ungrouped.length > 0) {
      ungroupedNode = {
        id: QA_UNGROUPED,
        name: "그룹 없음",
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
      total: 0,
      pending: 0,
      errors: 0,
      latestTime: "",
      sessions: []
    };
    var unlinkedSessionMap = {};

    function processItem(item, isPending) {
      if (!item || typeof item !== "object") return;
      var nodeInfo = qaNodeOf(item, tree);
      var time = isPending ? (item.created || "") : (item.timestamp || "");
      var isErr = !isPending && item.status && String(item.status).trim() !== "OK";

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

    if (ungroupedNode) {
      finalizeProject(ungroupedNode);
      if (ungroupedNode.sessions.length > 0) {
        result.push(ungroupedNode);
      }
    }

    finalizeProject(unlinkedNode);
    if (unlinkedNode.sessions.length > 0 && (unlinkedNode.total + unlinkedNode.pending > 0)) {
      result.push(unlinkedNode);
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

  function qaItemMatchesSelection(item, tree, projectId, sessionId) {
    if (!projectId) return true;
    var node = qaNodeOf(item, tree);
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
        if (item.status && String(item.status).trim() !== "OK") {
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

    var allNodes = buildQaTree(allItems, pendingItems, claudeTree);
    if (els.qaSessionCount) {
      els.qaSessionCount.textContent = allNodes.length;
    }

    var q = (els.qaSessionSearch && els.qaSessionSearch.value || "").trim().toLowerCase();
    var filtered = qaFilterTree(allNodes, q);
    var sorted = sortTreeNodes(filtered, getQaTreeSortMode(), { dateSource: "records" });
    var hasQuery = Boolean(q);

    var frag = document.createDocumentFragment();

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
      '<span class="project-badge">' + (allItems.length + pendingItems.length) + '</span>'
    ].join("");
    makeActivatable(allItem);
    allItem.onclick = function () { selectQaProject(""); };
    frag.appendChild(allItem);

    // 2. 프로젝트 트리 목록
    sorted.forEach(function (p) {
      var isOpen = isQaProjectOpen(p.id, hasQuery);
      var isProjectActive = (currentQaProject === p.id && currentQaSession === "");

      var pItem = document.createElement("div");
      var pClass = "project-item tree-project" + (isProjectActive ? " active" : "") + (isOpen ? " open" : "");
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
    var etas = document.querySelectorAll(".live-eta[data-start]");
    for (var e = 0; e < etas.length; e++) { paintEta(etas[e], Date.now()); }
    var deltas = document.querySelectorAll(".live-eta-delta[data-start]");
    for (var q = 0; q < deltas.length; q++) { paintEtaDelta(deltas[q], Date.now()); }
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

    if (!isServerOnline) {
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
        if (recordModel(last)) { meta.push('<span><code>' + escapeHtml(recordModel(last)) + '</code></span>'); }
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

  // ==========================================================================
  // Claude 토큰 절약(예상)
  //   Claude 가 쓴 토큰은 이 도구가 잴 수 없다. agy 의 토큰 수는 방식이 달라(입력이 단계마다 맥락을 다시 읽는 누적) 그대로 쓰지 않고,
  //   "같은 일을 Claude 가 직접 했다면" 필요했을 분량을 agy 가 남긴 과정(읽은 파일 · 쓴 파일 · 실행한 명령 · 생각)에서 어림한다:
  //     읽기  : 읽은 파일(같은 파일은 한 번)의 크기를 토큰으로(파일이 없으면 기본값, 한 파일 상한 있음)
  //     쓰기  : 새로 쓴 파일의 크기 / 고친 곳은 한 군데당 어림값
  //     명령  : 명령 글자 + 출력 어림값
  //     생각  : 과정에 남은 생각 글의 길이 × 2(요약본이라 실제 생각은 더 길다)
  //     단계마다 도구 호출 형식 몫
  //   거기서 위임하느라 Claude 가 쓴 질문(Claude 가 쓴 글)을 뺀다. 최종 답은 Claude 가 직접 했어도 써야 하고 위임해도 읽어야 해서 서로 상쇄된다.
  //   성공한 위임만 세고, 과정이 없는 기록(MCP 호출 등)은 어림할 근거가 없어 센 값이 없다.
  // ==========================================================================
  var SAVED_READ_CAP_TOKENS = 30000;     // 한 파일을 읽는 데 드는 토큰 상한
  var SAVED_READ_DEFAULT_TOKENS = 2500;  // 크기를 모르는 읽은 파일
  var SAVED_WRITE_DEFAULT_TOKENS = 1500; // 크기를 모르는 쓴 파일
  var SAVED_EDIT_TOKENS = 600;           // 파일 한 군데를 고치는 도구 호출(바꿀 부분 + 앞뒤)
  var SAVED_CMD_RESULT_TOKENS = 300;     // 명령 하나의 출력
  var SAVED_STEP_TOKENS = 80;            // 도구 호출 하나의 형식(이름 · 인자 틀)

  var SAVED_READ_TOOLS = { view_file: 1, read_file: 1 };
  var SAVED_WRITE_TOOLS = { write_to_file: 1, write_file: 1 };
  var SAVED_EDIT_TOOLS = { replace_file_content: 1, edit_file: 1, multi_replace_file_content: 1 };

  // 글자 수를 토큰으로 어림: 영문·숫자·기호는 4자에 1토큰, 한글 등은 1.5자에 1토큰.
  function estimateTextTokens(s) {
    var str = String(s == null ? "" : s);
    var ascii = 0, other = 0;
    for (var i = 0; i < str.length; i++) { if (str.charCodeAt(i) < 128) { ascii++; } else { other++; } }
    return Math.ceil(ascii / 4 + other / 1.5);
  }

  // 파일 바이트 수를 토큰으로 어림(코드·한글이 섞인 글은 3.2바이트에 1토큰 안팎).
  function bytesToTokens(bytes) { return Math.ceil((Number(bytes) || 0) / 3.2); }

  function tokenRecordKey(r) { return r && r.task_id ? String(r.task_id) : "t:" + String(r && r.timestamp || ""); }

  // 과정의 detail 이 파일 경로로 보이는가(절대 경로만). 글 내용이 들어 있는 경우(write_file 의 본문 등)는 거른다.
  function savedLooksLikePath(s) {
    var v = String(s == null ? "" : s);
    if (v.length === 0 || v.length > 400 || v.indexOf("\n") >= 0) { return false; }
    return /^[A-Za-z]:[\\/]/.test(v) || v.charAt(0) === "/";
  }

  // agy 자신의 작업 파일(지시문 파일 · 내부 기록)은 일의 분량이 아니라서 센 값에서 뺀다.
  function savedIsInternalPath(p) {
    return /[\\/]\.gemini[\\/]|[\\/]antigravity-cli[\\/]|[\\/]delegate-agy[\\/]runtime[\\/]|[\\/]\.samjil[\\/]delegate-agy[\\/]/i.test(String(p));
  }

  function savedNormPath(p) { return String(p).replace(/\\/g, "/"); }

  // 한 위임 기록의 과정에서 일의 종류별 양을 뽑는다. 과정이 없으면 null.
  function analyzeSavedWork(r) {
    var steps = r && Array.isArray(r.process) ? r.process : [];
    if (steps.length === 0) { return null; }
    var w = { reads: [], writes: [], writesNoPath: 0, edits: 0, commands: [], thinkChars: 0, steps: 0 };
    var readSeen = {}, writeSeen = {};
    steps.forEach(function (st) {
      if (!st) { return; }
      var tool = String(st.tool || "");
      var detail = String(st.detail == null ? "" : st.detail);
      w.thinkChars += String(st.think == null ? "" : st.think).length;
      if (SAVED_READ_TOOLS[tool]) {
        w.steps++;
        if (savedLooksLikePath(detail) && !savedIsInternalPath(detail)) {
          var rp = savedNormPath(detail);
          if (!readSeen[rp]) { readSeen[rp] = true; w.reads.push(rp); }
        }
      } else if (SAVED_WRITE_TOOLS[tool]) {
        w.steps++;
        if (savedLooksLikePath(detail)) {
          if (!savedIsInternalPath(detail)) {
            var wp = savedNormPath(detail);
            if (!writeSeen[wp]) { writeSeen[wp] = true; w.writes.push(wp); }
          }
        } else { w.writesNoPath++; }
      } else if (SAVED_EDIT_TOOLS[tool]) {
        w.steps++;
        if (!(savedLooksLikePath(detail) && savedIsInternalPath(detail))) { w.edits++; }
      } else if (tool === "run_command") {
        w.steps++;
        w.commands.push(detail);
      }
      // manage_task · schedule 등 기다림·관리용 호출은 일의 분량이 아니라서 세지 않는다.
    });
    return w;
  }

  // 분석 결과와 파일 크기 지도(경로 -> 바이트, -1 은 없음)로 "Claude 가 직접 했다면" 쓸 토큰을 부분별로 어림한다.
  function estimateDirectTokens(work, sizes) {
    sizes = sizes || {};
    var read = 0;
    work.reads.forEach(function (p) {
      var sz = sizes[p];
      read += (typeof sz === "number" && sz >= 0) ? Math.min(bytesToTokens(sz), SAVED_READ_CAP_TOKENS) : SAVED_READ_DEFAULT_TOKENS;
    });
    var write = 0;
    work.writes.forEach(function (p) {
      var sz = sizes[p];
      write += (typeof sz === "number" && sz >= 0) ? bytesToTokens(sz) : SAVED_WRITE_DEFAULT_TOKENS;
    });
    write += work.writesNoPath * SAVED_WRITE_DEFAULT_TOKENS;
    var edit = work.edits * SAVED_EDIT_TOKENS;
    var cmd = 0;
    work.commands.forEach(function (c) { cmd += estimateTextTokens(c) + SAVED_CMD_RESULT_TOKENS; });
    var think = Math.ceil(work.thinkChars / 4) * 2;   // 생각 글은 대부분 영문이라 4자에 1토큰, 요약본이라 × 2
    var steps = work.steps * SAVED_STEP_TOKENS;
    return { read: read, write: write, edit: edit, cmd: cmd, think: think, steps: steps, total: read + write + edit + cmd + think + steps };
  }

  // 파일 크기 지도. 서버(/api/qa/file-sizes)에서 받아 채운다. 받기 전에는 기본값으로 어림하고, 받으면 다시 그린다.
  var savedFileSizes = {};
  var savedSizeRequested = {};
  function savedMissingPaths(records) {
    var out = [];
    (Array.isArray(records) ? records : []).forEach(function (r) {
      if (!isOkStatus(r)) { return; }
      var w = analyzeSavedWork(r);
      if (!w) { return; }
      w.reads.concat(w.writes).forEach(function (p) {
        if (!Object.prototype.hasOwnProperty.call(savedFileSizes, p) && !savedSizeRequested[p]) { savedSizeRequested[p] = true; out.push(p); }
      });
    });
    return out;
  }
  function requestSavedFileSizes(records) {
    var paths = savedMissingPaths(records);
    if (paths.length === 0 || typeof fetch !== "function") { return Promise.resolve(false); }
    var chunks = [];
    for (var i = 0; i < paths.length; i += 300) { chunks.push(paths.slice(i, i + 300)); }
    return Promise.all(chunks.map(function (chunk) {
      return fetch("/api/qa/file-sizes", { method: "POST", headers: { "X-Samjil-Viewer": "1", "Content-Type": "application/json" }, body: JSON.stringify({ paths: chunk }) })
        .then(function (res) { return res.ok ? res.json() : null; })
        .then(function (data) {
          var got = data && data.sizes ? data.sizes : {};
          chunk.forEach(function (p) { savedFileSizes[p] = typeof got[p] === "number" ? got[p] : -1; });
          return true;
        })
        .catch(function () { chunk.forEach(function (p) { savedSizeRequested[p] = false; }); return false; });
    })).then(function (rs) { return rs.some(Boolean); });
  }

  // 성공한 위임 한 건의 Claude 토큰 절약 어림. 어림할 수 없으면(실패 · 과정 없음) null.
  function savedTokensOf(r) {
    if (!isOkStatus(r)) { return null; }
    var w = analyzeSavedWork(r);
    if (!w) { return null; }
    var d = estimateDirectTokens(w, savedFileSizes);
    var asked = estimateTextTokens(r.question);
    return { saved: Math.max(0, d.total - asked), direct: d.total, asked: asked, parts: d, reads: w.reads.length, writes: w.writes.length + w.writesNoPath, edits: w.edits, commands: w.commands.length };
  }

  // 여러 건의 합. 센 건수와 함께 돌려준다.
  function sumSavedTokens(items) {
    var saved = 0, count = 0;
    (Array.isArray(items) ? items : []).forEach(function (r) {
      var s = savedTokensOf(r);
      if (s) { saved += s.saved; count++; }
    });
    return { saved: saved, count: count };
  }

  function sumClaudeSavedTokens(items) {
    var saved = 0, count = 0;
    (Array.isArray(items) ? items : []).forEach(function (r) {
      if (r && r.claude && typeof r.claude.saved === "number") {
        saved += r.claude.saved;
        count++;
      }
    });
    return { saved: saved, count: count };
  }

  // 어림한 절약량(saved)을 증감으로 뒤집어 부호와 k·M 단위로 보인다: + 는 직접 했을 때보다 늘어남(더 소모), - 는 줄어듦(절약). 0 은 "0k".
  function savedDeltaShort(saved) {
    var d = -Math.round(Number(saved) || 0);
    if (d === 0) { return "0k"; }
    if (Math.abs(d) < 1000) { return (d > 0 ? "+" : "-") + Math.abs(d); }   // 1k 미만은 0.0k 로 뭉개지 않고 그대로
    return (d > 0 ? "+" : "-") + formatTokenCompact(Math.abs(d));
  }
  function savedTokensText(n) { return "Claude 토큰 증감 ≈ " + savedDeltaShort(n) + " (예상)"; }
  var SAVED_TOKENS_NOTE = "같은 일을 Claude 가 직접 했다면 쓸 분량을 agy 가 남긴 과정(읽은 파일·쓴 파일·명령·생각)에서 어림하고, 위임하느라 쓴 질문 분량을 뺀 예상값입니다. 증감의 부호: - 는 직접 했을 때보다 줄어든 것(절약), + 는 늘어난 것(더 소모)입니다. 실제 Claude 사용량은 이 도구가 잴 수 없습니다.";
  function savedTokensDetail(sv) {
    return SAVED_TOKENS_NOTE + " 직접 했다면 약 " + sv.direct.toLocaleString() + " (읽기 " + sv.parts.read.toLocaleString() + " · 쓰기 " + (sv.parts.write + sv.parts.edit).toLocaleString() +
      " · 명령 " + sv.parts.cmd.toLocaleString() + " · 생각 " + sv.parts.think.toLocaleString() + " · 도구 호출 " + sv.parts.steps.toLocaleString() + ") − 질문 약 " + sv.asked.toLocaleString() +
      " · 읽은 파일 " + sv.reads + "개 · 쓴 파일 " + sv.writes + "개 · 고친 곳 " + sv.edits + "곳 · 명령 " + sv.commands + "회";
  }

  // 진행 중인 위임의 절약 예상: 지금까지 모은 과정(liveProc 의 단계)과 질문으로 끝난 카드와 같은 방식으로 어림한다. 단계가 아직 없으면 null.
  function liveSavedOf(p) {
    if (!p) { return null; }
    var opts = pendingProcessOpts(p, []);
    var steps = opts && Array.isArray(opts.steps) ? opts.steps : [];
    if (steps.length === 0) { return null; }
    return savedTokensOf({ status: "OK", question: p.question, process: steps });
  }

  // 새 단계나 파일 크기가 들어오면 진행 중 카드의 절약 표시를 제자리에서 고친다(카드를 다시 그리지 않는다).
  function refreshLiveSaved() {
    var nodes = document.querySelectorAll("[data-saved-live]");
    for (var i = 0; i < nodes.length; i++) {
      var id = nodes[i].getAttribute("data-saved-live");
      var p = null;
      for (var j = 0; j < pendingItems.length; j++) { if (pendingItems[j] && pendingItems[j].task_id === id) { p = pendingItems[j]; break; } }
      var sv = liveSavedOf(p);
      if (!sv) { continue; }
      var inner = nodes[i].querySelector(".pg-saved");
      if (inner) { inner.textContent = savedTokensText(sv.saved); inner.title = savedTokensDetail(sv); }
      nodes[i].hidden = false;
    }
  }

  // 파일 크기가 도착해 값이 바뀌면 지금 화면의 토큰 절약 표시(카드 · 칩 · 대시보드)를 다시 계산한다.
  function refreshSavedViews() {
    var byKey = {};
    allItems.forEach(function (r) { byKey[tokenRecordKey(r)] = r; });
    var nodes = document.querySelectorAll("[data-saved-task]");
    for (var i = 0; i < nodes.length; i++) {
      var r = byKey[nodes[i].getAttribute("data-saved-task")];
      var sv = r ? savedTokensOf(r) : null;
      if (sv) {
        if (nodes[i].classList.contains("tok-item")) { setTokItem(nodes[i], "Claude 토큰 증감", "≈ " + savedDeltaShort(sv.saved), "예상"); } else { nodes[i].textContent = savedTokensText(sv.saved); }
        nodes[i].title = savedTokensDetail(sv);
      }
    }
    refreshLiveSaved();
    if (currentNav === "dashboard") { renderStats(); } else if (currentNav === "qa") { updateQaHeader(); }
  }

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

  // 모델 ID(+노력)를 화면 이름으로. agy(Gemini) 모델 ID 는 이름에 노력이 들어 있다("Gemini 3.8 Flash (High)").
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
  //   둘 다 모르면 위임 때 고른 단계(tier)로 gemini-3.8-flash-<tier> 를 짐작한다(inferred).
  function handoffDispatchResolver(channelData, records, pendings) {
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

  // 방향 표시: 모델명으로 "Claude Opus 5.5 → Gemini 3.8 Flash (High)". 채널 정보가 없으면 예전처럼 Claude/agy.
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

  function renderAttention() {
    if (!els.dashAttention) return;
    var items = [];

    handoffProjects.forEach(function (p) {
      var m = p.latestMsg;
      if (m && (m.status === "보냄" || m.status === "읽음")) {
        items.push({ time: m.time || p.updated || "", node: function () { return handoffRow(p.name, m); } });
      }
    });

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
              (recordModel(r) ? '<span>' + escapeHtml(recordModel(r)) + '</span>' : "") +
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
      els.dashAttention.innerHTML = '<li class="row-empty">확인할 항목이 없습니다. 처리를 기다리는 협의 메시지나 최근 24시간 안에 실패한 위임이 생기면 여기에 나옵니다.</li>';
      return;
    }
    var frag = document.createDocumentFragment();
    items.forEach(function (it) { frag.appendChild(it.node()); });
    els.dashAttention.appendChild(frag);
  }

  function renderTimeline() {
    if (!els.dashTimeline) return;
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
              (recordModel(r) ? '<span>' + escapeHtml(recordModel(r)) + '</span>' : "") +
              '<span>' + escapeHtml(r.session || "단발성") + '</span>',
            sideHtml: qaStatusBadge(r),
            onClick: goQaSession(r)
          });
        }
      });
    });

    handoffProjects.forEach(function (p) {
      var m = p.latestMsg;
      if (!m) return;
      entries.push({ time: m.time || p.updated || "", node: function () { return handoffRow(p.name, m, "협의"); } });
    });

    entries.sort(function (a, b) { return String(b.time).localeCompare(String(a.time)); });
    entries = entries.slice(0, 10);

    els.dashTimeline.innerHTML = "";
    if (entries.length === 0) {
      els.dashTimeline.innerHTML = '<li class="row-empty">아직 기록이 없습니다. Claude가 agy에 작업을 위임하거나 협의 메시지를 보내면 여기에 쌓입니다.</li>';
      return;
    }
    var frag = document.createDocumentFragment();
    entries.forEach(function (e) { frag.appendChild(e.node()); });
    els.dashTimeline.appendChild(frag);
  }

  function renderStats() {
    var totalQa = allItems.length;
    var okCount = 0;
    var errCount = 0;
    var todayCount = 0;
    var totalElapsed = 0;
    var elapsedItemCount = 0;
    var todayKey = localDateKey(new Date());
    var modelUsage = {};
    var savedAll = 0, savedToday = 0, savedCount = 0;

    allItems.forEach(function (r) {
      if (isOkStatus(r)) { okCount++; } else if (r.status) { errCount++; }
      if (r.timestamp && String(r.timestamp).slice(0, 10) === todayKey) { todayCount++; }
      var sv = savedTokensOf(r);
      if (sv) {
        savedAll += sv.saved; savedCount++;
        if (r.timestamp && String(r.timestamp).slice(0, 10) === todayKey) { savedToday += sv.saved; }
      }
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

    var totalHandoffMsgs = 0;
    handoffProjects.forEach(function (p) { totalHandoffMsgs += (p.msgCount || 0); });

    if (els.dashStats) {
      var stats = [
        ["누적 위임", totalQa.toLocaleString() + "건"],
        ["오늘", todayCount + "건"],
        ["성공률", successRate],
        ["평균 소요", avgSec],
        ["Claude 토큰 증감(예상)", savedCount > 0 ? "≈ " + savedDeltaShort(savedAll) : "-", SAVED_TOKENS_NOTE + " 성공한 위임 " + savedCount.toLocaleString() + "건 기준"],
        ["오늘 토큰 증감(예상)", savedCount > 0 ? "≈ " + savedDeltaShort(savedToday) : "-", SAVED_TOKENS_NOTE],
        ["협의 채널", handoffProjects.length + "개"],
        ["메시지", totalHandoffMsgs.toLocaleString() + "개"]
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
        if (!qaItemMatchesSelection(p, claudeTree, currentQaProject, currentQaSession)) return false;
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
      if (!qaItemMatchesSelection(r, claudeTree, currentQaProject, currentQaSession)) return false;
      if (!qaItemMatchesAgy(r, currentQaAgy)) return false;
      if (model && recordModel(r) !== model) return false;
      if (status) {
        var st = (r.status == null ? "" : String(r.status)).trim();
        if (status === "OK" && st !== "OK") return false;
        if (status === "ERROR" && st === "OK") return false;
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
    if (els.chipQaSaved) {
      var cSaved = sumClaudeSavedTokens(filteredQa);
      if (cSaved.count > 0) {
        var sign = cSaved.saved <= 0 ? "-" : "+";   // 증감: + 증가(더 소모), - 감소(절약)
        var absVal = Math.abs(cSaved.saved);
        var shortVal = formatTokenCompact(absVal);
        els.chipQaSaved.textContent = "Claude 토큰 증감 " + sign + shortVal + " (실측 기반 " + cSaved.count.toLocaleString() + "건)";
        els.chipQaSaved.title = "지금 보이는 위임 중 실측 연결된 " + cSaved.count.toLocaleString() + "건의 증감 합계입니다. 직접 했다면 예상보다 + 는 늘어난 것(더 소모), - 는 줄어든 것(절약)입니다.";
      } else {
        var sumSv = sumSavedTokens(filteredQa);
        els.chipQaSaved.textContent = sumSv.count > 0 ? savedTokensText(sumSv.saved) : "Claude 토큰 증감: -";
        els.chipQaSaved.title = SAVED_TOKENS_NOTE + (sumSv.count > 0 ? " 지금 보이는 성공한 위임 " + sumSv.count.toLocaleString() + "건의 합계" : "");
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
    if (!hasKatex) {
      var rawHtml = window.marked.parse(text);
      return window.DOMPurify && typeof window.DOMPurify.sanitize === "function" ?
        window.DOMPurify.sanitize(rawHtml, { ADD_TAGS: ["input"], ADD_ATTR: ["type", "checked", "disabled"] }) : rawHtml;
    }

    var mathList = [];

    // 1. 코드 블록(```...```) 및 인라인 코드(`...`) 임시 보호
    var codeBlocks = [];
    var s = String(text).replace(/(```[\s\S]*?```|`[^`\n]*?`)/g, function (match) {
      var ph = "%%%CBLOCK_" + codeBlocks.length + "%%%";
      codeBlocks.push(match);
      return ph;
    });

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

    // 4. 코드 블록 복원
    codeBlocks.forEach(function (code, i) {
      s = s.replace("%%%CBLOCK_" + i + "%%%", function () { return code; });
    });

    // 5. 마크다운 변환
    var html = window.marked.parse(s);

    // 6. DOMPurify 정제 (수식 플레이스홀더 및 task-list 체크박스 보존)
    if (window.DOMPurify && typeof window.DOMPurify.sanitize === "function") {
      html = window.DOMPurify.sanitize(html, { ADD_TAGS: ["input"], ADD_ATTR: ["type", "checked", "disabled"] });
    }

    // 7. KaTeX 수식 HTML 치환
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

  // 위임 한 건의 토큰 줄. 기록에 값이 있는 항목만 보여 주고, 하나도 없으면 줄 자체를 만들지 않는다.
  //   총 토큰 = 입력 + 출력(출력에는 사고 토큰이 이미 들어 있다. 그래서 따로 더하지 않고 "응답 · 사고"로 나눠 보여 준다).
  //   입력의 "(캐시 X)" 와 "현재 컨텍스트"(그 호출의 마지막 턴이 보낸 입력 크기)는 위임 기록 DB 에 없어 서버가 대화 기록에서 계산해 준다(받은 뒤에 채운다).
  var recordContexts = {};        // "<대화 id>|<마지막 단계 번호>" -> { cache, context }
  var recordContextRequested = {};

  function recordLastStep(r) {
    var steps = r && Array.isArray(r.process) ? r.process : [];
    var max = 0;
    steps.forEach(function (st) { var n = Number(st && st.n); if (!isNaN(n) && n > max) { max = n; } });
    // 과정의 마지막 단계는 마지막 도구 호출이다. 그 결과(+1) 다음의 최종 응답 턴(+2)까지가 이 호출의 몫이다(위임 기록의 입력·출력 합과 같아진다).
    return max > 0 ? max + 2 : 0;
  }
  function recordContextKey(r) { return r && r.session_id ? String(r.session_id) + "|" + recordLastStep(r) : ""; }

  function tokenMetaItems(r) {
    var num = function (v) { var n = Number(v); return (!v || isNaN(n)) ? 0 : n; };
    var total = num(r.total_tokens), input = num(r.input_tokens), output = num(r.output_tokens), thinking = num(r.thinking_tokens);
    var ctxInfo = recordContexts[recordContextKey(r)] || null;
    var items = [];
    // 항목마다: label(이름) · value(값) · sub(덧붙임. 없으면 빈 글자) · text(셋을 합친 글자) · title(설명) · cls(항목 모양)
    var add = function (label, value, sub, title, cls) { items.push({ label: label, value: value, sub: sub, text: label + " " + value + (sub ? " (" + sub + ")" : ""), title: title, cls: cls || "" }); };
    if (total) { add("총 토큰", total.toLocaleString(), "", "총 토큰 = 입력 + 출력(캐시 읽기와 사고는 따로 더하지 않습니다)", "tok-total"); }
    if (input) {
      add("입력", input.toLocaleString(), ctxInfo && ctxInfo.cache > 0 ? "캐시 " + ctxInfo.cache.toLocaleString() : "",
        "이 위임 호출이 쓴 입력 토큰(캐시 밖). 괄호는 캐시에서 읽은 입력으로 총 토큰에는 넣지 않습니다.");
    }
    if (output) {
      add("출력", output.toLocaleString(), thinking > 0 ? "응답 " + Math.max(0, output - thinking).toLocaleString() + " · 사고 " + thinking.toLocaleString() : "",
        "이 위임 호출이 쓴 출력 토큰. 사고(thinking) 토큰이 이미 들어 있어서 응답과 사고로 나눠 보여 줍니다.");
    }
    if (ctxInfo && ctxInfo.context > 0) {
      add("현재 컨텍스트", Number(ctxInfo.context).toLocaleString(), "", "이 호출의 마지막 턴이 모델에 보낸 입력 하나의 크기(캐시 포함). 누적 토큰과 다른, 지금 대화의 크기입니다.");
    }
    return items;
  }

  // 토큰 줄의 항목 하나: 이름(흐리게) · 값(진하게) · 덧붙임(작고 흐리게)을 나눠 그려 눈으로 구분되게 한다.
  function setTokItem(el, label, value, sub) {
    while (el.firstChild) { el.removeChild(el.firstChild); }
    var l = document.createElement("span"); l.className = "tok-label"; l.textContent = label; el.appendChild(l);
    var v = document.createElement("b"); v.className = "tok-val"; v.textContent = value; el.appendChild(v);
    if (sub) { var s = document.createElement("span"); s.className = "tok-sub"; s.textContent = sub; el.appendChild(s); }
  }
  function buildTokItem(label, value, sub, title, cls) {
    var el = document.createElement("span");
    el.className = "tok-item" + (cls ? " " + cls : "");
    if (title) { el.title = title; }
    setTokItem(el, label, value, sub);
    return el;
  }

  // "agy 토큰 보기"를 눌러 펼친 카드의 기록 키. 5초마다 카드가 다시 그려져도 펼친 상태를 이어 가려고 기억한다.
  var agyTokOpen = {};
  function agyTokLabel(open) { return (open ? "agy 토큰 접기" : "agy 토큰 보기") + (open ? " ▾" : " ▸"); }
  // "계산 정보 보기": 호출 수 · 다른 작업 제외 · 실측 여부 · 몫. 줄이 길어져 줄바꿈이 생기던 보조 정보를 펼침 메뉴로 옮겼다. 펼친 상태도 5초 갱신에서 유지한다.
  var calcTokOpen = {};
  function calcTokLabel(open) { return (open ? "계산 정보 접기" : "계산 정보 보기") + (open ? " ▾" : " ▸"); }

  function fillTokenMeta(row, r) {
    var tokKey = tokenRecordKey(r);
    var wasExpanded = Boolean(agyTokOpen[tokKey]);
    var existingBtn = row.querySelector(".btn-toggle-agy-tok");
    if (existingBtn && existingBtn.getAttribute("aria-expanded") === "true") {
      wasExpanded = true;
    }

    while (row.firstChild) { row.removeChild(row.firstChild); }

    var claudeLine = document.createElement("div");
    claudeLine.className = "token-claude-line";

    var claudeTimeLine = null;
    var calcItems = [];   // 펼침 메뉴("계산 정보")에 들어갈 보조 항목

    if (r && r.claude) {
      var nTasks = r.claude.tasks_in_turn || 1;
      if (nTasks >= 2) {
        var turnEstStr = "";
        var estTurn = r.claude.est_direct_turn != null ? r.claude.est_direct_turn : r.claude.est_direct_adj;
        if (estTurn != null) {
          turnEstStr = "직접 했다면 예상은 턴 전체 " + formatTokenK(estTurn, false);
          if (r.claude.est_direct != null && r.claude.est_direct !== estTurn) {
            turnEstStr += "(예상 " + formatTokenK(r.claude.est_direct, false) + "을 보정 비율로 나눔)";
          }
          turnEstStr += ", ";
        }
        var turnUsedVal = r.claude.used_turn != null ? r.claude.used_turn : r.claude.used;
        var turnUsedStr = "턴에 Claude가 실제 쓴 토큰은 " + formatTokenK(turnUsedVal != null ? turnUsedVal : 0, false);
        var sharePctVal = r.claude.share != null ? (r.claude.share * 100).toFixed(1) : "0.0";
        claudeLine.title = "이 턴에 위임 " + nTasks + "건을 함께 보냈습니다. " + turnEstStr + turnUsedStr + "이며 이 카드는 agy 작업량 비율 " + sharePctVal + "% 만큼 가집니다.";
      } else {
        claudeLine.title = "그 턴 전체를 위임들의 agy 작업량 비율로 나눈 값입니다";
      }

      var head = buildTokItem("토큰", "", "", "Claude 가 쓴 토큰입니다. agy 가 쓴 토큰은 오른쪽 버튼으로 봅니다.", "tok-claude-head");
      claudeLine.appendChild(head);

      var estDirectVal = r.claude.est_direct_share != null ? r.claude.est_direct_share : (nTasks === 1 ? r.claude.est_direct_adj : r.claude.est_direct);
      var estVal = estDirectVal != null ? formatTokenK(estDirectVal, false) : "—";
      claudeLine.appendChild(buildTokItem("직접", estVal, "", "직접 했다면 들었을 Claude 토큰 예상(지난 기록으로 보정한 추정값)", "tok-col"));

      var usedVal = r.claude.used != null ? formatTokenK(r.claude.used, false) : "—";
      var sv = r.claude.saved;
      var estDelShare = r.claude.est_delegate_share;
      if (estDelShare != null) {
        claudeLine.appendChild(buildTokItem("위임", formatTokenK(estDelShare, false), "", "위임했을 때 들 것으로 예상한 Claude 토큰(지난 기록으로 보정한 추정값)", "tok-col"));
      }
      claudeLine.appendChild(buildTokItem("실제", usedVal, "", "위임하고 Claude 가 실제로 쓴 토큰(위임과 무관한 호출은 뺀 값)", "tok-col"));
      // 식: 실제 - 직접 = 변화. + 는 직접 했을 때보다 늘어남(주황), - 는 줄어듦(절약, 초록)
      if (estDirectVal != null && r.claude.used != null && sv != null) {
        var tokDelta = r.claude.used - estDirectVal;
        var fx = document.createElement("span");   // 식은 한 덩어리: 줄이 모자라면 식 전체가 다음 줄로 넘어간다
        fx.className = "tok-formula";
        fx.appendChild(buildTokItem("", "=>", "", "", "tok-op tok-arrow"));
        fx.appendChild(buildTokItem("", usedVal, "", "", "tok-f-a"));
        fx.appendChild(buildTokItem("", "-", "", "", "tok-op"));
        fx.appendChild(buildTokItem("", estVal, "", "", "tok-f-b"));
        fx.appendChild(buildTokItem("", "=", "", "", "tok-op"));
        var deltaTitle = "실제 " + usedVal + " - 직접 " + estVal + " = " + (tokDelta > 0 ? "+" : tokDelta < 0 ? "-" : "+") + formatTokenK(Math.abs(tokDelta), false) +
          "\n+ 는 직접 했을 때보다 토큰이 늘어난 것, - 는 줄어든 것(절약)입니다. 직접 했다면 예상은 지난 기록으로 보정한 추정값입니다.";
        if (tokDelta > 0) {
          fx.appendChild(buildTokItem("", "+" + formatTokenK(tokDelta, false), "", deltaTitle, "saved-err tok-f-r"));
        } else if (tokDelta < 0) {
          fx.appendChild(buildTokItem("", "-" + formatTokenK(-tokDelta, false), "", deltaTitle, "saved-ok tok-f-r"));
        } else {
          fx.appendChild(buildTokItem("", "+0.0k", "", deltaTitle, "tok-dim tok-f-r"));
        }
        claudeLine.appendChild(fx);
      } else if (sv == null) {
        claudeLine.appendChild(buildTokItem("", "—", "", "", "saved-none"));
      }

      var callsCount = (r.claude.calls_related != null ? r.claude.calls_related : (r.claude.calls || 0));
      var callsText = "호출 " + callsCount + "회";
      calcItems.push(buildTokItem("", callsText, "", "위임과 관련된 Claude 도구 호출 수입니다(위임과 무관한 호출은 뺀 값).", "tok-aux"));

      if (r.claude.other_calls && r.claude.other_calls > 0) {
        var otherTokK = (r.claude.other_tokens && r.claude.other_tokens > 0) ? formatTokenK(r.claude.other_tokens, true) : "+0.0k";
        var excludedText = "다른 작업 " + r.claude.other_calls + "회·" + otherTokK + " 제외";
        var excludedTitle = "이 턴에서 위임과 무관한 호출은 위임 비용에서 뺐습니다";
        calcItems.push(buildTokItem("", excludedText, "", excludedTitle, "tok-aux tok-other-excluded"));
      }

      var basisText = r.claude.basis === "measured" ? "실측" : "일부 추정";
      calcItems.push(buildTokItem("", basisText, "", r.claude.basis === "measured" ? "Claude 대화 기록으로 실제로 잰 값입니다." : "답변 끝의 예상이 없어 일부는 추정한 값입니다.", "tok-aux"));

      if (nTasks >= 2 && r.claude.share != null) {
        var pctText = "몫 " + (r.claude.share * 100).toFixed(1) + "%";
        calcItems.push(buildTokItem("", pctText, "", "한 턴에 위임을 여러 건 보냈을 때 이 위임이 가진 몫입니다(agy 작업량 비율).", "tok-aux token-claude-share"));
      }

      // F2 절: 위임 카드 시간 줄 (시간 · 직접 했다면 예상 A · 위임 예상 B · agy 처리 실제 C)
      // Claude 의 시간 예상(est_time_delegate)이 있을 때만 줄을 보인다
      var estDelTime = r.claude.est_time_delegate_share != null ? r.claude.est_time_delegate_share : (r.claude.est_time_delegate != null ? r.claude.est_time_delegate : null);
      if (estDelTime != null || r.claude.anomaly) {
        var estDirTime = r.claude.est_time_direct_share != null ? r.claude.est_time_direct_share : (r.claude.est_time_direct != null ? r.claude.est_time_direct : null);
        var agyTime = r.elapsed_sec != null ? r.elapsed_sec : (r.claude.elapsed_sec != null ? r.claude.elapsed_sec : null);
        // 실제 = 위임에 걸린 전체 시간(agy 처리 + Claude 쪽). 서버가 못 주면 agy 처리 시간만 쓴다.
        var actTime = r.claude.total_sec != null ? r.claude.total_sec : agyTime;
        var actTip = r.claude.total_sec != null
          ? "위임에 실제로 걸린 시간(agy 처리 " + (agyTime != null ? formatTimeKo(agyTime) : "—") + " / Claude 쪽 " + (r.claude.claude_sec != null ? formatTimeKo(r.claude.claude_sec) : "—") + " 를 더한 값)"
          : "agy 가 실제로 처리한 시간(Claude 쪽 시간은 아직 모름)";
        if (agyTime != null) { calcItems.push(buildTokItem("", "agy 처리 " + formatTimeKo(agyTime), "", "agy 가 작업을 처리한 시간입니다.", "tok-aux")); }
        if (r.claude.claude_sec != null) { calcItems.push(buildTokItem("", "Claude 쪽 " + formatTimeKo(r.claude.claude_sec), "", "그 턴에서 위임에 쓴 Claude 시간(턴 시간 × 위임 관련 호출 비율)입니다. agy 를 기다린 시간이 일부 들어 있을 수 있어 합산한 실제 시간은 그만큼 겹쳐 센 근사값입니다.", "tok-aux")); }

        claudeTimeLine = document.createElement("div");
        claudeTimeLine.className = "token-claude-line token-claude-time-line";
        claudeTimeLine.appendChild(buildTokItem("시간", "", "", "", "tok-claude-head"));
        if (estDirTime != null) {
          claudeTimeLine.appendChild(buildTokItem("직접", formatTimeKo(estDirTime), "", "직접 했다면 걸렸을 시간 예상", "tok-col"));
        }
        if (estDelTime != null) {
          claudeTimeLine.appendChild(buildTokItem("위임", formatTimeKo(estDelTime), "", "위임했을 때 걸릴 시간 예상(agy 처리 + Claude 가 보내고 검토하는 시간)", "tok-col"));
        }
        if (actTime != null) {
          claudeTimeLine.appendChild(buildTokItem("실제", formatTimeKo(actTime), "", actTip, "tok-col"));
        }
        // 식: 실제 - 직접 = 변화. + 는 직접 했을 때보다 오래 걸림(주황), - 는 짧아짐(초록)
        if (estDirTime != null && actTime != null) {
          var timeDelta = actTime - estDirTime;
          var tfx = document.createElement("span");
          tfx.className = "tok-formula";
          tfx.appendChild(buildTokItem("", "=>", "", "", "tok-op tok-arrow"));
          tfx.appendChild(buildTokItem("", formatTimeKo(actTime), "", "", "tok-f-a"));
          tfx.appendChild(buildTokItem("", "-", "", "", "tok-op"));
          tfx.appendChild(buildTokItem("", formatTimeKo(estDirTime), "", "", "tok-f-b"));
          tfx.appendChild(buildTokItem("", "=", "", "", "tok-op"));
          var timeTitle = "실제 " + formatTimeKo(actTime) + " - 직접 " + formatTimeKo(estDirTime) + " = " + (timeDelta < 0 ? "-" : "+") + formatTimeKo(Math.abs(timeDelta)) +
            "\n+ 는 직접 했을 때보다 오래 걸린 것, - 는 짧아진 것입니다.";
          if (Math.abs(timeDelta) < 5) {
            tfx.appendChild(buildTokItem("", "+0초", "", timeTitle, "tok-dim tok-f-r"));
          } else if (timeDelta > 0) {
            tfx.appendChild(buildTokItem("", "+" + formatTimeKo(timeDelta), "", timeTitle, "saved-err tok-f-r"));
          } else {
            tfx.appendChild(buildTokItem("", "-" + formatTimeKo(-timeDelta), "", timeTitle, "saved-ok tok-f-r"));
          }
          claudeTimeLine.appendChild(tfx);
        }
        if (r.claude.anomaly) {
          var anomMap = {
            agy_slow: "agy 지연",
            scope: "예상 범위 불일치",
            weak_estimate: "근거 약한 예상",
            unknown: "원인 모름"
          };
          var anomText = anomMap[r.claude.anomaly] || r.claude.anomaly;
          var anomSpan = document.createElement("span");
          anomSpan.className = "anomaly-pill";
          anomSpan.textContent = "이상치 · " + anomText;
          anomSpan.title = "예상과 실제가 최근 같은 경로 턴들보다 크게 다릅니다. 보정 식은 이 건에 흔들리지 않습니다.";
          var calcBtnInTime = claudeTimeLine.querySelector(".btn-toggle-calc");
          if (calcBtnInTime) {
            claudeTimeLine.insertBefore(anomSpan, calcBtnInTime);
          } else {
            claudeTimeLine.appendChild(anomSpan);
          }
        }
      }
    } else {
      // 아직 Claude 쪽 사용량이 연결되지 않은 카드(끝난 직후, 수집기가 돌기 전): 완성된 카드와 같은 두 줄(토큰 / 시간) 구조를 두고
      // 아직 모르는 값은 — 로 둔다. 수집기가 돌아 연결되면 같은 자리에 값이 채워진다. agy 작업량으로 어림한 증감이 있으면 결과 자리에 흐리게 보인다.
      var waitTip = "아직 이 위임을 보낸 Claude 쪽 사용량과 연결되지 않았습니다. 수집기가 돈 뒤(보통 몇 분 안)에 채워집니다.";
      claudeLine.appendChild(buildTokItem("토큰", "", "", "Claude 가 쓴 토큰입니다. agy 가 쓴 토큰은 오른쪽 버튼으로 봅니다.", "tok-claude-head"));
      claudeLine.appendChild(buildTokItem("직접", "—", "", waitTip, "tok-col tok-dim"));
      claudeLine.appendChild(buildTokItem("위임", "—", "", waitTip, "tok-col tok-dim"));
      claudeLine.appendChild(buildTokItem("실제", "—", "", waitTip, "tok-col tok-dim"));
      var fxU = document.createElement("span");
      fxU.className = "tok-formula";
      fxU.appendChild(buildTokItem("", "=>", "", "", "tok-op tok-arrow"));
      fxU.appendChild(buildTokItem("", "—", "", "", "tok-f-a tok-dim"));
      fxU.appendChild(buildTokItem("", "-", "", "", "tok-op"));
      fxU.appendChild(buildTokItem("", "—", "", "", "tok-f-b tok-dim"));
      fxU.appendChild(buildTokItem("", "=", "", "", "tok-op"));
      var svOld = savedTokensOf(r);
      if (svOld) {
        fxU.appendChild(buildTokItem("", "≈ " + savedDeltaShort(svOld.saved), "", "agy 작업량으로 어림한 증감(집계 전 임시값, 예상). " + savedTokensDetail(svOld), "tok-dim tok-f-r"));
      } else {
        fxU.appendChild(buildTokItem("", "집계 전", "", waitTip, "tok-dim tok-f-r"));
      }
      claudeLine.appendChild(fxU);

      claudeTimeLine = document.createElement("div");
      claudeTimeLine.className = "token-claude-line token-claude-time-line";
      claudeTimeLine.appendChild(buildTokItem("시간", "", "", "", "tok-claude-head"));
      var actU = (r && r.elapsed_sec != null && !isNaN(Number(r.elapsed_sec))) ? formatTimeKo(Number(r.elapsed_sec)) : "—";
      claudeTimeLine.appendChild(buildTokItem("직접", "—", "", waitTip, "tok-col tok-dim"));
      claudeTimeLine.appendChild(buildTokItem("위임", "—", "", waitTip, "tok-col tok-dim"));
      claudeTimeLine.appendChild(buildTokItem("실제", actU, "", "agy 가 실제로 처리한 시간", "tok-col"));
      var tfxU = document.createElement("span");
      tfxU.className = "tok-formula";
      tfxU.appendChild(buildTokItem("", "=>", "", "", "tok-op tok-arrow"));
      tfxU.appendChild(buildTokItem("", actU, "", "", "tok-f-a"));
      tfxU.appendChild(buildTokItem("", "-", "", "", "tok-op"));
      tfxU.appendChild(buildTokItem("", "—", "", "", "tok-f-b tok-dim"));
      tfxU.appendChild(buildTokItem("", "=", "", "", "tok-op"));
      tfxU.appendChild(buildTokItem("", "집계 전", "", waitTip, "tok-dim tok-f-r"));
      claudeTimeLine.appendChild(tfxU);
    }

    var calcDetails = null;
    if (calcItems.length > 0) {
      var wasCalcExpanded = Boolean(calcTokOpen[tokKey]);
      calcDetails = document.createElement("div");
      calcDetails.className = "token-agy-details token-calc-details";
      calcDetails.style.display = wasCalcExpanded ? "flex" : "none";
      calcDetails.setAttribute("aria-hidden", wasCalcExpanded ? "false" : "true");
      calcItems.forEach(function (it) { calcDetails.appendChild(it); });

      var calcBtn = document.createElement("button");
      calcBtn.type = "button";
      calcBtn.className = "btn-toggle-agy-tok btn-toggle-calc";
      calcBtn.textContent = calcTokLabel(wasCalcExpanded);
      calcBtn.setAttribute("aria-expanded", wasCalcExpanded ? "true" : "false");
      calcBtn.title = "계산에 쓴 정보(호출 수 · 다른 작업 제외 · 실측 여부 · 몫) 펼치기/접기";
      calcBtn.addEventListener("click", function (e) {
        e.stopPropagation();
        var next = this.getAttribute("aria-expanded") !== "true";
        this.setAttribute("aria-expanded", next ? "true" : "false");
        this.textContent = calcTokLabel(next);
        if (next) { calcTokOpen[tokKey] = true; } else { delete calcTokOpen[tokKey]; }
        calcDetails.style.display = next ? "flex" : "none";
        calcDetails.setAttribute("aria-hidden", next ? "false" : "true");
      });
      claudeLine.appendChild(calcBtn);
    }

    var agyDetails = document.createElement("div");
    agyDetails.className = "token-agy-details";
    agyDetails.style.display = wasExpanded ? "flex" : "none";
    agyDetails.setAttribute("aria-hidden", wasExpanded ? "false" : "true");

    var agyItems = tokenMetaItems(r);
    agyItems.forEach(function (it) {
      agyDetails.appendChild(buildTokItem(it.label, it.value, it.sub, it.title, it.cls));
    });

    if (agyItems.length > 0) {
      var toggleBtn = document.createElement("button");
      toggleBtn.type = "button";
      toggleBtn.className = "btn-toggle-agy-tok";
      toggleBtn.textContent = agyTokLabel(wasExpanded);
      toggleBtn.setAttribute("aria-expanded", wasExpanded ? "true" : "false");
      toggleBtn.title = "agy 세부 토큰(총 토큰·입력·출력·컨텍스트) 펼치기/접기";

      toggleBtn.addEventListener("click", function (e) {
        e.stopPropagation();
        var exp = this.getAttribute("aria-expanded") === "true";
        var next = !exp;
        this.setAttribute("aria-expanded", next ? "true" : "false");
        this.textContent = agyTokLabel(next);
        if (next) { agyTokOpen[tokKey] = true; } else { delete agyTokOpen[tokKey]; }
        agyDetails.style.display = next ? "flex" : "none";
        agyDetails.setAttribute("aria-hidden", next ? "false" : "true");
      });

      claudeLine.appendChild(toggleBtn);
    }

    row.appendChild(claudeLine);
    if (claudeTimeLine) {
      row.appendChild(claudeTimeLine);
    }
    if (calcDetails) {
      row.appendChild(calcDetails);
    }
    row.appendChild(agyDetails);
  }

  // 진행 중·대기 중 카드의 토큰 / 시간 줄. 끝난 카드(fillTokenMeta)와 같은 칸(직접 / 위임 / 실제 => 식)을 두고,
  // 아직 모르는 값은 — 로 둔다. 실제 토큰은 지금까지 위임에 쓴 Claude 토큰, 실제 시간은 실행 경과(1초마다 늘어남)이다.
  // 직접 예상은 위임을 보낸 턴의 답변 끝 예상이 있어야 생기므로 작업이 끝나고 수집기가 돈 뒤에 채워진다.
  function buildPendingTokenMeta(p, startMs, etaSec) {
    var row = document.createElement("div");
    row.className = "meta token-meta token-meta-pending";
    var cl = p && p.claude_live ? p.claude_live : null;
    var later = "작업이 끝나고 수집기가 돈 뒤에 채워집니다(위임을 보낸 턴의 답변 끝 예상으로 계산).";
    var running = "진행 중이라 아직 계산하지 않습니다. 끝나면 실제 - 직접 = 변화로 바뀝니다.";

    var line = document.createElement("div");
    line.className = "token-claude-line";
    line.appendChild(buildTokItem("토큰", "", "", "Claude 가 쓴 토큰입니다. agy 가 쓴 토큰은 끝난 뒤 버튼으로 봅니다.", "tok-claude-head"));
    line.appendChild(buildTokItem("직접", "—", "", later, "tok-col tok-dim"));
    var delTok = cl && cl.est_delegate != null && !isNaN(cl.est_delegate) ? formatTokenK(cl.est_delegate, false) : "—";
    line.appendChild(buildTokItem("위임", delTok, "", delTok === "—" ? later : "위임했을 때 들 것으로 예상한 Claude 토큰", "tok-col" + (delTok === "—" ? " tok-dim" : "")));
    var usedTok = cl && cl.used != null && !isNaN(cl.used) ? formatTokenK(cl.used, false) : "—";
    var usedTip = cl ? formatClaudeLiveMeta(cl) : null;
    line.appendChild(buildTokItem("실제", usedTok, "", usedTip ? usedTip.title : "아직 이 위임을 보낸 Claude 쪽 사용량과 연결되지 않았습니다.", "tok-col" + (usedTok === "—" ? " tok-dim" : "")));
    var fx = document.createElement("span");
    fx.className = "tok-formula";
    fx.appendChild(buildTokItem("", "=>", "", "", "tok-op tok-arrow"));
    fx.appendChild(buildTokItem("", usedTok, "", "", "tok-f-a" + (usedTok === "—" ? " tok-dim" : "")));
    fx.appendChild(buildTokItem("", "-", "", "", "tok-op"));
    fx.appendChild(buildTokItem("", "—", "", "", "tok-f-b tok-dim"));
    fx.appendChild(buildTokItem("", "=", "", "", "tok-op"));
    fx.appendChild(buildTokItem("", "진행 중", "", running, "tok-dim tok-f-r"));
    line.appendChild(fx);
    row.appendChild(line);

    var tl = document.createElement("div");
    tl.className = "token-claude-line token-claude-time-line";
    tl.appendChild(buildTokItem("시간", "", "", "", "tok-claude-head"));
    tl.appendChild(buildTokItem("직접", "—", "", later, "tok-col tok-dim"));
    var delTime = etaSec != null && etaSec > 0 ? formatDuration(etaSec) : "—";   // 실행 줄의 "예상 [..]" 과 같은 표기
    tl.appendChild(buildTokItem("위임", delTime, "", delTime === "—" ? later : "처음 예정 시간(같은 모델로 끝난 최근 위임의 보통 실행 시간)", "tok-col" + (delTime === "—" ? " tok-dim" : "")));
    var liveAct = function (cls) {
      var it = buildTokItem(cls ? "" : "실제", startMs != null ? formatDuration((Date.now() - startMs) / 1000) : "—", "", "실행 경과 시간(1초마다 갱신). 끝나면 agy 처리 + Claude 쪽 시간으로 바뀝니다.", cls || "tok-col");
      if (startMs != null) {
        it.classList.add("live-elapsed");
        it.setAttribute("data-start", String(startMs));
        it.setAttribute("data-label-prefix", "");
        var v = it.querySelector(".tok-val");
        if (v) { v.classList.add("mv"); }
      } else {
        it.classList.add("tok-dim");
      }
      return it;
    };
    tl.appendChild(liveAct(""));
    var tfx = document.createElement("span");
    tfx.className = "tok-formula";
    tfx.appendChild(buildTokItem("", "=>", "", "", "tok-op tok-arrow"));
    tfx.appendChild(liveAct("tok-f-a"));
    tfx.appendChild(buildTokItem("", "-", "", "", "tok-op"));
    tfx.appendChild(buildTokItem("", "—", "", "", "tok-f-b tok-dim"));
    tfx.appendChild(buildTokItem("", "=", "", "", "tok-op"));
    tfx.appendChild(buildTokItem("", "진행 중", "", running, "tok-dim tok-f-r"));
    tl.appendChild(tfx);

    // 끝난 카드와 같은 두 버튼(계산 정보 보기 / agy 토큰 보기). 진행 중에 아는 것만 계산 정보에 넣고, agy 토큰은 끝나야 알 수 있어 눌리지 않게 둔다.
    var calcItems = [];
    if (cl && cl.calls_related != null) { calcItems.push(buildTokItem("", "호출 " + cl.calls_related + "회", "", "지금까지 위임과 관련된 Claude 도구 호출 수입니다.", "tok-aux")); }
    else if (cl && cl.calls != null) { calcItems.push(buildTokItem("", "호출 " + cl.calls + "회", "", "지금까지 위임과 관련된 Claude 도구 호출 수입니다.", "tok-aux")); }
    if (cl && cl.other_calls > 0) {
      var oTok = (cl.other_tokens != null && cl.other_tokens > 0) ? formatTokenK(cl.other_tokens, true) : "+0.0k";
      calcItems.push(buildTokItem("", "다른 작업 " + cl.other_calls + "회·" + oTok + " 제외", "", "이 턴에서 위임과 무관한 호출은 위임 비용에서 뺐습니다", "tok-aux tok-other-excluded"));
    }
    calcItems.push(buildTokItem("", "진행 중", "", "끝나면 실측 여부와 몫이 채워집니다.", "tok-aux"));
    var calcKey = "p:" + (p.task_id || "");
    var calcOpen = Boolean(calcTokOpen[calcKey]);
    var calcDetails = document.createElement("div");
    calcDetails.className = "token-agy-details token-calc-details";
    calcDetails.style.display = calcOpen ? "flex" : "none";
    calcDetails.setAttribute("aria-hidden", calcOpen ? "false" : "true");
    calcItems.forEach(function (it) { calcDetails.appendChild(it); });
    var calcBtn = document.createElement("button");
    calcBtn.type = "button";
    calcBtn.className = "btn-toggle-agy-tok btn-toggle-calc";
    calcBtn.textContent = calcTokLabel(calcOpen);
    calcBtn.setAttribute("aria-expanded", calcOpen ? "true" : "false");
    calcBtn.title = "계산에 쓴 정보(호출 수 · 다른 작업 제외) 펼치기/접기";
    calcBtn.addEventListener("click", function (e) {
      e.stopPropagation();
      var next = this.getAttribute("aria-expanded") !== "true";
      this.setAttribute("aria-expanded", next ? "true" : "false");
      this.textContent = calcTokLabel(next);
      if (next) { calcTokOpen[calcKey] = true; } else { delete calcTokOpen[calcKey]; }
      calcDetails.style.display = next ? "flex" : "none";
      calcDetails.setAttribute("aria-hidden", next ? "false" : "true");
    });
    line.appendChild(calcBtn);
    var agyBtn = document.createElement("button");
    agyBtn.type = "button";
    agyBtn.className = "btn-toggle-agy-tok";
    agyBtn.textContent = agyTokLabel(false);
    agyBtn.disabled = true;
    agyBtn.title = "agy 가 쓴 토큰은 작업이 끝나면 볼 수 있습니다.";
    line.appendChild(agyBtn);

    row.appendChild(tl);
    row.appendChild(calcDetails);
    return row;
  }

  function buildTokenMeta(r) {
    var hasClaude = Boolean(r && r.claude);
    var hasAgy = Boolean(Number(r && r.total_tokens));
    var hasSaved = Boolean(savedTokensOf(r));
    if (!hasClaude && !hasAgy && !hasSaved) return null;
    var row = document.createElement("div");
    row.className = "meta token-meta";
    row.setAttribute("data-token-task", tokenRecordKey(r));
    fillTokenMeta(row, r);
    return row.childNodes.length ? row : null;
  }

  // 끝난 위임의 캐시 읽기·현재 컨텍스트를 서버(/api/qa/contexts)에 묻는다. 받으면 화면의 토큰 줄을 다시 채운다.
  function requestRecordContexts(records) {
    var items = [];
    (Array.isArray(records) ? records : []).forEach(function (r) {
      if (!r || !r.session_id || !Number(r.total_tokens)) { return; }
      var key = recordContextKey(r);
      if (!key || recordContexts[key] || recordContextRequested[key]) { return; }
      recordContextRequested[key] = true;
      items.push({ id: String(r.session_id), max: recordLastStep(r) });
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
            if (got[key]) { recordContexts[key] = { cache: Number(got[key].cache) || 0, context: Number(got[key].context) || 0 }; }
          });
          return true;
        })
        .catch(function () { chunk.forEach(function (it) { recordContextRequested[it.id + "|" + it.max] = false; }); return false; });
    })).then(function (rs) { return rs.some(Boolean); });
  }

  function refreshTokenMetas() {
    var byKey = {};
    allItems.forEach(function (r) { byKey[tokenRecordKey(r)] = r; });
    var nodes = document.querySelectorAll(".token-meta[data-token-task]");
    for (var i = 0; i < nodes.length; i++) {
      var r = byKey[nodes[i].getAttribute("data-token-task")];
      if (r) { fillTokenMeta(nodes[i], r); }
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

  // 과정 목록(<ol>). 단계 번호 · 시각 · 한글 도구 설명 · 실제 대상 · 영어 라벨. 마우스를 올리면 생각까지 보인다.
  function buildProcessRowsHtml(steps, cwd) {
    var procSteps = groupProcessSteps(steps);
    var hasSkipped = false;
    var totalCalls = 0;
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
      return '<li class="proc-row"' + (tip.length ? ' title="' + escapeHtml(tip.join("\n")) + '"' : '') + '>' +
        '<span class="proc-n">' + escapeHtml(String(st.n)) + '</span>' +
        '<span class="proc-at">' + escapeHtml(st.at || "") + '</span>' +
        '<span class="proc-tool">' + escapeHtml(tool) + (st.bg ? ' (백그라운드)' : '') + '</span>' +
        '<span class="proc-text">' +
          (st.detail ? '<span class="proc-detail">' + escapeHtml(shown) + '</span>' : '') +
          (st.label ? ' <span class="proc-label">' + (st.detail ? '· ' : '') + escapeHtml(st.label) + '</span>' : '') +
          readDescHtml +
          buildNarrationHtml("proc", st.say, st.think) +
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
          refreshLiveSaved();
          requestSavedFileSizes([{ status: "OK", process: lp.steps }]).then(function (got) { if (got) { refreshLiveSaved(); } });
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
  // (/api/delegate/translate)가 agy(gemini-3.8-flash-low)로 옮기고, 결과는 서버에 캐시돼서 다음부터는 바로 보인다.
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
      out.push('<button type="button" class="proc-tr-btn" data-act="translate" title="agy(gemini-3.8-flash-low)가 번역합니다. 30초~1분 걸리고 agy 사용량을 씁니다. 결과는 서버에 저장됩니다.">' +
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
    var html;
    if (st.steps && st.steps.length) {
      procDialogSteps = st.steps;
      var viewItems = procTrItemsFor(convId, procTrViewOf(convId));
      html = buildProcessRowsHtml(viewItems ? applyProcessTranslation(st.steps, viewItems) : st.steps, src.opts.cwd);
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
        var recOk = String(src.record.status == null ? "" : src.record.status).trim() === "OK";
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

  function buildCard(r) {
    var st = (r.status == null ? "" : String(r.status)).trim();
    var isOk = (st === "OK");
    var isErr = (st !== "" && !isOk);

    var card = document.createElement("div");
    card.className = "card" + (isErr ? " err" : "");
    card.setAttribute("data-key", "r:" + (r.task_id || r.timestamp || ""));

    var meta = document.createElement("div");
    meta.className = "meta";
    meta.appendChild(metaHead("실행"));
    meta.appendChild(labeledMeta("", String(r.timestamp || "").replace(/^\d{4}-/, ""), "ts", "완료 시각 " + (r.timestamp || "")));

    if (st) {
      meta.appendChild(badge("status-" + (isOk ? "ok" : "err"), st));
    } else {
      meta.appendChild(badge("status-unknown", "상태 미기록"));
    }

    var modelName = recordModel(r) || null;
    var isSession = Boolean(r.session || r.session_id || r.model === "(session)");
    if (modelName) { meta.appendChild(labeledMeta("", String(modelName), "model", "모델")); }
    if (r.elapsed_sec) {
      var elSec = Number(r.elapsed_sec);
      meta.appendChild(labeledMeta("소요", formatDuration(elSec), "elapsed", "실제 실행 시간: " + r.elapsed_sec + "초"));
      // 예상과 비교: 진행 중에 보였던 처음 예정값, 없으면 같은 모델의 다른 기록 중앙값
      var estSec = etaStoredMed(r.task_id || "");
      var estFrom = "이 브라우저가 진행 중에 기억한 처음 예정 시간";
      if (!estSec) {
        var typDone = typicalRunSec(r.model, r.task_id);
        if (typDone) { estSec = typDone.med; estFrom = "같은 모델(" + r.model + ")로 끝난 다른 위임의 보통 실행 시간"; }
      }
      var vs = estSec ? runVsEstimate(elSec, estSec) : null;
      if (vs) {
        // "[12분 28초 +27분 11초]": 예상 시간 뒤에 차이를 붙이고, 차이만 강조한다(초과 주황 / 미만 초록)
        var etaDone = labeledMeta("예상", "", "eta-done",
          "예상 " + formatDuration(estSec) + " / 실제 " + formatDuration(elSec) + " / " + vs.label + " " + vs.text + " (" + estFrom + ")");
        var etaHost = etaDone.querySelector(".mv");
        etaHost.appendChild(document.createTextNode("[" + formatDuration(estSec) + " "));
        var etaVal = document.createElement("strong");
        etaVal.className = "eta-done-val " + (vs.over ? "over" : "under");
        etaVal.textContent = vs.text;
        etaHost.appendChild(etaVal);
        etaHost.appendChild(document.createTextNode("]"));
        meta.appendChild(etaDone);
      }
    }
    // 끝난 위임에도 접수부터 실행 시작까지 기다린 시간을 남긴다(진행·대기 중 카드의 "대기 N" 과 같은 모양).
    // 서버가 작업 ID 의 접수 시각으로 계산한 근사값이다.
    if (r.wait_sec !== null && r.wait_sec !== undefined && Number(r.wait_sec) >= 1) {
      meta.appendChild(labeledMeta("대기", formatDuration(Number(r.wait_sec)), "elapsed", "접수부터 실행 시작까지 기다린 시간(오차 약 10초): " + r.wait_sec + "초"));
    }
    if (r.attempts && Number(r.attempts) > 1) { meta.appendChild(metaItem("시도 " + r.attempts + "회")); }
    // 위임 경로: 대부분은 inbox 파일 위임(bridge)이라 따로 표시하지 않고, Claude 가 antigravity MCP 로 직접 부른 기록만 "MCP" 로 표시한다.
    if (viaMcp(r)) { meta.appendChild(metaItem("MCP", "src-mcp", "위임 경로: Claude 가 antigravity MCP 로 직접 호출한 기록")); }
    card.appendChild(meta);

    var tokenMeta = buildTokenMeta(r);
    if (tokenMeta) card.appendChild(tokenMeta);

    card.appendChild(buildSessionMeta(r.session, r.session_id, r.task_id));   // 식별 줄: 모든 카드에(세션이 없으면 "세션 없음")

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

    meta.appendChild(buildProcessButton(card.getAttribute("data-key"), recordProcessOpts(r, qImgInfo.cwds)));

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
      write_to_file: "파일 쓰기",
      replace_file_content: "파일 일부 수정",
      list_dir: "폴더 목록 보기",
      find_by_name: "파일 이름 찾기",
      grep_search: "파일 내용 검색",
      search_web: "웹 검색",
      read_url_content: "웹 페이지 읽기",
      manage_task: "작업 관리",
      schedule: "잠시 대기",
      generate_image: "이미지 생성"
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

  // 진행 중 카드의 토큰 세부: "입력 X (캐시 C) · 출력 Y · 현재 컨텍스트 K". 총 토큰은 끝난 뒤 위임 기록과 같은 기준(입력 + 출력)이다.
  function liveTokenDetail(tk) {
    var parts = ["입력 " + tokenShort(tk.input) + (Number(tk.cache) > 0 ? " (캐시 " + tokenShort(tk.cache) + ")" : ""), "출력 " + tokenShort(tk.output)];
    if (Number(tk.context) > 0) { parts.push("현재 컨텍스트 " + tokenShort(tk.context)); }
    return parts.join(" · ");
  }
  function liveTokenTitle(tk) {
    return "실시간 토큰 " + Number(tk.total).toLocaleString() + " = 입력 " + Number(tk.input || 0).toLocaleString() + " + 출력 " + Number(tk.output || 0).toLocaleString() +
      (Number(tk.cache) > 0 ? " (캐시에서 읽은 입력 " + Number(tk.cache).toLocaleString() + " 은 따로, 총에 넣지 않습니다)" : "") +
      (Number(tk.context) > 0 ? " · 현재 컨텍스트 " + Number(tk.context).toLocaleString() + "(마지막 턴이 보낸 입력의 크기)" : "") +
      (Number(tk.turns) > 0 ? " · 모델 응답 " + Number(tk.turns) + "번" : "");
  }

  function buildProgressHtml(pg, cwd, saved, taskId) {
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
    // Claude 토큰 절약(예상): 끝난 카드와 같은 방식. 단계가 모이기 전에는 숨겨 두고(자리만 만들어) 값이 생기면 제자리에서 채운다.
    var savedHtml = "";
    if (taskId) {
      savedHtml = '<span class="pg-saved-wrap" data-saved-live="' + escapeHtml(taskId) + '"' + (saved ? "" : " hidden") + '><span class="pg-sep">·</span><span class="pg-saved saved-tokens"' +
        (saved ? ' title="' + escapeHtml(savedTokensDetail(saved)) + '">' + escapeHtml(savedTokensText(saved.saved)) : ">") + '</span></span>';
    }
    var action = buildProgressActionHtml(pg, cwd);
    return '<div class="pending-progress">' + (parts.length ? '<div class="pg-line">' + parts.join('<span class="pg-sep">·</span>') + savedHtml + '</div>' : "") + action + '</div>';
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
    if (idle >= stall && !pg.waiting_background) {
      return { kind: "stalled", label: "멈춘 것으로 보임", idleSec: idle, detail: join([idleText, healthStallMinutes(stall) + " 넘게 새 단계가 없습니다"]) };
    }
    if (pg.waiting_background && idle >= PROGRESS_QUIET_SEC) {
      return { kind: "running", label: "진행 중", idleSec: idle, detail: join(["오래 걸리는 명령이 끝나기를 기다리는 중", idleText]) };
    }
    if (idle >= PROGRESS_QUIET_SEC) {
      return { kind: "quiet", label: "조용함", idleSec: idle, detail: join([idleText, healthStallMinutes(stall) + " 넘게 조용하면 멈춘 것으로 봅니다"]) };
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
      var ok = String(rec.status == null ? "" : rec.status).trim() === "OK";
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

    if (p.model) { meta.appendChild(labeledMeta("", String(p.model), "model", "모델")); }

    var pendStartMs = null;     // 토큰/시간 줄의 실제 시간(실시간)에 쓴다
    var pendEtaSec = null;      // 처음 예정 시간(같은 모델의 보통 실행 시간)
    if (isProcessing) {
      var createdTime = parseLocalTime(p.created);
      var actualStartTime = p.started_at ? parseLocalTime(p.started_at) : createdTime;
      var startTime = actualStartTime || createdTime;

      // 1. 실제 실행 시간 라이브 배지 (1초마다 자동 갱신)
      if (startTime) {
        var elapsedSec = Math.max(0, (Date.now() - startTime.getTime()) / 1000);
        pendStartMs = startTime.getTime();
        var live = labeledMeta("소요", formatDuration(elapsedSec), "elapsed live-elapsed", "실제 실행 경과 시간 (실행 시작: " + (p.started_at || p.created || "") + ")");
        live.setAttribute("data-start", String(startTime.getTime()));
        live.setAttribute("data-label-prefix", "");
        meta.appendChild(live);

        // 완료 예정: 시작 시각 + 같은 모델의 보통 실행 시간. 이미 넘었으면 시각 대신 "예상보다 오래 걸리는 중"으로 알린다.
        var typ = typicalRunSec(p.model);
        if (typ) {
          var etaBasis = "같은 모델(" + p.model + ")로 끝난 최근 위임 기준: 보통 " + formatDuration(typ.med) + ", 오래 걸린 경우 " + formatDuration(typ.p90) + ". 작업 크기에 따라 달라집니다.";
          var initMed = etaInitialMed(p.task_id || "", typ.med);
          pendEtaSec = initMed;
          var etaItem = labeledMeta("예상", "", "eta live-eta", "추정. " + etaBasis + " 처음 예정 " + formatDuration(initMed) + ".");
          etaItem.setAttribute("data-start", String(startTime.getTime()));
          etaItem.setAttribute("data-med", String(typ.med));
          etaItem.setAttribute("data-init-med", String(initMed));
          paintEta(etaItem, Date.now());
          meta.appendChild(etaItem);
          var deltaItem = metaItem("", "eta-delta live-eta-delta", "");
          deltaItem.setAttribute("data-start", String(startTime.getTime()));
          deltaItem.setAttribute("data-med", String(typ.med));
          deltaItem.setAttribute("data-init-med", String(initMed));
          paintEtaDelta(deltaItem, Date.now());
          meta.appendChild(deltaItem);
        }
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
    // 끝난 카드와 같은 네 줄(실행 / 토큰 / 시간 / 식별). Claude 토큰은 실행 줄이 아니라 토큰 줄에 둔다.
    card.appendChild(buildPendingTokenMeta(p, pendStartMs, pendEtaSec));

    card.appendChild(buildSessionMeta(p.session, p.session_id, p.task_id));   // 식별 줄: 모든 카드에(세션이 없으면 "세션 없음")

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

    meta.appendChild(buildProcessButton(card.getAttribute("data-key"), pendingProcessOpts(p, effCwds)));

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
      ((isProcessing || p.interrupted) ? buildProgressHtml(p.progress, effCwds, isProcessing ? liveSavedOf(p) : null, isProcessing ? p.task_id : "") : "")
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
      wrap.innerHTML = buildProgressHtml(live.pending.progress, cwdListOf(live.pending.cwd), liveSavedOf(live.pending), live.pending.task_id);
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

  // ==========================================================================
  // Token & Delegation Statistics
  // ==========================================================================

  // 100만 이상은 M 로 줄여 쓴다(예 17.0M). 캐시 재읽기처럼 값이 아주 큰 칸이 표 너비를 키우지 않게 하려는 것이다. 그 밖에는 formatTokenK 와 같다.
  function formatTokenCompact(num) {
    if (num === null || num === undefined || isNaN(num)) return "-";
    var n = Number(num);
    if (Math.abs(n) >= 1000000) {
      return (n < 0 ? "-" : "") + (Math.round(Math.abs(n) / 100000) / 10).toFixed(1) + "M";
    }
    return formatTokenK(n, false);
  }

  // 진행 중 위임 카드의 Claude 토큰 라이브 메타 항목 포맷팅
  function formatClaudeLiveMeta(cl) {
    if (!cl || cl.used == null || isNaN(cl.used)) return null;
    var tokText = "Claude 토큰 위임 " + formatTokenCompact(cl.used);
    var tipParts = ["이 위임을 보낸 턴에서 위임에 쓴 Claude 토큰(지금까지, 위임과 무관한 호출은 뺀 값)"];
    if (cl.other_calls && cl.other_calls > 0) {
      var oTokNum = (cl.other_tokens != null && cl.other_tokens > 0) ? cl.other_tokens : (cl.d_tokens != null && cl.d_tokens > cl.used ? cl.d_tokens - cl.used : 0);
      var oTokStr = (oTokNum > 0) ? formatTokenK(oTokNum, true) : "+0.0k";
      tipParts.push("다른 작업 " + cl.other_calls + "회·" + oTokStr + " 제외");
    }
    if (cl.est_delegate != null && !isNaN(cl.est_delegate)) {
      tipParts.push("예상 " + formatTokenCompact(cl.est_delegate));
    }
    return {
      text: tokText,
      cls: "tok-claude-live",
      title: tipParts.join(" · ")
    };
  }

  function formatTokenK(num, withSign) {
    if (num === null || num === undefined || isNaN(num)) return "-";
    var n = Number(num);
    var sign = "";
    if (withSign) {
      if (n > 0) sign = "+";
      else if (n < 0) sign = "-";
    } else if (n < 0) {
      sign = "-";
    }
    var abs = Math.abs(n);
    if (abs === 0) {
      return "0k";
    }
    var rounded = Math.round(abs / 100) / 10;
    return sign + rounded.toFixed(1) + "k";
  }

  function computeLinearIntersection(directA, directB, delegateA, delegateB) {
    if (typeof directA !== "number" || typeof directB !== "number" ||
        typeof delegateA !== "number" || typeof delegateB !== "number") {
      return null;
    }
    var denom = directB - delegateB;
    if (denom <= 0) return null;
    var diffA = delegateA - directA;
    if (diffA <= 0) return 0;
    var x = diffA / denom;
    return Math.round(x);
  }

  function computeNiceTicks(minVal, maxVal, maxTicks) {
    if (typeof minVal !== "number" || typeof maxVal !== "number" || isNaN(minVal) || isNaN(maxVal)) {
      return { min: 0, max: 1, step: 1, ticks: [0, 1] };
    }
    if (minVal === maxVal) {
      if (minVal === 0) return { min: 0, max: 1, step: 1, ticks: [0, 1] };
      if (minVal > 0) return { min: 0, max: minVal * 1.5, step: minVal * 0.5, ticks: [0, minVal, minVal * 1.5] };
      return { min: minVal * 1.5, max: 0, step: Math.abs(minVal) * 0.5, ticks: [minVal * 1.5, minVal, 0] };
    }
    if (!maxTicks || maxTicks < 2) maxTicks = 5;

    var span = maxVal - minVal;
    var roughStep = span / (maxTicks - 1);
    var stepMagnitude = Math.pow(10, Math.floor(Math.log(roughStep) / Math.LN10));
    var stepNorm = roughStep / stepMagnitude;
    var step;
    if (stepNorm <= 1) step = 1 * stepMagnitude;
    else if (stepNorm <= 2) step = 2 * stepMagnitude;
    else if (stepNorm <= 5) step = 5 * stepMagnitude;
    else step = 10 * stepMagnitude;

    var niceMin = Math.floor(minVal / step) * step;
    var niceMax = Math.ceil(maxVal / step) * step;
    var ticks = [];
    var cur = niceMin;
    while (cur <= niceMax + (step * 0.5)) {
      ticks.push(Math.round(cur * 1000) / 1000);
      cur += step;
    }
    return { min: niceMin, max: niceMax, step: step, ticks: ticks };
  }

  function fillDateRange(startDateStr, endDateStr, existingItems) {
    var map = {};
    if (existingItems && existingItems.length) {
      for (var i = 0; i < existingItems.length; i++) {
        var it = existingItems[i];
        if (it && it.date) {
          map[it.date] = it;
        }
      }
    }
    var result = [];
    var cur = new Date(startDateStr + "T00:00:00");
    var end = new Date(endDateStr + "T00:00:00");
    if (isNaN(cur.getTime()) || isNaN(end.getTime())) return result;

    while (cur.getTime() <= end.getTime()) {
      var y = cur.getFullYear();
      var m = cur.getMonth() + 1;
      var d = cur.getDate();
      var dStr = y + "-" + (m < 10 ? "0" + m : m) + "-" + (d < 10 ? "0" + d : d);
      if (map[dStr]) {
        result.push(map[dStr]);
      } else {
        result.push({
          date: dStr,
          ok: 0,
          fail: 0,
          saved: 0,
          cum_saved: 0,
          direct_turns: 0,
          delegate_turns: 0
        });
      }
      cur.setDate(cur.getDate() + 1);
    }
    return result;
  }

  function computeCollectProgress(delegateN, target) {
    var t = Number(target);
    if (isNaN(t) || t <= 0) return 0;
    var n = Number(delegateN);
    if (isNaN(n) || n <= 0) return 0;
    var pct = (n / t) * 100;
    if (pct > 100) return 100;
    return Math.round(pct * 10) / 10;
  }

  function getCollectBannerState(collect) {
    if (!collect || !collect.active) {
      return {
        show: false,
        n: 0,
        target: 20,
        pct: 0,
        title: "",
        desc: ""
      };
    }
    var n = Math.max(0, parseInt(collect.delegate_n, 10) || 0);
    var target = parseInt(collect.target, 10);
    if (isNaN(target) || target <= 0) target = 20;
    var pct = computeCollectProgress(n, target);
    return {
      show: true,
      n: n,
      target: target,
      pct: pct,
      title: "수집 중 · 위임 표본 " + n + "/" + target,
      desc: "일정 수준이 모일 때까지 위임을 우선합니다. " + target + "건이 되면 이 표시가 사라지고 보정식이 이 PC 의 패턴으로 바뀝니다."
    };
  }

  function formatTimeKo(sec) {
    if (sec === null || sec === undefined || isNaN(sec)) return "—";
    var n = Number(sec);
    if (n < 0) return "—";
    n = Math.round(n);
    if (n < 60) return n + "초";
    var h = Math.floor(n / 3600);
    var rem = n % 3600;
    var m = Math.floor(rem / 60);
    var s = rem % 60;
    if (h > 0) {
      return h + "시간" + (m > 0 ? " " + m + "분" : "");
    }
    if (s > 0) {
      return m + "분 " + s + "초";
    }
    return m + "분";
  }

  function getCardWaitIcon(state, isProcessing, isInterrupted) {
    if (state === "waiting") return "hourglass";
    if (state === "queued" && !isProcessing && !isInterrupted) return "hourglass";
    return null;
  }

  function allocateTurnTokens(dTokens, turnSaved, taskTokensList) {
    taskTokensList = Array.isArray(taskTokensList) ? taskTokensList : [];
    var n = taskTokensList.length;
    if (n === 0) return [];
    var sum = 0;
    var hasPositive = false;
    for (var i = 0; i < n; i++) {
      var val = Number(taskTokensList[i]);
      if (!isNaN(val) && val > 0) {
        sum += val;
        hasPositive = true;
      }
    }
    var weights = [];
    for (var i = 0; i < n; i++) {
      if (hasPositive && sum > 0) {
        var val = Number(taskTokensList[i]);
        weights.push((!isNaN(val) && val > 0) ? (val / sum) : 0);
      } else {
        weights.push(1 / n);
      }
    }
    var maxIdx = 0;
    for (var i = 1; i < n; i++) {
      if (weights[i] > weights[maxIdx]) maxIdx = i;
    }
    var usedList = [];
    var usedSum = 0;
    for (var i = 0; i < n; i++) {
      var u = Math.round(dTokens * weights[i]);
      usedList.push(u);
      usedSum += u;
    }
    var diffUsed = dTokens - usedSum;
    if (diffUsed !== 0) usedList[maxIdx] += diffUsed;

    var savedList = [];
    if (turnSaved !== null && turnSaved !== undefined && !isNaN(turnSaved)) {
      var savedSum = 0;
      for (var i = 0; i < n; i++) {
        var s = Math.round(turnSaved * weights[i]);
        savedList.push(s);
        savedSum += s;
      }
      var diffSaved = turnSaved - savedSum;
      if (diffSaved !== 0) savedList[maxIdx] += diffSaved;
    } else {
      for (var i = 0; i < n; i++) {
        savedList.push(null);
      }
    }
    var res = [];
    for (var i = 0; i < n; i++) {
      res.push({ used: usedList[i], saved: savedList[i], weight: weights[i] });
    }
    return res;
  }

  function setStatsLoading() {
    if (els.statsHeroSaved && !statsData) {
      els.statsHeroSaved.textContent = "불러오는 중…";
      els.statsHeroSaved.className = "stats-hero-number stats-loading";
    }
    if (els.statsHeroDesc && !statsData) {
      els.statsHeroDesc.textContent = "최근 " + statsDays + "일 · 불러오는 중…";
    }
  }

  function loadStats(days) {
    var d = (days === 7 || days === 30 || days === 60) ? days : 30;
    setStatsLoading();
    return fetchJson("/api/token-stats?days=" + d).then(function (data) {
      statsData = data;
      lastStatsFetchAt = Date.now();
      return data;
    }).catch(function (err) {
      console.warn("Failed to load token stats:", err);
      return null;
    });
  }

  function fetchAndRenderStats(force) {
    var nowTs = Date.now();
    if (!force && statsData && (nowTs - lastStatsFetchAt < 30000)) {
      renderStats(statsData);
      return;
    }
    loadStats(statsDays).then(function (data) {
      renderStats(data);
    });
  }

  function applyStatsTableToggle() {
    var showTable = Boolean(statsTableView);
    if (els.statsTableToggle) {
      els.statsTableToggle.checked = showTable;
    }
    var chartViews = [els.chartTasksView, els.chartSavingsView, els.chartAccuracyView, els.chartScatterView, els.chartTimeAccuracyView];
    var tableViews = [els.tableTasksView, els.tableSavingsView, els.tableAccuracyView, els.tableScatterView, els.tableTimeAccuracyView];
    for (var i = 0; i < chartViews.length; i++) {
      if (chartViews[i]) chartViews[i].style.display = showTable ? "none" : "block";
    }
    for (var j = 0; j < tableViews.length; j++) {
      if (tableViews[j]) tableViews[j].style.display = showTable ? "block" : "none";
    }
  }

  function showStatsTooltip(e, title, items) {
    if (!els.statsTooltip) return;
    var html = '<div class="stats-tooltip-title">' + escapeHtml(title) + '</div>';
    for (var i = 0; i < items.length; i++) {
      var it = items[i];
      var swatch = it.color ? '<span style="display:inline-block;width:8px;height:8px;border-radius:2px;background:' + it.color + ';margin-right:4px;"></span>' : '';
      html += '<div class="stats-tooltip-row">' +
              '<span class="stats-tooltip-key">' + swatch + escapeHtml(it.label) + '</span>' +
              '<span class="stats-tooltip-val">' + escapeHtml(it.value) + '</span>' +
              '</div>';
    }
    els.statsTooltip.innerHTML = html;
    els.statsTooltip.style.display = "flex";

    moveStatsTooltip(e);
  }

  // 화면(viewport) 기준 좌표로 커서 옆에 둔다. 스크롤·조상 위치와 무관하고, 화면 가장자리에서는 반대쪽으로 넘긴다.
  function moveStatsTooltip(e) {
    var tip = els.statsTooltip;
    if (!tip) return;
    var w = tip.offsetWidth, h = tip.offsetHeight;
    var x = e.clientX + 14, y = e.clientY + 14;
    if (x + w > window.innerWidth - 8) x = e.clientX - w - 14;
    if (y + h > window.innerHeight - 8) y = e.clientY - h - 14;
    tip.style.left = Math.max(8, x) + "px";
    tip.style.top = Math.max(8, y) + "px";
  }

  function hideStatsTooltip() {
    if (els.statsTooltip) {
      els.statsTooltip.style.display = "none";
    }
  }

  function renderChartTasks(daily) {
    if (!els.chartTasksView || !els.tableTasksView) return;
    daily = daily || [];
    var n = daily.length;
    if (!n) {
      els.chartTasksView.innerHTML = '<div class="empty-hint" style="padding:40px;text-align:center;">데이터가 없습니다.</div>';
      els.tableTasksView.innerHTML = '';
      return;
    }

    var maxVal = 0;
    for (var i = 0; i < n; i++) {
      var tot = (daily[i].ok || 0) + (daily[i].fail || 0);
      if (tot > maxVal) maxVal = tot;
    }
    if (maxVal === 0) maxVal = 5;

    var ticksObj = computeNiceTicks(0, maxVal, 4);
    var tickMax = ticksObj.max;

    var svgW = 600, svgH = 220;
    var padLeft = 40, padRight = 20, padTop = 20, padBottom = 32;
    var plotW = svgW - padLeft - padRight;
    var plotH = svgH - padTop - padBottom;
    var baseY = padTop + plotH;

    function scaleY(v) {
      return baseY - (v / tickMax) * plotH;
    }

    var svg = '<svg viewBox="0 0 ' + svgW + ' ' + svgH + '" class="stats-chart-svg" preserveAspectRatio="xMidYMid meet" role="img" aria-label="위임 성공 실패 막대 차트">';

    for (var t = 0; t < ticksObj.ticks.length; t++) {
      var tick = ticksObj.ticks[t];
      var ty = Math.round(scaleY(tick));
      svg += '<line x1="' + padLeft + '" y1="' + ty + '" x2="' + (padLeft + plotW) + '" y2="' + ty + '" stroke="var(--line)" stroke-width="1"/>';
      svg += '<text x="' + (padLeft - 8) + '" y="' + (ty + 4) + '" text-anchor="end" font-size="11" fill="var(--ink-3)">' + tick + '</text>';
    }

    svg += '<line x1="' + padLeft + '" y1="' + baseY + '" x2="' + (padLeft + plotW) + '" y2="' + baseY + '" stroke="var(--line-strong)" stroke-width="1"/>';

    var slotW = plotW / n;
    var barW = Math.min(24, Math.max(4, Math.round(slotW * 0.6)));

    for (var i = 0; i < n; i++) {
      var d = daily[i];
      var cx = padLeft + (i + 0.5) * slotW;
      var bx = Math.round(cx - barW / 2);
      var ok = d.ok || 0;
      var fail = d.fail || 0;

      if (ok > 0 && fail > 0) {
        var hOk = Math.max(1, Math.round((ok / tickMax) * plotH));
        var hFail = Math.max(1, Math.round((fail / tickMax) * plotH));
        var yOk = baseY - hOk;
        var yFail = yOk - hFail - 2;
        svg += '<rect x="' + bx + '" y="' + yOk + '" width="' + barW + '" height="' + hOk + '" fill="var(--ok)"/>';
        svg += '<rect x="' + bx + '" y="' + yFail + '" width="' + barW + '" height="' + hFail + '" rx="4" ry="4" fill="var(--err)"/>';
      } else if (ok > 0) {
        var hOk = Math.max(1, Math.round((ok / tickMax) * plotH));
        var yOk = baseY - hOk;
        svg += '<rect x="' + bx + '" y="' + yOk + '" width="' + barW + '" height="' + hOk + '" rx="4" ry="4" fill="var(--ok)"/>';
      } else if (fail > 0) {
        var hFail = Math.max(1, Math.round((fail / tickMax) * plotH));
        var yFail = baseY - hFail;
        svg += '<rect x="' + bx + '" y="' + yFail + '" width="' + barW + '" height="' + hFail + '" rx="4" ry="4" fill="var(--err)"/>';
      }

      var ariaLabel = d.date + " 성공 " + ok + "건, 실패 " + fail + "건";
      svg += '<rect class="chart-hit-slot" data-chart="tasks" data-idx="' + i + '" x="' + (cx - slotW / 2) + '" y="' + padTop + '" width="' + slotW + '" height="' + plotH + '" fill="transparent" tabindex="0" role="graphics-symbol" aria-label="' + escapeHtml(ariaLabel) + '" style="cursor:pointer;outline:none;"/>';
    }

    var stepLabels = Math.max(1, Math.floor(n / 5));
    for (var i = 0; i < n; i += stepLabels) {
      var cx = padLeft + (i + 0.5) * slotW;
      var dStr = daily[i].date;
      var shortDate = dStr ? dStr.slice(5) : "";
      svg += '<text x="' + cx + '" y="' + (baseY + 18) + '" text-anchor="middle" font-size="11" fill="var(--ink-3)">' + escapeHtml(shortDate) + '</text>';
    }
    if ((n - 1) % stepLabels !== 0) {
      var cx = padLeft + (n - 0.5) * slotW;
      var dStr = daily[n - 1].date;
      var shortDate = dStr ? dStr.slice(5) : "";
      svg += '<text x="' + cx + '" y="' + (baseY + 18) + '" text-anchor="middle" font-size="11" fill="var(--ink-3)">' + escapeHtml(shortDate) + '</text>';
    }

    svg += '</svg>';
    els.chartTasksView.innerHTML = svg;

    var tHtml = '<table class="stats-data-table"><thead><tr><th>날짜</th><th class="num">성공</th><th class="num">실패</th><th class="num">전체</th></tr></thead><tbody>';
    for (var i = 0; i < n; i++) {
      var d = daily[i];
      var tot = (d.ok || 0) + (d.fail || 0);
      tHtml += '<tr><td>' + escapeHtml(d.date) + '</td><td class="num">' + (d.ok || 0) + '</td><td class="num">' + (d.fail || 0) + '</td><td class="num">' + tot + '</td></tr>';
    }
    tHtml += '</tbody></table>';
    els.tableTasksView.innerHTML = tHtml;
  }

  function renderChartSavings(daily) {
    if (!els.chartSavingsView || !els.tableSavingsView) return;
    // 서버의 saved(절약, + 가 좋음)를 증감(delta: + 증가·더 소모, - 감소·절약)으로 뒤집어 쓴다. cum 은 누적 증감.
    daily = (daily || []).map(function (x) { return { date: x.date, delta: -(x.saved || 0), cum: -(x.cum_saved || 0) }; });
    var n = daily.length;
    if (!n) {
      els.chartSavingsView.innerHTML = '<div class="empty-hint" style="padding:40px;text-align:center;">데이터가 없습니다.</div>';
      els.tableSavingsView.innerHTML = '';
      return;
    }

    var minVal = 0, maxVal = 0;
    for (var i = 0; i < n; i++) {
      var s = daily[i].delta || 0;
      var c = daily[i].cum || 0;
      if (s < minVal) minVal = s;
      if (c < minVal) minVal = c;
      if (s > maxVal) maxVal = s;
      if (c > maxVal) maxVal = c;
    }
    if (minVal === 0 && maxVal === 0) {
      maxVal = 10000;
      minVal = -2000;
    }

    var ticksObj = computeNiceTicks(minVal, maxVal, 5);
    var tMin = ticksObj.min, tMax = ticksObj.max;
    var span = tMax - tMin;
    if (span === 0) span = 1;

    var svgW = 600, svgH = 220;
    var padLeft = 48, padRight = 44, padTop = 20, padBottom = 32;
    var plotW = svgW - padLeft - padRight;
    var plotH = svgH - padTop - padBottom;
    var baseY = padTop + plotH;

    function scaleY(v) {
      return baseY - ((v - tMin) / span) * plotH;
    }

    var y0 = Math.round(scaleY(0));

    var svg = '<svg viewBox="0 0 ' + svgW + ' ' + svgH + '" class="stats-chart-svg" preserveAspectRatio="xMidYMid meet" role="img" aria-label="토큰 증감 차트">';

    for (var t = 0; t < ticksObj.ticks.length; t++) {
      var tick = ticksObj.ticks[t];
      var ty = Math.round(scaleY(tick));
      svg += '<line x1="' + padLeft + '" y1="' + ty + '" x2="' + (padLeft + plotW) + '" y2="' + ty + '" stroke="var(--line)" stroke-width="1"/>';
      svg += '<text x="' + (padLeft - 8) + '" y="' + (ty + 4) + '" text-anchor="end" font-size="11" fill="var(--ink-3)">' + formatTokenK(tick, false) + '</text>';
    }

    svg += '<line x1="' + padLeft + '" y1="' + y0 + '" x2="' + (padLeft + plotW) + '" y2="' + y0 + '" stroke="var(--line-strong)" stroke-width="1.5"/>';

    var slotW = plotW / n;
    var barW = Math.min(24, Math.max(4, Math.round(slotW * 0.6)));

    for (var i = 0; i < n; i++) {
      var d = daily[i];
      var s = d.delta || 0;
      var cx = padLeft + (i + 0.5) * slotW;
      var bx = Math.round(cx - barW / 2);
      if (s > 0) {
        var yVal = Math.round(scaleY(s));
        var h = Math.max(1, y0 - yVal);
        svg += '<rect x="' + bx + '" y="' + yVal + '" width="' + barW + '" height="' + h + '" rx="4" ry="4" fill="var(--loss)"/>';
      } else if (s < 0) {
        var yVal = Math.round(scaleY(s));
        var h = Math.max(1, yVal - y0);
        svg += '<rect x="' + bx + '" y="' + y0 + '" width="' + barW + '" height="' + h + '" rx="4" ry="4" fill="var(--gain)"/>';
      }
    }

    var linePts = [];
    for (var i = 0; i < n; i++) {
      var cx = padLeft + (i + 0.5) * slotW;
      var cy = Math.round(scaleY(daily[i].cum || 0));
      linePts.push({ x: cx, y: cy });
    }

    if (linePts.length > 0) {
      var dPath = "M " + linePts[0].x + " " + linePts[0].y;
      for (var i = 1; i < linePts.length; i++) {
        dPath += " L " + linePts[i].x + " " + linePts[i].y;
      }
      svg += '<path d="' + dPath + '" fill="none" stroke="var(--ink)" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>';

      for (var i = 0; i < linePts.length; i++) {
        svg += '<circle cx="' + linePts[i].x + '" cy="' + linePts[i].y + '" r="4" fill="var(--ink)" stroke="var(--surface)" stroke-width="2"/>';
      }

      var lastPt = linePts[linePts.length - 1];
      var lastCum = daily[n - 1].cum || 0;
      svg += '<text x="' + (lastPt.x + 6) + '" y="' + (lastPt.y + 4) + '" font-size="11" font-weight="600" fill="var(--ink)">' + formatTokenK(lastCum, true) + '</text>';
    }

    for (var i = 0; i < n; i++) {
      var d = daily[i];
      var cx = padLeft + (i + 0.5) * slotW;
      var ariaLabel = d.date + " 증감 (추정) " + formatTokenK(d.delta || 0, true) + ", 누적 (추정) " + formatTokenK(d.cum || 0, true);
      svg += '<rect class="chart-hit-slot" data-chart="savings" data-idx="' + i + '" x="' + (cx - slotW / 2) + '" y="' + padTop + '" width="' + slotW + '" height="' + plotH + '" fill="transparent" tabindex="0" role="graphics-symbol" aria-label="' + escapeHtml(ariaLabel) + '" style="cursor:pointer;outline:none;"/>';
    }

    var stepLabels = Math.max(1, Math.floor(n / 5));
    for (var i = 0; i < n; i += stepLabels) {
      var cx = padLeft + (i + 0.5) * slotW;
      var dStr = daily[i].date;
      var shortDate = dStr ? dStr.slice(5) : "";
      svg += '<text x="' + cx + '" y="' + (baseY + 18) + '" text-anchor="middle" font-size="11" fill="var(--ink-3)">' + escapeHtml(shortDate) + '</text>';
    }
    if ((n - 1) % stepLabels !== 0) {
      var cx = padLeft + (n - 0.5) * slotW;
      var dStr = daily[n - 1].date;
      var shortDate = dStr ? dStr.slice(5) : "";
      svg += '<text x="' + cx + '" y="' + (baseY + 18) + '" text-anchor="middle" font-size="11" fill="var(--ink-3)">' + escapeHtml(shortDate) + '</text>';
    }

    svg += '</svg>';
    els.chartSavingsView.innerHTML = svg;

    var tHtml = '<table class="stats-data-table"><thead><tr><th>날짜</th><th class="num">증감</th><th class="num">누적 증감</th></tr></thead><tbody>';
    for (var i = 0; i < n; i++) {
      var d = daily[i];
      var sStr = formatTokenK(d.delta || 0, true);
      var cStr = formatTokenK(d.cum || 0, true);
      var sCls = (d.delta || 0) <= 0 ? "val-ok" : "val-err";
      tHtml += '<tr><td>' + escapeHtml(d.date) + '</td><td class="num ' + sCls + '">' + sStr + '</td><td class="num">' + cStr + '</td></tr>';
    }
    tHtml += '</tbody></table>';
    els.tableSavingsView.innerHTML = tHtml;
  }

  function renderChartAccuracy(weekly) {
    if (!els.chartAccuracyView || !els.tableAccuracyView) return;
    weekly = weekly || [];
    var n = weekly.length;
    if (!n) {
      els.chartAccuracyView.innerHTML = '<div class="empty-hint" style="padding:40px;text-align:center;">주별 예상 정확도 표본이 아직 없습니다.</div>';
      els.tableAccuracyView.innerHTML = '<div class="empty-hint" style="padding:40px;text-align:center;">주별 예상 정확도 표본이 아직 없습니다.</div>';
      return;
    }

    var maxR = 2.0;
    for (var i = 0; i < n; i++) {
      if (weekly[i].direct !== null && weekly[i].direct !== undefined && weekly[i].direct > maxR) maxR = weekly[i].direct;
      if (weekly[i].delegate !== null && weekly[i].delegate !== undefined && weekly[i].delegate > maxR) maxR = weekly[i].delegate;
    }
    maxR = Math.ceil(maxR * 1.2 * 10) / 10;

    var ticksObj = computeNiceTicks(0, maxR, 4);
    var tickMax = ticksObj.max;

    var svgW = 600, svgH = 220;
    var padLeft = 40, padRight = 75, padTop = 20, padBottom = 32;
    var plotW = svgW - padLeft - padRight;
    var plotH = svgH - padTop - padBottom;
    var baseY = padTop + plotH;

    function scaleY(v) {
      return baseY - (v / tickMax) * plotH;
    }

    var svg = '<svg viewBox="0 0 ' + svgW + ' ' + svgH + '" class="stats-chart-svg" preserveAspectRatio="xMidYMid meet" role="img" aria-label="주별 예상 정확도 차트">';

    for (var t = 0; t < ticksObj.ticks.length; t++) {
      var tick = ticksObj.ticks[t];
      var ty = Math.round(scaleY(tick));
      svg += '<line x1="' + padLeft + '" y1="' + ty + '" x2="' + (padLeft + plotW) + '" y2="' + ty + '" stroke="var(--line)" stroke-width="1"/>';
      svg += '<text x="' + (padLeft - 8) + '" y="' + (ty + 4) + '" text-anchor="end" font-size="11" fill="var(--ink-3)">' + tick.toFixed(1) + '</text>';
    }

    var y1 = Math.round(scaleY(1.0));
    svg += '<line x1="' + padLeft + '" y1="' + y1 + '" x2="' + (padLeft + plotW) + '" y2="' + y1 + '" stroke="var(--ink-2)" stroke-width="1" stroke-dasharray="4,4"/>';
    svg += '<text x="' + (padLeft + plotW + 6) + '" y="' + (y1 + 4) + '" font-size="10" fill="var(--ink-2)">정확 (1.0)</text>';

    var slotW = n > 1 ? plotW / (n - 1) : plotW;

    var dirPts = [], delPts = [];
    for (var i = 0; i < n; i++) {
      var cx = n > 1 ? (padLeft + i * slotW) : (padLeft + plotW / 2);
      if (weekly[i].direct !== null && weekly[i].direct !== undefined) {
        dirPts.push({ x: cx, y: Math.round(scaleY(weekly[i].direct)), val: weekly[i].direct, idx: i });
      }
      if (weekly[i].delegate !== null && weekly[i].delegate !== undefined) {
        delPts.push({ x: cx, y: Math.round(scaleY(weekly[i].delegate)), val: weekly[i].delegate, idx: i });
      }
    }

    if (dirPts.length > 1) {
      var pD = "M " + dirPts[0].x + " " + dirPts[0].y;
      for (var i = 1; i < dirPts.length; i++) { pD += " L " + dirPts[i].x + " " + dirPts[i].y; }
      svg += '<path d="' + pD + '" fill="none" stroke="var(--claude)" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>';
    }
    for (var i = 0; i < dirPts.length; i++) {
      svg += '<circle cx="' + dirPts[i].x + '" cy="' + dirPts[i].y + '" r="4" fill="var(--claude)" stroke="var(--surface)" stroke-width="2"/>';
    }
    if (dirPts.length > 0) {
      var lastD = dirPts[dirPts.length - 1];
      svg += '<text x="' + (lastD.x + 6) + '" y="' + (lastD.y + 4) + '" font-size="11" font-weight="600" fill="var(--claude)">직접 ' + lastD.val + '배</text>';
    }

    if (delPts.length > 1) {
      var pDel = "M " + delPts[0].x + " " + delPts[0].y;
      for (var i = 1; i < delPts.length; i++) { pDel += " L " + delPts[i].x + " " + delPts[i].y; }
      svg += '<path d="' + pDel + '" fill="none" stroke="var(--agy)" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>';
    }
    for (var i = 0; i < delPts.length; i++) {
      svg += '<circle cx="' + delPts[i].x + '" cy="' + delPts[i].y + '" r="4" fill="var(--agy)" stroke="var(--surface)" stroke-width="2"/>';
    }
    if (delPts.length > 0) {
      var lastDel = delPts[delPts.length - 1];
      svg += '<text x="' + (lastDel.x + 6) + '" y="' + (lastDel.y + 4) + '" font-size="11" font-weight="600" fill="var(--agy)">위임 ' + lastDel.val + '배</text>';
    }

    for (var i = 0; i < n; i++) {
      var cx = n > 1 ? (padLeft + i * slotW) : (padLeft + plotW / 2);
      var hW = n > 1 ? slotW : plotW;
      var ariaLabel = weekly[i].week + " 직접: " + (weekly[i].direct !== null ? weekly[i].direct + "배" : "-") + ", 위임: " + (weekly[i].delegate !== null ? weekly[i].delegate + "배" : "-");
      svg += '<rect class="chart-hit-slot" data-chart="accuracy" data-idx="' + i + '" x="' + (cx - hW / 2) + '" y="' + padTop + '" width="' + hW + '" height="' + plotH + '" fill="transparent" tabindex="0" role="graphics-symbol" aria-label="' + escapeHtml(ariaLabel) + '" style="cursor:pointer;outline:none;"/>';
      svg += '<text x="' + cx + '" y="' + (baseY + 18) + '" text-anchor="middle" font-size="11" fill="var(--ink-3)">' + escapeHtml(weekly[i].week) + '</text>';
    }

    svg += '</svg>';
    els.chartAccuracyView.innerHTML = svg;

    var tHtml = '<table class="stats-data-table"><thead><tr><th>주차</th><th class="num">직접 (예상÷실제)</th><th class="num">위임 (예상÷실제)</th></tr></thead><tbody>';
    for (var i = 0; i < n; i++) {
      var w = weekly[i];
      var dirStr = w.direct !== null && w.direct !== undefined ? w.direct + "배" : "-";
      var delStr = w.delegate !== null && w.delegate !== undefined ? w.delegate + "배" : "-";
      tHtml += '<tr><td>' + escapeHtml(w.week) + '</td><td class="num">' + dirStr + '</td><td class="num">' + delStr + '</td></tr>';
    }
    tHtml += '</tbody></table>';
    els.tableAccuracyView.innerHTML = tHtml;
  }

  function renderChartTimeAccuracy(weekly) {
    if (!els.chartTimeAccuracyView || !els.tableTimeAccuracyView) return;
    weekly = weekly || [];
    var n = weekly.length;
    if (!n) {
      els.chartTimeAccuracyView.innerHTML = '<div class="empty-hint" style="padding:40px;text-align:center;">주별 처리 시간 정확도 표본이 아직 없습니다.</div>';
      els.tableTimeAccuracyView.innerHTML = '<div class="empty-hint" style="padding:40px;text-align:center;">주별 처리 시간 정확도 표본이 아직 없습니다.</div>';
      return;
    }

    var maxR = 2.0;
    for (var i = 0; i < n; i++) {
      if (weekly[i].time_direct !== null && weekly[i].time_direct !== undefined && weekly[i].time_direct > maxR) maxR = weekly[i].time_direct;
      if (weekly[i].time_delegate !== null && weekly[i].time_delegate !== undefined && weekly[i].time_delegate > maxR) maxR = weekly[i].time_delegate;
    }
    maxR = Math.ceil(maxR * 1.2 * 10) / 10;

    var ticksObj = computeNiceTicks(0, maxR, 4);
    var tickMax = ticksObj.max;

    var svgW = 600, svgH = 220;
    var padLeft = 40, padRight = 75, padTop = 20, padBottom = 32;
    var plotW = svgW - padLeft - padRight;
    var plotH = svgH - padTop - padBottom;
    var baseY = padTop + plotH;

    function scaleY(v) {
      return baseY - (v / tickMax) * plotH;
    }

    var svg = '<svg viewBox="0 0 ' + svgW + ' ' + svgH + '" class="stats-chart-svg" preserveAspectRatio="xMidYMid meet" role="img" aria-label="주별 처리 시간 예상 정확도 차트">';

    for (var t = 0; t < ticksObj.ticks.length; t++) {
      var tick = ticksObj.ticks[t];
      var ty = Math.round(scaleY(tick));
      svg += '<line x1="' + padLeft + '" y1="' + ty + '" x2="' + (padLeft + plotW) + '" y2="' + ty + '" stroke="var(--line)" stroke-width="1"/>';
      svg += '<text x="' + (padLeft - 8) + '" y="' + (ty + 4) + '" text-anchor="end" font-size="11" fill="var(--ink-3)">' + tick.toFixed(1) + '</text>';
    }

    var y1 = Math.round(scaleY(1.0));
    svg += '<line x1="' + padLeft + '" y1="' + y1 + '" x2="' + (padLeft + plotW) + '" y2="' + y1 + '" stroke="var(--ink-2)" stroke-width="1" stroke-dasharray="4,4"/>';
    svg += '<text x="' + (padLeft + plotW + 6) + '" y="' + (y1 + 4) + '" font-size="10" fill="var(--ink-2)">정확 (1.0)</text>';

    var slotW = n > 1 ? plotW / (n - 1) : plotW;

    var dirPts = [], delPts = [];
    for (var i = 0; i < n; i++) {
      var cx = n > 1 ? (padLeft + i * slotW) : (padLeft + plotW / 2);
      if (weekly[i].time_direct !== null && weekly[i].time_direct !== undefined) {
        dirPts.push({ x: cx, y: Math.round(scaleY(weekly[i].time_direct)), val: weekly[i].time_direct, idx: i });
      }
      if (weekly[i].time_delegate !== null && weekly[i].time_delegate !== undefined) {
        delPts.push({ x: cx, y: Math.round(scaleY(weekly[i].time_delegate)), val: weekly[i].time_delegate, idx: i });
      }
    }

    if (dirPts.length > 1) {
      var pD = "M " + dirPts[0].x + " " + dirPts[0].y;
      for (var i = 1; i < dirPts.length; i++) { pD += " L " + dirPts[i].x + " " + dirPts[i].y; }
      svg += '<path d="' + pD + '" fill="none" stroke="var(--claude)" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>';
    }
    for (var i = 0; i < dirPts.length; i++) {
      svg += '<circle cx="' + dirPts[i].x + '" cy="' + dirPts[i].y + '" r="4" fill="var(--claude)" stroke="var(--surface)" stroke-width="2"/>';
    }
    if (dirPts.length > 0) {
      var lastD = dirPts[dirPts.length - 1];
      svg += '<text x="' + (lastD.x + 6) + '" y="' + (lastD.y + 4) + '" font-size="11" font-weight="600" fill="var(--claude)">직접 ' + lastD.val + '배</text>';
    }

    if (delPts.length > 1) {
      var pDel = "M " + delPts[0].x + " " + delPts[0].y;
      for (var i = 1; i < delPts.length; i++) { pDel += " L " + delPts[i].x + " " + delPts[i].y; }
      svg += '<path d="' + pDel + '" fill="none" stroke="var(--agy)" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>';
    }
    for (var i = 0; i < delPts.length; i++) {
      svg += '<circle cx="' + delPts[i].x + '" cy="' + delPts[i].y + '" r="4" fill="var(--agy)" stroke="var(--surface)" stroke-width="2"/>';
    }
    if (delPts.length > 0) {
      var lastDel = delPts[delPts.length - 1];
      svg += '<text x="' + (lastDel.x + 6) + '" y="' + (lastDel.y + 4) + '" font-size="11" font-weight="600" fill="var(--agy)">위임 ' + lastDel.val + '배</text>';
    }

    for (var i = 0; i < n; i++) {
      var cx = n > 1 ? (padLeft + i * slotW) : (padLeft + plotW / 2);
      var hW = n > 1 ? slotW : plotW;
      var ariaLabel = weekly[i].week + " 직접: " + (weekly[i].time_direct !== null ? weekly[i].time_direct + "배" : "-") + ", 위임: " + (weekly[i].time_delegate !== null ? weekly[i].time_delegate + "배" : "-");
      svg += '<rect class="chart-hit-slot" data-chart="time-accuracy" data-idx="' + i + '" x="' + (cx - hW / 2) + '" y="' + padTop + '" width="' + hW + '" height="' + plotH + '" fill="transparent" tabindex="0" role="graphics-symbol" aria-label="' + escapeHtml(ariaLabel) + '" style="cursor:pointer;outline:none;"/>';
      svg += '<text x="' + cx + '" y="' + (baseY + 18) + '" text-anchor="middle" font-size="11" fill="var(--ink-3)">' + escapeHtml(weekly[i].week) + '</text>';
    }

    svg += '</svg>';
    els.chartTimeAccuracyView.innerHTML = svg;

    var tHtml = '<table class="stats-data-table"><thead><tr><th>주차</th><th class="num">직접 (예상÷실제)</th><th class="num">위임 (예상÷실제)</th></tr></thead><tbody>';
    for (var i = 0; i < n; i++) {
      var w = weekly[i];
      var dirStr = w.time_direct !== null && w.time_direct !== undefined ? w.time_direct + "배" : "-";
      var delStr = w.time_delegate !== null && w.time_delegate !== undefined ? w.time_delegate + "배" : "-";
      tHtml += '<tr><td>' + escapeHtml(w.week) + '</td><td class="num">' + dirStr + '</td><td class="num">' + delStr + '</td></tr>';
    }
    tHtml += '</tbody></table>';
    els.tableTimeAccuracyView.innerHTML = tHtml;
  }

  function renderChartScatter(points, cal) {
    if (!els.chartScatterView || !els.tableScatterView) return;
    points = points || [];
    var n = points.length;

    var maxCalls = 0, maxActual = 0;
    for (var i = 0; i < n; i++) {
      var c = points[i].calls || 0;
      var a = points[i].actual || 0;
      if (c > maxCalls) maxCalls = c;
      if (a > maxActual) maxActual = a;
    }
    if (maxCalls < 10) maxCalls = 10;
    if (maxActual < 5000) maxActual = 5000;
    maxCalls = Math.ceil(maxCalls * 1.15);
    maxActual = Math.ceil(maxActual * 1.15);

    var ticksX = computeNiceTicks(0, maxCalls, 5);
    var ticksY = computeNiceTicks(0, maxActual, 5);
    var xMax = ticksX.max;
    var yMax = ticksY.max;

    var svgW = 600, svgH = 240;
    var padLeft = 48, padRight = 24, padTop = 20, padBottom = 34;
    var plotW = svgW - padLeft - padRight;
    var plotH = svgH - padTop - padBottom;
    var baseY = padTop + plotH;

    function scaleX(v) { return padLeft + (v / xMax) * plotW; }
    function scaleY(v) { return baseY - (v / yMax) * plotH; }

    var dirA = (cal && cal.direct && typeof cal.direct.a === "number") ? cal.direct.a : 800;
    var dirB = (cal && cal.direct && typeof cal.direct.b === "number") ? cal.direct.b : 1300;
    var delA = (cal && cal.delegate && typeof cal.delegate.a === "number") ? cal.delegate.a : 2500;
    var delB = (cal && cal.delegate && typeof cal.delegate.b === "number") ? cal.delegate.b : 1000;

    var crossX = computeLinearIntersection(dirA, dirB, delA, delB);
    if (els.statsScatterCrossover) {
      if (crossX !== null && crossX > 0) {
        els.statsScatterCrossover.textContent = "약 " + crossX + "번부터 위임이 쌈";
      } else {
        els.statsScatterCrossover.textContent = "";
      }
    }

    var svg = '<svg viewBox="0 0 ' + svgW + ' ' + svgH + '" class="stats-chart-svg" preserveAspectRatio="xMidYMid meet" role="img" aria-label="호출 수와 실제 토큰 산점도">';

    for (var t = 0; t < ticksY.ticks.length; t++) {
      var tick = ticksY.ticks[t];
      var ty = Math.round(scaleY(tick));
      svg += '<line x1="' + padLeft + '" y1="' + ty + '" x2="' + (padLeft + plotW) + '" y2="' + ty + '" stroke="var(--line)" stroke-width="1"/>';
      svg += '<text x="' + (padLeft - 8) + '" y="' + (ty + 4) + '" text-anchor="end" font-size="11" fill="var(--ink-3)">' + formatTokenK(tick, false) + '</text>';
    }

    for (var t = 0; t < ticksX.ticks.length; t++) {
      var tick = ticksX.ticks[t];
      var tx = Math.round(scaleX(tick));
      svg += '<line x1="' + tx + '" y1="' + padTop + '" x2="' + tx + '" y2="' + baseY + '" stroke="var(--line)" stroke-width="1"/>';
      svg += '<text x="' + tx + '" y="' + (baseY + 18) + '" text-anchor="middle" font-size="11" fill="var(--ink-3)">' + tick + '회</text>';
    }

    var dirY0 = scaleY(dirA), dirYEnd = scaleY(dirA + dirB * xMax);
    svg += '<line x1="' + padLeft + '" y1="' + dirY0 + '" x2="' + (padLeft + plotW) + '" y2="' + dirYEnd + '" stroke="var(--claude)" stroke-width="2" stroke-linecap="round"/>';

    var delY0 = scaleY(delA), delYEnd = scaleY(delA + delB * xMax);
    svg += '<line x1="' + padLeft + '" y1="' + delY0 + '" x2="' + (padLeft + plotW) + '" y2="' + delYEnd + '" stroke="var(--agy)" stroke-width="2" stroke-linecap="round"/>';

    if (crossX !== null && crossX > 0 && crossX <= xMax) {
      var crossYVal = dirA + dirB * crossX;
      var cxPos = Math.round(scaleX(crossX));
      var cyPos = Math.round(scaleY(crossYVal));
      svg += '<line x1="' + cxPos + '" y1="' + cyPos + '" x2="' + cxPos + '" y2="' + baseY + '" stroke="var(--ink-2)" stroke-width="1" stroke-dasharray="3,3"/>';
      svg += '<rect x="' + (cxPos - 60) + '" y="' + (cyPos - 22) + '" width="120" height="18" rx="3" fill="var(--raised)" stroke="var(--line-strong)" stroke-width="1"/>';
      svg += '<text x="' + cxPos + '" y="' + (cyPos - 10) + '" font-size="10" font-weight="600" fill="var(--ink)" text-anchor="middle">약 ' + crossX + '번부터 위임이 쌈</text>';
    }

    for (var i = 0; i < n; i++) {
      var pt = points[i];
      var cx = Math.round(scaleX(pt.calls || 0));
      var cy = Math.round(scaleY(pt.actual || 0));
      var isDirect = (pt.path === "direct");
      if (isDirect) {
        svg += '<circle cx="' + cx + '" cy="' + cy + '" r="4.5" fill="var(--claude)" stroke="var(--surface)" stroke-width="2"/>';
      } else {
        svg += '<rect x="' + (cx - 4.5) + '" y="' + (cy - 4.5) + '" width="9" height="9" rx="1" fill="var(--agy)" stroke="var(--surface)" stroke-width="2"/>';
      }

      var ariaLabel = (isDirect ? "직접 처리" : "위임") + " 호출 " + (pt.calls || 0) + "회, 실제 " + formatTokenK(pt.actual || 0, false);
      svg += '<circle class="chart-hit-scatter" data-chart="scatter" data-idx="' + i + '" cx="' + cx + '" cy="' + cy + '" r="12" fill="transparent" tabindex="0" role="graphics-symbol" aria-label="' + escapeHtml(ariaLabel) + '" style="cursor:pointer;outline:none;"/>';
    }

    svg += '</svg>';
    els.chartScatterView.innerHTML = svg;

    var tHtml = '<table class="stats-data-table"><thead><tr><th>길</th><th class="num">도구 호출 수</th><th class="num">실제 사용 토큰</th></tr></thead><tbody>';
    for (var i = 0; i < n; i++) {
      var pt = points[i];
      var pathLabel = pt.path === "direct" ? "직접" : "위임";
      tHtml += '<tr><td>' + pathLabel + '</td><td class="num">' + (pt.calls || 0) + '회</td><td class="num">' + formatTokenK(pt.actual || 0, false) + '</td></tr>';
    }
    tHtml += '</tbody></table>';
    els.tableScatterView.innerHTML = tHtml;
  }

  function renderRecentTable(recent) {
    if (!els.statsRecentTbody) return;
    recent = recent || [];
    if (!recent.length) {
      els.statsRecentTbody.innerHTML = '<tr><td colspan="12" style="text-align:center;padding:24px;color:var(--ink-3);">최근 턴 기록이 없습니다.</td></tr>';
      return;
    }
    var html = '';
    for (var i = 0; i < recent.length; i++) {
      var it = recent[i];
      // 수집기는 시각을 UTC("…Z")로 저장한다. 이 PC의 시간대로 바꿔서 보인다(문자열을 잘라 쓰면 9시간 어긋난다).
      var tsDate = it.ts ? new Date(it.ts) : null;
      var tsOk = tsDate && !isNaN(tsDate.getTime());
      var tsFull = tsOk ? tsDate.getFullYear() + "-" + pad2(tsDate.getMonth() + 1) + "-" + pad2(tsDate.getDate()) + " " + pad2(tsDate.getHours()) + ":" + pad2(tsDate.getMinutes()) + ":" + pad2(tsDate.getSeconds()) : "-";
      var tsStr = tsOk ? tsFull.slice(5, 16) : "-";   // 11-06 11:37 (전체 시각은 마우스를 올리면)
      var pStr = it.project || "-";
      var pShort = pStr.length > 18 ? "…" + pStr.slice(-17) : pStr;   // 앞을 줄여 뒤 이름(폴더 이름)을 다 보인다
      var pathBadge = '';
      if (it.path === "direct") {
        pathBadge = '<span class="path-badge direct">직접</span>';
      } else if (it.path === "delegate") {
        pathBadge = '<span class="path-badge delegate">위임</span>';
      } else if (it.path === "chat") {
        pathBadge = '<span class="path-badge chat">대화</span>';
      } else {
        pathBadge = '<span class="path-badge">' + escapeHtml(it.path || "-") + '</span>';
      }
      var callsCount = (it.path === "delegate" && it.calls_related !== null && it.calls_related !== undefined) ? it.calls_related : it.calls;
      var callsStr = callsCount !== null && callsCount !== undefined ? callsCount : "-";
      var crStr = (it.cr_tokens !== null && it.cr_tokens !== undefined) ? formatTokenCompact(it.cr_tokens) : "—";
      var estStr = it.estimate !== null && it.estimate !== undefined ? formatTokenK(it.estimate, false) : "-";
      if (it.est_ver === "v1") {
        estStr += ' <span class="tag-v1">옛 형식</span>';
      }
      var actStr = it.actual !== null && it.actual !== undefined ? formatTokenK(it.actual, false) : "-";
      var ratioStr = it.ratio !== null && it.ratio !== undefined ? it.ratio + "배" : "-";
      var savedHtml = "-";
      if (it.saved !== null && it.saved !== undefined) {
        var itDelta = -it.saved;   // + 증가(더 소모, 주황) / - 감소(절약, 초록)
        var sCls = itDelta <= 0 ? "val-ok" : "val-err";
        savedHtml = '<span class="' + sCls + '">' + formatTokenK(itDelta, true) + '</span>';
      }
      var estTimeStr = formatTimeKo(it.est_time);
      var actTimeStr = formatTimeKo(it.actual_time);
      var claudeWallStr = formatTimeKo(it.claude_wall);

      html += '<tr>' +
              '<td title="' + escapeHtml(tsFull) + '">' + escapeHtml(tsStr) + '</td>' +
              '<td title="' + escapeHtml(pStr) + '">' + escapeHtml(pShort) + '</td>' +
              '<td>' + pathBadge + '</td>' +
              '<td class="num">' + callsStr + '</td>' +
              '<td class="num">' + crStr + '</td>' +
              '<td class="num">' + estStr + '</td>' +
              '<td class="num">' + actStr + '</td>' +
              '<td class="num">' + ratioStr + '</td>' +
              '<td class="num">' + savedHtml + '</td>' +
              '<td class="num">' + estTimeStr + '</td>' +
              '<td class="num">' + actTimeStr + '</td>' +
              '<td class="num">' + claudeWallStr + '</td>' +
              '</tr>';
    }
    els.statsRecentTbody.innerHTML = html;
  }

  function renderStats(data) {
    var collectData = (data && data.summary && data.summary.collect) || (data && data.calibration && data.calibration.collect) || null;
    var bannerState = getCollectBannerState(collectData);
    if (els.statsCollectBanner) {
      if (bannerState.show) {
        els.statsCollectBanner.style.display = "flex";
        if (els.statsCollectTitle) els.statsCollectTitle.textContent = bannerState.title;
        if (els.statsCollectDesc) els.statsCollectDesc.textContent = bannerState.desc;
        if (els.statsCollectFill) {
          els.statsCollectFill.style.width = bannerState.pct + "%";
          var pBar = els.statsCollectFill.parentElement;
          if (pBar) {
            pBar.setAttribute("aria-valuenow", String(bannerState.pct));
            pBar.setAttribute("aria-valuetext", bannerState.title);
          }
        }
      } else {
        els.statsCollectBanner.style.display = "none";
      }
    }

    if (!data) {
      if (els.statsHeroSaved) {
        els.statsHeroSaved.textContent = "통계를 불러오지 못했습니다. 지금 갱신을 눌러 다시 시도해 주세요.";
        els.statsHeroSaved.className = "stats-hero-number stats-error";
      }
      if (els.statsHeroDesc) {
        els.statsHeroDesc.textContent = "";
      }
      if (els.statsEmptyState) {
        var emptyMsg = els.statsEmptyState.querySelector(".stats-empty-msg");
        if (emptyMsg) {
          emptyMsg.textContent = "통계를 불러오지 못했습니다. 지금 갱신을 눌러 다시 시도해 주세요.";
        }
        els.statsEmptyState.style.display = "flex";
      }
      if (els.statsContentWrap) els.statsContentWrap.style.display = "none";
      return;
    }

    if (!data.summary && (!data.daily || !data.daily.length)) {
      if (els.statsEmptyState) {
        var emptyMsg1 = els.statsEmptyState.querySelector(".stats-empty-msg");
        if (emptyMsg1) {
          emptyMsg1.innerHTML = "아직 모인 통계가 없습니다. 위임이나 직접 처리 답변 끝에 '예상 토큰'이 적히면 다음 갱신 때 여기에 쌓입니다.<br>위임을 20건 하면 보정식이 이 PC 에 맞춰집니다.";
        }
        els.statsEmptyState.style.display = "flex";
      }
      if (els.statsContentWrap) els.statsContentWrap.style.display = "none";
      return;
    }

    var sum = data.summary || {};
    var samples = sum.samples || 0;
    var hasDailyActivity = false;
    if (data.daily) {
      for (var i = 0; i < data.daily.length; i++) {
        var d = data.daily[i];
        if (d.ok > 0 || d.fail > 0 || d.saved !== 0 || d.direct_turns > 0 || d.delegate_turns > 0) {
          hasDailyActivity = true;
          break;
        }
      }
    }

    if (samples === 0 && !hasDailyActivity && (!data.recent || !data.recent.length)) {
      if (els.statsEmptyState) {
        var emptyMsg2 = els.statsEmptyState.querySelector(".stats-empty-msg");
        if (emptyMsg2) {
          emptyMsg2.innerHTML = "아직 모인 통계가 없습니다. 위임이나 직접 처리 답변 끝에 '예상 토큰'이 적히면 다음 갱신 때 여기에 쌓입니다.<br>위임을 20건 하면 보정식이 이 PC 에 맞춰집니다.";
        }
        els.statsEmptyState.style.display = "flex";
      }
      if (els.statsContentWrap) els.statsContentWrap.style.display = "none";
      return;
    }

    if (els.statsEmptyState) els.statsEmptyState.style.display = "none";
    if (els.statsContentWrap) els.statsContentWrap.style.display = "block";

    // 1) 헤더 메타
    if (els.statsUpdatedTime) {
      els.statsUpdatedTime.textContent = "갱신: " + (data.updated || "-");
    }
    var segmentBtns = document.querySelectorAll(".stats-days-segment .segment-btn");
    for (var b = 0; b < segmentBtns.length; b++) {
      var dVal = parseInt(segmentBtns[b].getAttribute("data-days"), 10);
      segmentBtns[b].classList.toggle("active", dVal === (data.days || statsDays));
    }

    // 2) 헤드라인
    // 부호의 뜻: + 는 직접 했을 때(또는 다른 쪽으로 처리했을 때)보다 토큰이 늘어난 것(더 소모, 주황), - 는 줄어든 것(절약, 초록)
    var netDelta = -(sum.net_saved || 0);
    if (els.statsHeroSaved) {
      els.statsHeroSaved.textContent = formatTokenK(netDelta, true) + " 토큰";
      els.statsHeroSaved.className = "stats-hero-number " + (netDelta <= 0 ? "ok" : "err");
    }
    if (els.statsHeroDesc) {
      els.statsHeroDesc.textContent = "최근 " + (data.days || 30) + "일 · 위임 " + (sum.delegate_turns || 0) + "건, 직접 " + (sum.direct_turns || 0) + "턴 기준 · 추정값";
    }

    var totTasks = (sum.delegate_ok || 0) + (sum.delegate_fail || 0);
    if (els.statsSumSuccess) {
      var sRate = totTasks > 0 ? "위임 성공률 " + Math.round((sum.delegate_ok / totTasks) * 100) + "% (" + sum.delegate_ok + "/" + totTasks + ")" : "위임 성공률 -";
      els.statsSumSuccess.textContent = sRate;
    }

    if (els.statsSumAccuracy) {
      var rDir = (sum.ratio_direct !== null && sum.ratio_direct !== undefined) ? sum.ratio_direct + "배" : "-";
      var rDel = (sum.ratio_delegate !== null && sum.ratio_delegate !== undefined) ? sum.ratio_delegate + "배" : "-";
      els.statsSumAccuracy.textContent = "예상 정확도 직접 " + rDir + " · 위임 " + rDel + " (예상÷실제, 1에 가까울수록 정확)";
    }

    if (els.statsSumFormula) {
      var cal = data.calibration;
      var formulaStr = "";
      if (cal && cal.direct && cal.delegate) {
        formulaStr = "보정식 직접 ≈ " + formatTokenK(cal.direct.a, false) + " + " + formatTokenK(cal.direct.b, false) + "×호출, 위임 ≈ " + formatTokenK(cal.delegate.a, false) + " + " + formatTokenK(cal.delegate.b, false) + "×호출";
      } else {
        formulaStr = "보정식 직접 ≈ 0.8k + 1.3k×호출, 위임 ≈ 2.5k + 1.0k×호출";
      }
      els.statsSumFormula.textContent = "표본 " + (sum.samples || 0) + "턴 · " + formulaStr;
    }

    if (els.statsSumCache) {
      if (data && data.calibration && data.calibration.context_reread_per_call != null) {
        var crk = formatTokenCompact(data.calibration.context_reread_per_call);
        els.statsSumCache.textContent = "호출당 캐시 재읽기 약 " + crk + " (참고, 절약 계산에는 넣지 않음)";
        els.statsSumCache.style.display = "block";
      } else {
        els.statsSumCache.style.display = "none";
      }
    }

    if (els.statsSumTime) {
      var tSum = sum.time;
      var tDirAvg = (tSum && tSum.direct_avg_s != null) ? formatTimeKo(tSum.direct_avg_s) : "—";
      var tDelAgyAvg = (tSum && tSum.delegate_agy_avg_s != null) ? formatTimeKo(tSum.delegate_agy_avg_s) : "—";
      var tDelTurnAvg = (tSum && tSum.delegate_turn_avg_s != null) ? formatTimeKo(tSum.delegate_turn_avg_s) : "—";
      var tRatDir = (tSum && tSum.ratio_time_direct != null) ? tSum.ratio_time_direct + "배" : "-";
      var tRatDel = (tSum && tSum.ratio_time_delegate != null) ? tSum.ratio_time_delegate + "배" : "-";
      els.statsSumTime.textContent = "처리 시간 · 직접 평균 " + tDirAvg + " · 위임(agy 처리) 평균 " + tDelAgyAvg + " · 위임 턴 Claude 활동 평균 " + tDelTurnAvg + " · 예상 정확도 직접 " + tRatDir + " · 위임 " + tRatDel;
      els.statsSumTime.style.display = "block";
    }

    // 3) 차트 렌더링
    renderChartTasks(data.daily);
    renderChartSavings(data.daily);
    renderChartAccuracy(data.weekly_accuracy);
    renderChartScatter(data.points, data.calibration);
    renderChartTimeAccuracy(data.weekly_accuracy);
    renderRecentTable(data.recent);
    applyStatsTableToggle();
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

    return [pParts.join("|"), uParts.join("|"), tlParts.join(","), hlParts.join(",")].join("#");
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
    return Promise.all([
      loadSystemStatus(),
      loadAllQa(force),
      loadPending(),
      loadHandoffProjects(force),
      loadClaudeTree()
    ]).then(function (results) {
      var qaRes = results[1] || { changed: false };
      var pList = results[2] || [];
      var treeRes = results[4] || { changed: false };

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
      renderHandoffTree();

      if (currentNav === "dashboard") {
        renderDashboard();
      } else if (currentNav === "stats") {
        var nowTs = Date.now();
        if (force || (nowTs - lastStatsFetchAt >= 30000)) {
          if (!isStatsHovering) {
            loadStats(statsDays).then(function (data) {
              renderStats(data);
            });
          }
        }
      } else if (currentNav === "qa") {
        if (qaNeedsRender) {
          applyQaFilters();
        } else {
          updateQaHeader();
          renderProcessDialog();
        }
      } else if (currentNav === "handoff") {
        if (force || treeRes.changed || qaRes.changed) {   // qaRes: 새 위임 기록이 들어오면 회신 카드의 토큰 칩도 갱신
          renderHandoffView();
        }
        refreshHandoffLive();
        renderProcessDialog();
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
  // Event Bindings & Initializers
  // ==========================================================================

  function bindEvents() {
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
    if (els.navBtnStats) els.navBtnStats.addEventListener("click", function () { switchNav("stats"); });
    if (els.navBtnQa) els.navBtnQa.addEventListener("click", function () { switchNav("qa"); });
    if (els.navBtnHandoff) els.navBtnHandoff.addEventListener("click", function () { switchNav("handoff"); });

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
        if (els.appSidebar) els.appSidebar.classList.toggle("open");
      });
    }

    // 대시보드 내 "모두 보기" 링크
    if (els.btnViewAllQa) {
      els.btnViewAllQa.addEventListener("click", function () {
        selectQaProject("");
        switchNav("qa");
      });
    }
    if (els.btnViewAllHandoff) {
      els.btnViewAllHandoff.addEventListener("click", function () {
        switchNav("handoff");
      });
    }

    // QA 세션 사이드바 검색 및 필터
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
    if (els.handoffCards) {
      els.handoffCards.addEventListener("click", function (e) {
        var procBtn = e.target && e.target.closest ? e.target.closest(".proc-open") : null;
        if (procBtn) { openProcessDialog(procBtn.getAttribute("data-proc-key")); }
      });
    }
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

    // 통계 기간 버튼 이벤트
    var dayBtns = document.querySelectorAll(".stats-days-segment .segment-btn");
    for (var db = 0; db < dayBtns.length; db++) {
      dayBtns[db].addEventListener("click", function () {
        var d = parseInt(this.getAttribute("data-days"), 10);
        if (d === 7 || d === 30 || d === 60) {
          statsDays = d;
          updateHash();
          fetchAndRenderStats(true);
        }
      });
    }

    // 통계 지금 갱신 버튼 이벤트
    function handleStatsRefresh() {
      if (els.statsRefreshBtn) els.statsRefreshBtn.textContent = "갱신 요청 중...";
      fetchJson("/api/token-stats/refresh", { method: "POST" }).then(function () {
        setTimeout(function () {
          if (els.statsRefreshBtn) els.statsRefreshBtn.textContent = "지금 갱신";
          fetchAndRenderStats(true);
        }, 2500);
      }).catch(function () {
        if (els.statsRefreshBtn) els.statsRefreshBtn.textContent = "지금 갱신";
      });
    }
    if (els.statsRefreshBtn) els.statsRefreshBtn.addEventListener("click", handleStatsRefresh);
    if (els.statsEmptyRefreshBtn) els.statsEmptyRefreshBtn.addEventListener("click", handleStatsRefresh);

    // 통계 표로 보기 토글 이벤트
    if (els.statsTableToggle) {
      els.statsTableToggle.addEventListener("change", function () {
        statsTableView = Boolean(this.checked);
        applyStatsTableToggle();
      });
    }

    // 통계 차트 툴팁 및 호버 감지 (호버 중 자동 갱신 방지)
    var statsCont = document.querySelector(".stats-page-container");
    if (statsCont) {
      statsCont.addEventListener("pointerenter", function () {
        isStatsHovering = true;
      });
      statsCont.addEventListener("pointerleave", function () {
        isStatsHovering = false;
        hideStatsTooltip();
      });

      statsCont.addEventListener("pointerover", function (e) {
        var target = e.target;
        if (!target) return;
        var chartType = target.getAttribute("data-chart");
        var idxStr = target.getAttribute("data-idx");
        if (!chartType || idxStr === null) return;
        var idx = parseInt(idxStr, 10);
        if (isNaN(idx)) return;

        if (chartType === "tasks" && statsData && statsData.daily && statsData.daily[idx]) {
          var d = statsData.daily[idx];
          showStatsTooltip(e, d.date, [
            { label: "성공", value: (d.ok || 0) + "건", color: "var(--ok)" },
            { label: "실패", value: (d.fail || 0) + "건", color: "var(--err)" },
            { label: "전체", value: ((d.ok || 0) + (d.fail || 0)) + "건" }
          ]);
        } else if (chartType === "savings" && statsData && statsData.daily && statsData.daily[idx]) {
          var d = statsData.daily[idx];
          showStatsTooltip(e, d.date, [
            { label: "그날 증감 (추정)", value: formatTokenK(-(d.saved || 0), true), color: (d.saved || 0) >= 0 ? "var(--gain)" : "var(--loss)" },
            { label: "누적 증감 (추정)", value: formatTokenK(-(d.cum_saved || 0), true), color: "var(--ink)" }
          ]);
        } else if (chartType === "accuracy" && statsData && statsData.weekly_accuracy && statsData.weekly_accuracy[idx]) {
          var w = statsData.weekly_accuracy[idx];
          showStatsTooltip(e, w.week, [
            { label: "직접", value: w.direct !== null && w.direct !== undefined ? w.direct + "배" : "-", color: "var(--claude)" },
            { label: "위임", value: w.delegate !== null && w.delegate !== undefined ? w.delegate + "배" : "-", color: "var(--agy)" }
          ]);
        } else if (chartType === "time-accuracy" && statsData && statsData.weekly_accuracy && statsData.weekly_accuracy[idx]) {
          var w = statsData.weekly_accuracy[idx];
          showStatsTooltip(e, w.week, [
            { label: "직접", value: w.time_direct !== null && w.time_direct !== undefined ? w.time_direct + "배" : "-", color: "var(--claude)" },
            { label: "위임", value: w.time_delegate !== null && w.time_delegate !== undefined ? w.time_delegate + "배" : "-", color: "var(--agy)" }
          ]);
        } else if (chartType === "scatter" && statsData && statsData.points && statsData.points[idx]) {
          var pt = statsData.points[idx];
          var isDir = (pt.path === "direct");
          showStatsTooltip(e, isDir ? "직접 처리" : "에이전트 위임", [
            { label: "도구 호출", value: (pt.calls || 0) + "회" },
            { label: "실제 토큰", value: formatTokenK(pt.actual || 0, false), color: isDir ? "var(--claude)" : "var(--agy)" }
          ]);
        }
      });

      statsCont.addEventListener("pointermove", function (e) {
        if (els.statsTooltip && els.statsTooltip.style.display !== "none") moveStatsTooltip(e);
      });

      statsCont.addEventListener("pointerout", function (e) {
        var target = e.target;
        if (target && target.hasAttribute("data-chart")) {
          hideStatsTooltip();
        }
      });
    }

    // 브라우저 해시 변경 감지 (뒤로가기/앞으로가기)
    var applyHashRoute = function () {
      var parsed = parseHash();
      if (parsed.nav !== currentNav) {
        switchNav(parsed.nav, false);
      }
      if (parsed.nav === "stats") {
        var daysChanged = (parsed.days !== statsDays);
        if (daysChanged) {
          statsDays = parsed.days || 30;
          fetchAndRenderStats(true);
        }
      } else if (parsed.nav === "qa") {
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
      } else if (parsed.nav === "handoff" && (parsed.project !== currentHandoffProject || parsed.session !== currentHandoffSession)) {
        selectHandoffSession(parsed.session, parsed.project);
      }
    };
    window.addEventListener("hashchange", function () {
      hashRouting = true;
      try { applyHashRoute(); } finally { hashRouting = false; }
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
  if (initialRoute.nav === "stats") {
    statsDays = initialRoute.days || 30;
  } else if (initialRoute.nav === "qa") {
    if (initialRoute.session) { currentQaSession = initialRoute.session; }
    if (initialRoute.project) { currentQaProject = initialRoute.project; }
    if (initialRoute.agy) { currentQaAgy = initialRoute.agy; }
  } else if (initialRoute.nav === "handoff") {
    if (initialRoute.session) { currentHandoffSession = initialRoute.session; }
    if (initialRoute.project) { currentHandoffProject = initialRoute.project; }
  }

  // 최초 네비게이션 적용
  switchNav(initialRoute.nav, false);

  // 최초 데이터 로드 및 타이머 시작
  refresh(true).then(scheduleAutoRefresh);
})();
