/* 확장의 배경 일꾼.
 *
 * 페이지에 심어 둔 content.js 는 금고에 직접 말을 걸 수 없습니다.
 * 여기서만 네이티브 메시징으로 맥의 금고 앱에 물어봅니다.
 *
 * 지키는 규칙
 * - 주소는 content.js 가 보내온 것을 쓰지 않고, 크롬이 알려주는 **보낸 탭의 실제 주소**를 씁니다.
 *   페이지 스크립트가 주소를 속여 남의 비밀번호를 빼가지 못하게 하려는 것입니다.
 * - 받아온 비밀번호는 여기에 저장하지 않고 그대로 넘기기만 합니다.
 */

const HOST = "com.github.soojinoh.passwordvault";

function ask(message) {
  return new Promise((resolve) => {
    try {
      chrome.runtime.sendNativeMessage(HOST, message, (reply) => {
        if (chrome.runtime.lastError) {
          resolve({ ok: false, error: chrome.runtime.lastError.message });
        } else {
          resolve(reply || { ok: false, error: "빈 응답" });
        }
      });
    } catch (e) {
      resolve({ ok: false, error: String(e) });
    }
  });
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg?.type !== "lookup") return false;

  // ★ 주소는 보낸 쪽 말을 믿지 않는다. 크롬이 아는 그 프레임의 진짜 주소를 쓴다.
  const url = sender?.url || "";
  if (!/^https?:\/\//i.test(url)) {
    sendResponse({ ok: true, items: [] });
    return true;
  }

  ask({ v: 1, op: "lookup", url }).then((reply) => {
    if (!reply.ok) {
      sendResponse({ ok: false, error: reply.error || "금고에 물어보지 못했습니다." });
    } else if (reply.locked) {
      sendResponse({ ok: true, locked: true, items: [] });
    } else {
      sendResponse({ ok: true, items: reply.items || [] });
    }
  });
  return true;   // 비동기 응답
});
