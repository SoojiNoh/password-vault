import XCTest
@testable import VaultCore

final class VaultModelTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let item = VaultItem(
            kind: .card,
            title: "신용카드",
            username: "홍길동",
            password: "1234",
            urls: ["https://bank.example.com"],
            notes: "메모",
            totp: "JBSWY3DPEHPK3PXP",
            customFields: [CustomField(label: "CVC", value: "123", isSecret: true)],
            tags: ["금융", "개인"],
            isFavorite: true,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            passwordChangedAt: Date(timeIntervalSince1970: 1_700_000_050)
        )

        let data = try VaultFile.jsonEncoder.encode(item)
        let restored = try VaultFile.jsonDecoder.decode(VaultItem.self, from: data)
        XCTAssertEqual(restored, item)
    }

    /// 예전 버전이 쓴 파일(필드가 몇 개 없는)도 열려야 합니다.
    func testDecodingToleratesMissingFields() throws {
        let json = """
        { "id": "6B29FC40-CA47-1067-B31D-00DD010662DA", "title": "옛날 항목" }
        """
        let item = try VaultFile.jsonDecoder.decode(VaultItem.self, from: Data(json.utf8))

        XCTAssertEqual(item.title, "옛날 항목")
        XCTAssertEqual(item.kind, .login)
        XCTAssertEqual(item.username, "")
        XCTAssertEqual(item.urls, [])
        XCTAssertEqual(item.customFields, [])
        XCTAssertFalse(item.isFavorite)
        XCTAssertNil(item.totp)
    }

    /// 앞으로 새 종류가 생겨도 그 항목이 통째로 사라지면 안 됩니다.
    func testUnknownKindFallsBackToLogin() throws {
        let json = """
        { "title": "미래 항목", "kind": "cryptoWallet" }
        """
        let item = try VaultFile.jsonDecoder.decode(VaultItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.kind, .login)
        XCTAssertEqual(item.title, "미래 항목")
    }

    func testDocumentDecodingToleratesEmptyObject() throws {
        let document = try VaultFile.jsonDecoder.decode(VaultDocument.self, from: Data("{}".utf8))
        XCTAssertEqual(document.items, [])
        XCTAssertEqual(document.schemaVersion, VaultDocument.currentSchemaVersion)
    }

    func testDisplayTitleFallsBack() {
        XCTAssertEqual(VaultItem(title: "제목").displayTitle, "제목")
        XCTAssertEqual(VaultItem(title: "  ", username: "hong").displayTitle, "hong")
        XCTAssertEqual(VaultItem(urls: ["https://www.example.com/login"]).displayTitle, "example.com")
        XCTAssertEqual(VaultItem().displayTitle, "제목 없음")
    }

    func testURLNormalization() {
        XCTAssertEqual(VaultItem.normalizedURLString("example.com"), "https://example.com")
        XCTAssertEqual(VaultItem.normalizedURLString("https://example.com"), "https://example.com")
        XCTAssertEqual(VaultItem.normalizedURLString("http://example.com"), "http://example.com")
        XCTAssertEqual(VaultItem.normalizedURLString("  example.com  "), "https://example.com")
    }

    func testSearchMatching() {
        let item = VaultItem(
            title: "지메일",
            username: "hong@example.com",
            password: "매우-비밀스러운-값",
            urls: ["https://mail.google.com"],
            notes: "회사 계정",
            customFields: [CustomField(label: "복구코드", value: "AAA-BBB", isSecret: true)],
            tags: ["업무"]
        )

        XCTAssertTrue(item.matches(query: ""))
        XCTAssertTrue(item.matches(query: "지메일"))
        XCTAssertTrue(item.matches(query: "HONG"))
        XCTAssertTrue(item.matches(query: "google"))
        XCTAssertTrue(item.matches(query: "업무"))
        XCTAssertTrue(item.matches(query: "복구코드"), "비밀 필드의 이름으로는 찾을 수 있어야 합니다.")
        XCTAssertTrue(item.matches(query: "지메일 회사"), "여러 낱말은 모두 만족해야 합니다.")

        XCTAssertFalse(item.matches(query: "네이버"))
        XCTAssertFalse(item.matches(query: "지메일 없는낱말"))
        XCTAssertFalse(item.matches(query: "매우-비밀스러운-값"), "비밀번호 값은 검색되면 안 됩니다.")
        XCTAssertFalse(item.matches(query: "AAA-BBB"), "비밀 필드의 값은 검색되면 안 됩니다.")
    }

    func testAllTags() {
        let document = VaultDocument(items: [
            VaultItem(title: "가", tags: ["업무", "  "]),
            VaultItem(title: "나", tags: ["개인", "업무"]),
        ])
        XCTAssertEqual(document.allTags, ["개인", "업무"])
    }
}

final class CSVTests: XCTestCase {

