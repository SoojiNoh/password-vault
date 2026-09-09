import Foundation

/// 브라우저가 보고 있는 주소와 금고 항목을 짝지어 줍니다.
///
/// 자동완성에서 가장 위험한 곳이 여기입니다. 짝짓기를 조금만 헐겁게 만들면
/// `github.com.evil.com` 같은 주소에 진짜 비밀번호를 넘겨주게 됩니다.
/// 그래서 "포함되어 있으면 통과" 같은 규칙은 절대 쓰지 않고,
/// **호스트가 정확히 같거나, 점(.) 으로 끊기는 하위 도메인일 때만** 통과시킵니다.
public enum AutofillMatch {

    /// 주소 문자열에서 호스트만 뽑아 소문자로 정규화합니다.
    /// `https://WWW.Example.com/login?x=1` → `example.com`
    public static func normalizedHost(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var host: String?
        if let url = URL(string: VaultItem.normalizedURLString(trimmed)), let h = url.host {
            host = h
        } else {
            // URL 로 못 읽으면 사용자가 호스트만 적었다고 보고 앞뒤를 정리해 봅니다.
            host = trimmed
                .replacingOccurrences(of: "^[a-zA-Z][a-zA-Z0-9+.-]*://", with: "", options: .regularExpression)
                .split(separator: "/").first.map(String.init)
        }

        guard var h = host?.lowercased(), !h.isEmpty else { return nil }

        // 포트·사용자정보·끝점 제거
        if let at = h.lastIndex(of: "@") { h = String(h[h.index(after: at)...]) }
        if !h.hasPrefix("["), let colon = h.firstIndex(of: ":") { h = String(h[..<colon]) }
        while h.hasSuffix(".") { h.removeLast() }
        if h.hasPrefix("www.") { h = String(h.dropFirst(4)) }

        guard !h.isEmpty, !h.contains(" ") else { return nil }
        return h
    }

    /// 저장해 둔 호스트가 지금 보고 있는 페이지 호스트를 담당하는지.
    ///
    /// - 정확히 같으면 통과: `example.com` ↔ `example.com`
    /// - 하위 도메인이면 통과: 저장 `example.com` ↔ 페이지 `login.example.com`
    /// - 그 밖에는 전부 거부. 특히 `example.com` 이 `example.com.evil.com` 을 절대
    ///   담당하지 않습니다(그쪽은 `.example.com` 으로 끝나지 않습니다).
    public static func hostMatches(stored: String, page: String) -> Bool {
        guard !stored.isEmpty, !page.isEmpty else { return false }
        if stored == page { return true }
        return page.hasSuffix("." + stored)
    }

    /// 페이지 주소에 쓸 수 있는 항목을 골라 줍니다.
    ///
    /// 로그인 종류이면서 아이디나 비밀번호가 있는 것만 내보냅니다.
    /// 더 구체적인 호스트를 저장해 둔 항목(`login.example.com`)이
    /// 뭉뚱그린 것(`example.com`)보다 앞에 옵니다.
    public static func candidates(for pageURL: String, in items: [VaultItem]) -> [VaultItem] {
        guard let page = normalizedHost(pageURL) else { return [] }

        var scored: [(item: VaultItem, score: Int)] = []
        for item in items {
            guard item.kind == .login else { continue }
            guard !item.password.isEmpty || !item.username.isEmpty else { continue }

            var best: Int?
            for raw in item.urls {
                guard let stored = normalizedHost(raw) else { continue }
                guard hostMatches(stored: stored, page: page) else { continue }
                // 저장된 호스트가 길수록(=구체적일수록) 우선.
                best = max(best ?? 0, stored.count)
            }
            if let score = best { scored.append((item, score)) }
        }

        return scored
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                return a.item.displayTitle.localizedCaseInsensitiveCompare(b.item.displayTitle) == .orderedAscending
            }
            .map(\.item)
    }

    /// 브라우저에서 방금 로그인한 것을 저장하려 할 때,
    /// **이미 있는 항목을 갱신해야 하는지** 판단합니다.
    ///
    /// 같은 사이트에 같은 아이디가 이미 있으면 새로 만들지 않고 그것을 고칩니다.
    /// 안 그러면 비밀번호를 바꿀 때마다 같은 사이트 항목이 계속 쌓입니다.
    public static func existingIndex(for pageURL: String,
                                     username: String,
                                     in items: [VaultItem]) -> Int? {
        guard let page = normalizedHost(pageURL) else { return nil }
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)

        var best: (index: Int, score: Int)?
        for (index, item) in items.enumerated() {
            guard item.kind == .login else { continue }
            // 아이디까지 같아야 "같은 계정"입니다. 대소문자는 무시합니다.
            guard item.username.compare(user, options: .caseInsensitive) == .orderedSame else { continue }

            for raw in item.urls {
                guard let stored = normalizedHost(raw), hostMatches(stored: stored, page: page) else { continue }
                if best == nil || stored.count > best!.score { best = (index, stored.count) }
            }
        }
        return best?.index
    }

    /// 브라우저에서 받은 로그인으로 새 항목을 만듭니다. 제목은 사이트 이름을 씁니다.
    public static func newItem(for pageURL: String, username: String, password: String) -> VaultItem {
        let host = normalizedHost(pageURL) ?? pageURL
        var item = VaultItem(kind: .login, title: host)
        item.username = username
        item.password = password
        item.urls = ["https://" + host]
        return item
    }
}
