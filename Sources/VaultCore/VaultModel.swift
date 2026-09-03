import Foundation

/// 항목 종류. 1Password 의 "로그인 / 보안 메모 / 카드" 에 해당합니다.
public enum ItemKind: String, Codable, CaseIterable, Equatable {
    case login
    case secureNote
    case card

    public var displayName: String {
        switch self {
        case .login: return "로그인"
        case .secureNote: return "보안 메모"
        case .card: return "카드"
        }
    }

    /// SF Symbols 이름.
    public var symbolName: String {
        switch self {
        case .login: return "person.badge.key"
        case .secureNote: return "note.text"
        case .card: return "creditcard"
        }
    }
}

/// 사용자가 직접 추가하는 항목 안의 한 줄.
public struct CustomField: Codable, Equatable, Identifiable {
    public var id: UUID
    public var label: String
    public var value: String
    /// 참이면 화면에서 가려 두고, "보기" 를 눌러야 드러납니다.
    public var isSecret: Bool

    public init(id: UUID = UUID(), label: String, value: String, isSecret: Bool = false) {
        self.id = id
        self.label = label
        self.value = value
        self.isSecret = isSecret
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, value, isSecret
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        isSecret = try c.decodeIfPresent(Bool.self, forKey: .isSecret) ?? false
    }
}

/// 금고에 저장되는 항목 하나.
///
/// 파일 형식이 오래 살아남아야 하므로 디코딩은 관대하게 합니다.
/// 새 필드를 나중에 추가해도 예전 파일이 그대로 열리고,
/// 예전 앱이 모르는 필드를 만나도 그 항목만 통째로 날아가지 않습니다.
public struct VaultItem: Codable, Equatable, Identifiable {
    public var id: UUID
    public var kind: ItemKind
    public var title: String
    public var username: String
    public var password: String
    public var urls: [String]
    public var notes: String
    /// `otpauth://...` 전체 URI 또는 Base32 시크릿 문자열.
    public var totp: String?
    public var customFields: [CustomField]
    public var tags: [String]
    public var isFavorite: Bool
    public var createdAt: Date
    public var updatedAt: Date
    /// 비밀번호를 마지막으로 바꾼 시각. "오래된 비밀번호" 표시에 씁니다.
    public var passwordChangedAt: Date?

    public init(
        id: UUID = UUID(),
        kind: ItemKind = .login,
        title: String = "",
        username: String = "",
        password: String = "",
        urls: [String] = [],
        notes: String = "",
        totp: String? = nil,
        customFields: [CustomField] = [],
        tags: [String] = [],
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        passwordChangedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.username = username
        self.password = password
        self.urls = urls
        self.notes = notes
        self.totp = totp
        self.customFields = customFields
        self.tags = tags
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.passwordChangedAt = passwordChangedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, username, password, urls, notes, totp
        case customFields, tags, isFavorite, createdAt, updatedAt, passwordChangedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        // 모르는 종류 문자열이 들어 있어도 항목을 버리지 않고 로그인으로 취급합니다.
        kind = (try? c.decode(ItemKind.self, forKey: .kind)) ?? .login
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try c.decodeIfPresent(String.self, forKey: .password) ?? ""
        urls = try c.decodeIfPresent([String].self, forKey: .urls) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        totp = try c.decodeIfPresent(String.self, forKey: .totp)
        customFields = try c.decodeIfPresent([CustomField].self, forKey: .customFields) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        let now = Date()
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        passwordChangedAt = try c.decodeIfPresent(Date.self, forKey: .passwordChangedAt)
    }

    // MARK: - 화면 표시용

    /// 목록에 굵게 보여줄 이름. 비어 있으면 대신 쓸 만한 값을 찾아 줍니다.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if !username.isEmpty { return username }
        if let host = primaryHost { return host }
        return "제목 없음"
    }

    /// 목록에 흐리게 보여줄 두 번째 줄.
    public var displaySubtitle: String {
        if !username.isEmpty { return username }
        if let host = primaryHost { return host }
        switch kind {
        case .secureNote:
            return notes.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n").first.map(String.init) ?? ""
        case .card, .login:
            return ""
        }
    }

    public var primaryURL: String? {
        urls.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// `https://` 같은 접두어를 뗀 도메인. 목록에서 읽기 좋게 쓰려는 용도입니다.
    public var primaryHost: String? {
        guard let raw = primaryURL else { return nil }
        let normalized = VaultItem.normalizedURLString(raw)
        guard let host = URL(string: normalized)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// 사용자가 `example.com` 처럼 적어도 열 수 있게 스킴을 채워 줍니다.
    public static func normalizedURLString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.contains("://") { return trimmed }
        return "https://" + trimmed
    }

    /// 검색어와 맞는지 봅니다. 공백으로 나눈 모든 조각이 어딘가에 들어 있어야 합니다.
    ///
    /// 비밀번호 값 자체는 검색 대상에서 뺍니다. 검색창에 우연히 남은 문자열로
    /// 비밀번호를 역추적할 수 있게 만들 이유가 없습니다.
    public func matches(query: String) -> Bool {
        let terms = query
            .lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
        guard !terms.isEmpty else { return true }

        var haystack = [title, username, notes]
        haystack.append(contentsOf: urls)
        haystack.append(contentsOf: tags)
        haystack.append(contentsOf: customFields.filter { !$0.isSecret }.map { $0.label + " " + $0.value })
        haystack.append(contentsOf: customFields.filter { $0.isSecret }.map { $0.label })
        haystack.append(kind.displayName)
        let joined = haystack.joined(separator: "\n").lowercased()

        return terms.allSatisfy { joined.contains($0) }
    }
}

/// 암호화된 덩어리 안에 들어가는 실제 내용.
public struct VaultDocument: Codable, Equatable {
    /// 내용물 스키마 버전. 파일 형식 버전(`VaultFile.currentVersion`) 과는 별개입니다.
    public var schemaVersion: Int
    public var items: [VaultItem]

    public static let currentSchemaVersion = 1

    public init(items: [VaultItem] = [], schemaVersion: Int = VaultDocument.currentSchemaVersion) {
        self.schemaVersion = schemaVersion
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, items
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? VaultDocument.currentSchemaVersion
        items = try c.decodeIfPresent([VaultItem].self, forKey: .items) ?? []
    }

    /// 모든 항목에서 쓰인 태그를 정렬해 돌려줍니다.
    public var allTags: [String] {
        var seen = Set<String>()
        for item in items {
            for tag in item.tags {
                let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { seen.insert(trimmed) }
            }
        }
        return seen.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
