import XCTest
@testable import VaultCore

/// 자동완성 짝짓기 시험.
///
/// 여기가 뚫리면 가짜 사이트에 진짜 비밀번호가 넘어갑니다.
/// 그래서 "되는 경우"보다 **"되면 안 되는 경우"**를 더 많이 적어 둡니다.
final class AutofillMatchTests: XCTestCase {

    // MARK: - 호스트 정규화

    func testNormalizedHostStripsSchemePathAndWWW() {
        XCTAssertEqual(AutofillMatch.normalizedHost("https://www.Example.com/login?a=1"), "example.com")
        XCTAssertEqual(AutofillMatch.normalizedHost("example.com"), "example.com")
        XCTAssertEqual(AutofillMatch.normalizedHost("http://EXAMPLE.com"), "example.com")
        XCTAssertEqual(AutofillMatch.normalizedHost("example.com/some/path"), "example.com")
    }

    func testNormalizedHostStripsPortAndUserInfoAndTrailingDot() {
        XCTAssertEqual(AutofillMatch.normalizedHost("https://example.com:8443/x"), "example.com")
        XCTAssertEqual(AutofillMatch.normalizedHost("https://user:pw@example.com/x"), "example.com")
        XCTAssertEqual(AutofillMatch.normalizedHost("https://example.com./x"), "example.com")
    }

    func testNormalizedHostRejectsJunk() {
        XCTAssertNil(AutofillMatch.normalizedHost(""))
        XCTAssertNil(AutofillMatch.normalizedHost("   "))
    }

    // MARK: - 통과해야 하는 것

    func testExactAndSubdomainMatch() {
        XCTAssertTrue(AutofillMatch.hostMatches(stored: "example.com", page: "example.com"))
        XCTAssertTrue(AutofillMatch.hostMatches(stored: "example.com", page: "login.example.com"))
        XCTAssertTrue(AutofillMatch.hostMatches(stored: "example.com", page: "a.b.example.com"))
    }

    // MARK: - 반드시 막아야 하는 것

    func testDoesNotMatchLookalikeDomains() {
        // 가장 흔한 수법: 진짜 도메인을 앞에 붙인 남의 도메인
        XCTAssertFalse(AutofillMatch.hostMatches(stored: "example.com", page: "example.com.evil.com"))
        XCTAssertFalse(AutofillMatch.hostMatches(stored: "github.com", page: "github.com.attacker.net"))
        // 점 없이 이어 붙인 것
        XCTAssertFalse(AutofillMatch.hostMatches(stored: "example.com", page: "notexample.com"))
        XCTAssertFalse(AutofillMatch.hostMatches(stored: "example.com", page: "evil-example.com"))
        // 반대 방향(더 넓은 쪽으로는 새지 않는다)
        XCTAssertFalse(AutofillMatch.hostMatches(stored: "login.example.com", page: "example.com"))
        // 전혀 다른 곳
        XCTAssertFalse(AutofillMatch.hostMatches(stored: "example.com", page: "example.org"))
        XCTAssertFalse(AutofillMatch.hostMatches(stored: "", page: "example.com"))
    }

    // MARK: - 항목 고르기

    private func login(_ title: String, user: String, pass: String, urls: [String]) -> VaultItem {
        var item = VaultItem(kind: .login, title: title)
        item.username = user
        item.password = pass
        item.urls = urls
        return item
    }

    func testCandidatesOnlyReturnsMatchingLogins() {
        let items = [
            login("깃허브", user: "me", pass: "pw1", urls: ["https://github.com"]),
            login("예제", user: "u", pass: "pw2", urls: ["https://example.com"]),
            login("가짜", user: "u", pass: "pw3", urls: ["https://github.com.evil.com"]),
        ]
        let got = AutofillMatch.candidates(for: "https://github.com/login", in: items)
        XCTAssertEqual(got.map(\.title), ["깃허브"])
    }

    func testCandidatesMatchSubdomainOfStoredHost() {
        let items = [login("예제", user: "u", pass: "p", urls: ["example.com"])]
        XCTAssertEqual(AutofillMatch.candidates(for: "https://login.example.com/", in: items).count, 1)
    }

    func testCandidatesNeverLeakToLookalikeSite() {
        let items = [login("깃허브", user: "me", pass: "secret", urls: ["https://github.com"])]
        XCTAssertTrue(AutofillMatch.candidates(for: "https://github.com.evil.com/login", in: items).isEmpty)
        XCTAssertTrue(AutofillMatch.candidates(for: "https://notgithub.com/login", in: items).isEmpty)
    }

    func testCandidatesSkipNonLoginKindsAndEmptyItems() {
        var note = VaultItem(kind: .secureNote, title: "메모")
        note.urls = ["https://example.com"]
        var empty = VaultItem(kind: .login, title: "빈 항목")
        empty.urls = ["https://example.com"]
        XCTAssertTrue(AutofillMatch.candidates(for: "https://example.com", in: [note, empty]).isEmpty)
    }

    func testMoreSpecificHostComesFirst() {
        let items = [
            login("두루뭉술", user: "a", pass: "p", urls: ["example.com"]),
            login("콕집은", user: "b", pass: "p", urls: ["login.example.com"]),
        ]
        let got = AutofillMatch.candidates(for: "https://login.example.com/", in: items)
        XCTAssertEqual(got.map(\.title), ["콕집은", "두루뭉술"])
    }

    func testUnparseablePageURLYieldsNothing() {
        let items = [login("예제", user: "u", pass: "p", urls: ["example.com"])]
        XCTAssertTrue(AutofillMatch.candidates(for: "", in: items).isEmpty)
    }
}
