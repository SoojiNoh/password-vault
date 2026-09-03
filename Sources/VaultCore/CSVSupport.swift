import Foundation

/// RFC 4180 형태의 CSV 읽기·쓰기.
///
/// 크롬·사파리·1Password·Bitwarden 이 내보내는 CSV 를 그대로 받아들이는 것이 목적입니다.
public enum CSV {

    /// CSV 텍스트를 행·열로 나눕니다. 따옴표 안의 쉼표와 줄바꿈을 제대로 처리합니다.
    public static func parse(_ text: String) -> [[String]] {
        var source = text
        // 엑셀이 붙이는 BOM 제거.
        if source.hasPrefix("\u{FEFF}") { source.removeFirst() }

        let characters = Array(source)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = 0

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            rows.append(row)
            row = []
        }

        while index < characters.count {
            let character = characters[index]

            if inQuotes {
                if character == "\"" {
                    // `""` 는 따옴표 한 글자를 뜻합니다.
                    if index + 1 < characters.count && characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes = false
                    index += 1
                    continue
                }
                // 따옴표 안의 줄바꿈은 살리되 형태는 \n 으로 통일합니다.
                field.append(isLineBreak(character) ? "\n" : character)
                index += 1
                continue
            }

            switch character {
            case "\"":
                inQuotes = true
                index += 1
            case ",":
                endField()
                index += 1
            // 스위프트에서 CRLF 는 **한 글자**(하나의 grapheme cluster)로 묶입니다.
            // "\r" 과 "\n" 만 따로 보면 윈도우·엑셀이 만든 CSV 가 통째로 한 줄이 되어 버립니다.
            case "\r\n", "\r", "\n":
                endRow()
                index += 1
            default:
                field.append(character)
                index += 1
            }
        }

        if !field.isEmpty || !row.isEmpty {
            endRow()
        }

        // 빈 줄 제거.
        return rows.filter { !($0.count == 1 && $0[0].trimmingCharacters(in: .whitespaces).isEmpty) }
    }

    /// 행·열을 CSV 텍스트로 만듭니다.
    public static func encode(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map(escape).joined(separator: ",")
        }
        .joined(separator: "\n")
    }

    static func escape(_ field: String) -> String {
        let needsQuoting = field.contains(",")
            || field.contains("\"")
            || field.contains(where: isLineBreak)
            || field.hasPrefix(" ")
            || field.hasSuffix(" ")
        guard needsQuoting else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// 줄바꿈 한 글자인지. CRLF 도 스위프트에서는 한 글자라 함께 봐야 합니다.
    static func isLineBreak(_ character: Character) -> Bool {
        character == "\r\n" || character == "\r" || character == "\n"
    }
}

/// CSV 가져오기 결과.
public struct CSVImportResult: Equatable {
    public var items: [VaultItem]
    /// 제목·아이디·비밀번호가 모두 비어 건너뛴 줄 수.
    public var skippedRows: Int
    /// 어떤 열을 무엇으로 해석했는지. 사용자에게 그대로 보여 주기 위한 값입니다.
    public var columnMapping: [String: String]

    public init(items: [VaultItem], skippedRows: Int, columnMapping: [String: String]) {
        self.items = items
        self.skippedRows = skippedRows
        self.columnMapping = columnMapping
    }
}

/// 다른 비밀번호 관리자에서 내보낸 CSV 를 항목으로 바꿉니다.
public enum VaultImporter {

    /// 열 이름 후보. 앞에 있을수록 우선합니다.
    static let titleKeys = ["name", "title", "account", "item", "display name", "이름", "제목"]
    static let usernameKeys = ["username", "user name", "login_username", "login", "user", "email", "e-mail", "userid", "아이디", "사용자"]
    static let passwordKeys = ["password", "login_password", "pass", "pwd", "비밀번호", "암호"]
    static let urlKeys = ["url", "urls", "website", "web site", "login_uri", "uri", "site", "링크", "주소"]
    static let notesKeys = ["notes", "note", "comment", "comments", "extra", "메모", "비고"]
    static let totpKeys = ["totp", "otpauth", "otp", "login_totp", "two factor", "2fa", "verification code"]

