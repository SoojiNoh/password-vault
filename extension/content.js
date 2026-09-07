/* 로그인 칸 옆에 "금고에서 채우기" 목록을 띄우고, 고른 것을 채워 넣습니다.
 *
 * 안전 규칙
 * - **사람이 목록에서 고를 때만** 값이 들어갑니다. 저절로 채우지 않습니다.
 *   보이지 않는 가짜 로그인 폼을 심어 두고 자동완성을 낚아채는 수법을 막기 위해서입니다.
 * - 폼을 대신 제출하지 않습니다. 확인은 사람이 합니다.
 * - 목록은 shadow DOM 안에 그려서 페이지 CSS·스크립트와 섞이지 않게 합니다.
 * - 비밀번호는 목록에 글자로 쓰지 않습니다. 고르기 전에는 화면에 나오지 않습니다.
 */
(() => {
  "use strict";
  if (window.__vaultAutofillLoaded) return;
  window.__vaultAutofillLoaded = true;

  let panel = null;      // { host, shadow, list }
  let anchor = null;     // 지금 목록이 붙어 있는 입력칸

  // ── 입력칸 찾기 ────────────────────────────────────────────────
  const isPassword = (el) =>
    el instanceof HTMLInputElement && el.type === "password";

  const isUsername = (el) => {
    if (!(el instanceof HTMLInputElement)) return false;
    if (["text", "email", "tel", ""].indexOf(el.type) < 0) return false;
    const hay = [el.name, el.id, el.autocomplete, el.placeholder,
                 el.getAttribute("aria-label")].join(" ").toLowerCase();
    if (/user|email|login|account|id\b|아이디|이메일/.test(hay)) return true;
    // 같은 폼 안에 비밀번호 칸이 있으면 그 앞의 글자칸을 아이디로 본다.
    const form = el.form;
    return !!(form && form.querySelector('input[type="password"]'));
  };

  /** 채워 넣을 아이디/비밀번호 칸 한 쌍을 고른다. */
  function fieldsNear(el) {
    const scope = el.form || document;
    const pw = isPassword(el)
      ? el
      : scope.querySelector('input[type="password"]:not([disabled]):not([readonly])');
    let user = isPassword(el) ? null : el;
    if (!user && pw) {
      const inputs = [...scope.querySelectorAll("input")];
      const before = inputs.slice(0, inputs.indexOf(pw)).reverse();
      user = before.find(isUsername) || null;
    }
    return { user, pw };
  }

  // ── 값 넣기 ────────────────────────────────────────────────────
  /* 리액트·뷰 처럼 값을 스스로 관리하는 화면에서도 반영되도록,
     네이티브 setter 로 넣은 뒤 input·change 를 알려 준다. */
  function setValue(input, value) {
    if (!input) return;
    const proto = Object.getPrototypeOf(input);
    const desc = Object.getOwnPropertyDescriptor(proto, "value");
    if (desc && desc.set) desc.set.call(input, value);
    else input.value = value;
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function fill(item, target) {
    const { user, pw } = fieldsNear(target);
    if (user && item.username) setValue(user, item.username);
    if (pw && item.password) setValue(pw, item.password);
    (pw || user)?.focus();
    close();
    // 제출은 사람이 한다. 여기서 form.submit() 을 부르지 않는다.
  }

  // ── 목록 ───────────────────────────────────────────────────────
  function close() {
    panel?.host.remove();
    panel = null;
    anchor = null;
  }

  function open(items, target) {
    close();
    anchor = target;

    const host = document.createElement("div");
    host.style.cssText = "all:initial;position:absolute;z-index:2147483647";
    const shadow = host.attachShadow({ mode: "closed" });

    const style = document.createElement("style");
    style.textContent = `
      .box{font:13px -apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo",sans-serif;
        background:#fff;color:#1b1f2a;border:1px solid #d7dbe4;border-radius:10px;
        box-shadow:0 8px 24px rgba(20,25,40,.16);overflow:hidden;min-width:240px;max-width:360px}
      .hd{padding:7px 11px;font-size:11px;color:#78809a;border-bottom:1px solid #eef0f5;
        display:flex;align-items:center;gap:5px}
      .row{display:block;width:100%;text-align:left;padding:9px 11px;border:0;background:#fff;
        cursor:pointer;font:inherit;border-bottom:1px solid #f4f6fa}
      .row:last-child{border-bottom:0}
      .row:hover,.row:focus{background:#eef2ff;outline:none}
      .t{font-weight:600;display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
      .u{color:#78809a;font-size:12px;display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
      .msg{padding:10px 11px;color:#78809a}
      @media (prefers-color-scheme:dark){
        .box{background:#1e2230;color:#e8eaf0;border-color:#39405a}
        .hd{color:#9aa2bd;border-bottom-color:#2b3145}
        .row{background:#1e2230;border-bottom-color:#2b3145}
        .row:hover,.row:focus{background:#2c3350}
        .u,.msg{color:#9aa2bd}}
    `;

    const box = document.createElement("div");
    box.className = "box";
    const hd = document.createElement("div");
    hd.className = "hd";
    hd.textContent = "🔒 비밀번호 금고";
    box.appendChild(hd);

    if (!items.length) {
      const m = document.createElement("div");
      m.className = "msg";
      m.textContent = "이 사이트에 저장된 로그인이 없습니다.";
      box.appendChild(m);
    } else {
      for (const item of items) {
        const b = document.createElement("button");
        b.type = "button";
        b.className = "row";
        const t = document.createElement("span");
        t.className = "t";
        t.textContent = item.title || "(제목 없음)";
        const u = document.createElement("span");
        u.className = "u";
        u.textContent = item.username || "(아이디 없음)";   // 비밀번호는 절대 쓰지 않는다
        b.append(t, u);
        b.addEventListener("mousedown", (e) => e.preventDefault());
        b.addEventListener("click", () => fill(item, target));
        box.appendChild(b);
      }
    }

    shadow.append(style, box);
    document.body.appendChild(host);
    panel = { host, shadow };
    place();
  }

  function place() {
    if (!panel || !anchor?.isConnected) return close();
    const r = anchor.getBoundingClientRect();
    panel.host.style.left = Math.round(r.left + scrollX) + "px";
    panel.host.style.top = Math.round(r.bottom + scrollY + 4) + "px";
    panel.host.style.width = Math.max(240, Math.round(r.width)) + "px";
  }

  function openLocked(target) {
    close();
    anchor = target;
    open([], target);
    const box = panel?.shadow.querySelector(".msg");
    if (box) box.textContent = "금고가 잠겨 있습니다. 앱에서 잠금을 풀어 주세요.";
  }

  // ── 입력칸을 건드리면 물어본다 ─────────────────────────────────
  let pending = 0;
  function maybeOffer(target) {
    if (!isPassword(target) && !isUsername(target)) return;
    const seq = ++pending;
    chrome.runtime.sendMessage({ type: "lookup" }, (reply) => {
      if (chrome.runtime.lastError) return;       // 앱·확장이 없으면 조용히 넘어간다
      if (seq !== pending || !target.isConnected) return;
      if (document.activeElement !== target) return;
      if (!reply?.ok) return;
      if (reply.locked) return openLocked(target);
      if (reply.items.length) open(reply.items, target);
    });
  }

  document.addEventListener("focusin", (e) => maybeOffer(e.target), true);
  document.addEventListener("click", (e) => {
    if (panel && e.target !== anchor && !panel.host.contains(e.target)) close();
  }, true);
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") close(); }, true);
  addEventListener("scroll", place, true);
  addEventListener("resize", place);
})();