    func testParsesQuotedFields() {
        let rows = CSV.parse("a,b,c\n1,\"둘, 셋\",\"넷\"\"다섯\"")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], ["a", "b", "c"])
        XCTAssertEqual(rows[1], ["1", "둘, 셋", "넷\"다섯"])
    }

    func testParsesNewlinesInsideQuotes() {
        let rows = CSV.parse("a,b\n1,\"첫 줄\n둘째 줄\"")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1][1], "첫 줄\n둘째 줄")
    }

    /// 스위프트에서 CRLF 는 한 글자로 묶입니다. `"\r"` 만 보면 윈도우 CSV 가 통째로 한 줄이 됩니다.
    func testHandlesCRLFAndBOM() {
        let rows = CSV.parse("\u{FEFF}a,b\r\n1,2\r\n")
        XCTAssertEqual(rows, [["a", "b"], ["1", "2"]])
    }

    func testHandlesLoneCarriageReturn() {
        XCTAssertEqual(CSV.parse("a,b\r1,2"), [["a", "b"], ["1", "2"]])
    }

    func testCRLFInsideQuotesBecomesNewline() {
        let rows = CSV.parse("a,b\r\n1,\"첫 줄\r\n둘째 줄\"\r\n")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1][1], "첫 줄\n둘째 줄", "따옴표 안의 CRLF 를 줄바꿈으로 살리지 못했습니다.")
    }

    /// 윈도우에서 내보낸 파일을 그대로 가져올 수 있어야 합니다.
    func testImportWindowsStyleExport() throws {
        let csv = "\u{FEFF}name,url,username,password,note\r\n지메일,https://mail.google.com,me@example.com,pw1,메모\r\n"
        let result = try VaultImporter.importCSV(csv)

        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].title, "지메일")
        XCTAssertEqual(result.items[0].password, "pw1")
        XCTAssertEqual(result.items[0].notes, "메모")
    }

    func testEncodeQuotesWhenNeeded() {
        XCTAssertEqual(CSV.encode([["보통", "쉼표,포함", "따옴표\"포함"]]), "보통,\"쉼표,포함\",\"따옴표\"\"포함\"")
        XCTAssertEqual(CSV.encode([["줄\n바꿈"]]), "\"줄\n바꿈\"")
    }

    func testEncodeParseRoundTrip() {
        let rows = [
            ["title", "password", "notes"],
            ["지메일", "a,b\"c", "여러\n줄"],
            ["빈 값", "", ""],
        ]
        XCTAssertEqual(CSV.parse(CSV.encode(rows)), rows)
    }

    func testImportChromeExport() throws {
        let csv = """
        name,url,username,password,note
        지메일,https://mail.google.com,me@example.com,pw1,메모
        네이버,https://naver.com,me2,pw2,
        """
        let result = try VaultImporter.importCSV(csv)

        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items[0].title, "지메일")
        XCTAssertEqual(result.items[0].username, "me@example.com")
        XCTAssertEqual(result.items[0].password, "pw1")
        XCTAssertEqual(result.items[0].urls, ["https://mail.google.com"])
        XCTAssertEqual(result.items[0].notes, "메모")
        XCTAssertEqual(result.columnMapping["제목"], "name")
        XCTAssertEqual(result.columnMapping["비밀번호"], "password")
    }

    func testImportBitwardenExport() throws {
        let csv = """
        folder,favorite,type,name,notes,fields,login_uri,login_username,login_password,login_totp
        ,,login,깃허브,,,https://github.com,hong,secret,JBSWY3DPEHPK3PXP
        """
        let result = try VaultImporter.importCSV(csv)

        XCTAssertEqual(result.items.count, 1)
        let item = result.items[0]
        XCTAssertEqual(item.title, "깃허브")
        XCTAssertEqual(item.username, "hong")
        XCTAssertEqual(item.password, "secret")
        XCTAssertEqual(item.urls, ["https://github.com"])
        XCTAssertEqual(item.totp, "JBSWY3DPEHPK3PXP")
        // 알아보지 못한 열(type)은 버리지 않고 사용자 지정 필드로 남깁니다.
        XCTAssertTrue(item.customFields.contains { $0.label == "type" && $0.value == "login" })
    }

    func testImportSkipsEmptyRows() throws {
        let csv = """
        title,username,password
        쓸모있음,hong,pw
        ,,
        """
        let result = try VaultImporter.importCSV(csv)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.skippedRows, 1)
    }

    func testImportRejectsUnrecognizedHeader() {
        let csv = """
        열하나,열둘,열셋
        가,나,다
        """
        XCTAssertThrowsError(try VaultImporter.importCSV(csv))
    }

    func testImportRequiresDataRows() {
        XCTAssertThrowsError(try VaultImporter.importCSV("title,username,password"))
        XCTAssertThrowsError(try VaultImporter.importCSV(""))
    }

    func testExportThenImportKeepsFields() throws {
        let items = [
            VaultItem(
                title: "지메일",
                username: "me@example.com",
                password: "따옴표\"와,쉼표",
                urls: ["https://mail.google.com"],
                notes: "여러\n줄 메모",
                totp: "JBSWY3DPEHPK3PXP",
                tags: ["업무"]
            )
        ]
        let csv = VaultExporter.csv(for: items)
        let result = try VaultImporter.importCSV(csv)

        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].title, "지메일")
        XCTAssertEqual(result.items[0].password, "따옴표\"와,쉼표")
        XCTAssertEqual(result.items[0].notes, "여러\n줄 메모")
        XCTAssertEqual(result.items[0].totp, "JBSWY3DPEHPK3PXP")
    }
}

final class SelfTestSuiteTests: XCTestCase {

    /// 배포 관문으로 쓰는 자체 검사가 실제로 통과하는지 여기서도 확인합니다.
    func testSelfTestPasses() {
        var lines: [String] = []
        let success = SelfTest.run { lines.append($0) }
        XCTAssertTrue(success, "자체 검사 실패:\n" + lines.joined(separator: "\n"))
    }
}