    public static func importCSV(_ text: String) throws -> CSVImportResult {
        let rows = CSV.parse(text)
        guard let header = rows.first, rows.count > 1 else {
            throw VaultError.invalidInput(reason: "CSV 에 머리글 줄과 데이터가 모두 있어야 합니다.")
        }

        let normalizedHeader = header.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        let titleIndex = firstIndex(in: normalizedHeader, matching: titleKeys)
        let usernameIndex = firstIndex(in: normalizedHeader, matching: usernameKeys)
        let passwordIndex = firstIndex(in: normalizedHeader, matching: passwordKeys)
        let urlIndex = firstIndex(in: normalizedHeader, matching: urlKeys)
        let notesIndex = firstIndex(in: normalizedHeader, matching: notesKeys)
        let totpIndex = firstIndex(in: normalizedHeader, matching: totpKeys)

        guard titleIndex != nil || usernameIndex != nil || passwordIndex != nil else {
            throw VaultError.invalidInput(
                reason: "이 CSV 에서 제목·아이디·비밀번호 열을 찾지 못했습니다. 머리글 줄이 있는지 확인해 주세요."
            )
        }

        var mapping: [String: String] = [:]
        func record(_ role: String, _ index: Int?) {
            if let index = index, index < header.count { mapping[role] = header[index] }
        }
        record("제목", titleIndex)
        record("아이디", usernameIndex)
        record("비밀번호", passwordIndex)
        record("주소", urlIndex)
        record("메모", notesIndex)
        record("OTP", totpIndex)

        // 알아보지 못한 열은 버리지 않고 사용자 지정 필드로 옮깁니다.
        let recognized = Set([titleIndex, usernameIndex, passwordIndex, urlIndex, notesIndex, totpIndex].compactMap { $0 })

        var items: [VaultItem] = []
        var skipped = 0

        for row in rows.dropFirst() {
            func value(_ index: Int?) -> String {
                guard let index = index, index >= 0, index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let title = value(titleIndex)
            let username = value(usernameIndex)
            let password = value(passwordIndex)
            let url = value(urlIndex)
            let notes = value(notesIndex)
            let totp = value(totpIndex)

            if title.isEmpty && username.isEmpty && password.isEmpty && notes.isEmpty {
                skipped += 1
                continue
            }

            var extras: [CustomField] = []
            for (index, cell) in row.enumerated() where !recognized.contains(index) {
                let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, index < header.count else { continue }
                let label = header[index].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !label.isEmpty else { continue }
                extras.append(CustomField(label: label, value: trimmed, isSecret: false))
            }

            let kind: ItemKind = password.isEmpty && username.isEmpty ? .secureNote : .login

            items.append(
                VaultItem(
                    kind: kind,
                    title: title.isEmpty ? (username.isEmpty ? "가져온 항목" : username) : title,
                    username: username,
                    password: password,
                    urls: url.isEmpty ? [] : [url],
                    notes: notes,
                    totp: totp.isEmpty ? nil : totp,
                    customFields: extras,
                    passwordChangedAt: password.isEmpty ? nil : Date()
                )
            )
        }

        return CSVImportResult(items: items, skippedRows: skipped, columnMapping: mapping)
    }

    static func firstIndex(in header: [String], matching keys: [String]) -> Int? {
        // 정확히 일치하는 열을 먼저 찾고, 없으면 포함하는 열을 찾습니다.
        for key in keys {
            if let index = header.firstIndex(of: key) { return index }
        }
        for key in keys {
            if let index = header.firstIndex(where: { $0.contains(key) }) { return index }
        }
        return nil
    }
}

/// 항목을 평문 CSV 로 내보냅니다.
///
/// 평문이라 위험합니다. 호출하는 쪽에서 반드시 경고를 보여 주세요.
public enum VaultExporter {

    public static let header = ["title", "username", "password", "url", "notes", "totp", "tags", "kind"]

    public static func csv(for items: [VaultItem]) -> String {
        var rows: [[String]] = [header]
        for item in items {
            rows.append([
                item.title,
                item.username,
                item.password,
                item.urls.joined(separator: " "),
                item.notes,
                item.totp ?? "",
                item.tags.joined(separator: ","),
                item.kind.rawValue,
            ])
        }
        return CSV.encode(rows) + "\n"
    }
}
