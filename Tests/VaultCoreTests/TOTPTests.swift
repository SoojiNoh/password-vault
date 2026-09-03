import XCTest
@testable import VaultCore

final class Base32Tests: XCTestCase {

    func testKnownVectors() {
        // RFC 4648 부록의 시험값.
        XCTAssertEqual(Base32.encode(Data("".utf8)), "")
        XCTAssertEqual(Base32.encode(Data("f".utf8)), "MY======")
        XCTAssertEqual(Base32.encode(Data("fo".utf8)), "MZXQ====")
        XCTAssertEqual(Base32.encode(Data("foo".utf8)), "MZXW6===")
        XCTAssertEqual(Base32.encode(Data("foob".utf8)), "MZXW6YQ=")
        XCTAssertEqual(Base32.encode(Data("fooba".utf8)), "MZXW6YTB")
        XCTAssertEqual(Base32.encode(Data("foobar".utf8)), "MZXW6YTBOI======")

        XCTAssertEqual(Base32.decode("MY======"), Data("f".utf8))
        XCTAssertEqual(Base32.decode("MZXW6YTBOI======"), Data("foobar".utf8))
    }

    func testDecodeIsForgiving() {
        let expected = Data("foobar".utf8)
        XCTAssertEqual(Base32.decode("mzxw6ytboi"), expected, "소문자를 받아들이지 못했습니다.")
        XCTAssertEqual(Base32.decode("MZXW 6YTB OI"), expected, "공백을 무시하지 못했습니다.")
        XCTAssertEqual(Base32.decode("MZXW-6YTB-OI"), expected, "하이픈을 무시하지 못했습니다.")
        XCTAssertEqual(Base32.decode("MZXW6YTBOI"), expected, "패딩 없는 입력을 받지 못했습니다.")
    }

    func testDecodeRejectsInvalidCharacters() {
        XCTAssertNil(Base32.decode("MZXW6YTB0I"), "Base32 에 없는 '0' 을 통과시켰습니다.")
        XCTAssertNil(Base32.decode("한글"))
    }

    func testRoundTrip() throws {
        for length in 1...40 {
            let data = try SecureRandom.bytes(length)
            let encoded = Base32.encode(data)
            XCTAssertEqual(Base32.decode(encoded), data, "\(length)바이트 왕복에 실패했습니다.")
        }
    }
}

final class TOTPTests: XCTestCase {

    /// RFC 6238 부록 B (SHA-1, 8자리).
    private let sha1Secret = Data("12345678901234567890".utf8)

    func testRFC6238SHA1Vectors() {
        let totp = TOTP(secret: sha1Secret, digits: 8, period: 30, algorithm: .sha1)
        let vectors: [(TimeInterval, String)] = [
            (59, "94287082"),
            (1111111109, "07081804"),
            (1111111111, "14050471"),
            (1234567890, "89005924"),
            (2000000000, "69279037"),
            (20000000000, "65353130"),
        ]
        for (seconds, expected) in vectors {
            XCTAssertEqual(
                totp.code(at: Date(timeIntervalSince1970: seconds)),
                expected,
                "t=\(Int(seconds))"
            )
        }
    }

    func testRFC6238SHA256Vectors() {
        let secret = Data("12345678901234567890123456789012".utf8)
        let totp = TOTP(secret: secret, digits: 8, period: 30, algorithm: .sha256)
        XCTAssertEqual(totp.code(at: Date(timeIntervalSince1970: 59)), "46119246")
        XCTAssertEqual(totp.code(at: Date(timeIntervalSince1970: 1111111109)), "68084774")
    }

    func testRFC6238SHA512Vectors() {
        let secret = Data("1234567890123456789012345678901234567890123456789012345678901234".utf8)
        let totp = TOTP(secret: secret, digits: 8, period: 30, algorithm: .sha512)
        XCTAssertEqual(totp.code(at: Date(timeIntervalSince1970: 59)), "90693936")
        XCTAssertEqual(totp.code(at: Date(timeIntervalSince1970: 1111111109)), "25091201")
    }

    func testSixDigitCodeIsPadded() {
        let totp = TOTP(secret: sha1Secret, digits: 6, period: 30, algorithm: .sha1)
        for offset in stride(from: 0, to: 3_000, by: 37) {
            let code = totp.code(at: Date(timeIntervalSince1970: TimeInterval(offset)))
            XCTAssertEqual(code.count, 6)
            XCTAssertTrue(code.allSatisfy { $0.isNumber })
        }
    }

    func testCodeChangesEachPeriod() {
        let totp = TOTP(secret: sha1Secret)
        let first = totp.code(at: Date(timeIntervalSince1970: 0))
        let sameWindow = totp.code(at: Date(timeIntervalSince1970: 29))
        let nextWindow = totp.code(at: Date(timeIntervalSince1970: 30))

        XCTAssertEqual(first, sameWindow, "같은 30초 구간인데 코드가 달라졌습니다.")
        XCTAssertNotEqual(first, nextWindow, "구간이 넘어갔는데 코드가 그대로입니다.")
    }

    func testSecondsRemaining() {
        let totp = TOTP(secret: sha1Secret, period: 30)
        XCTAssertEqual(totp.secondsRemaining(at: Date(timeIntervalSince1970: 0)), 30)
        XCTAssertEqual(totp.secondsRemaining(at: Date(timeIntervalSince1970: 10)), 20)
        XCTAssertEqual(totp.secondsRemaining(at: Date(timeIntervalSince1970: 29)), 1)
    }

    func testParseBareBase32Secret() {
        let totp = TOTP.parse("JBSWY3DPEHPK3PXP")
        XCTAssertNotNil(totp)
        XCTAssertEqual(totp?.digits, 6)
        XCTAssertEqual(totp?.period, 30)
        XCTAssertEqual(totp?.algorithm, .sha1)
    }

    func testParseOTPAuthURI() {
        let uri = "otpauth://totp/GitHub:hong%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&algorithm=SHA256&digits=8&period=60"
        guard let totp = TOTP.parse(uri) else {
            return XCTFail("URI 를 해석하지 못했습니다.")
        }
        XCTAssertEqual(totp.issuer, "GitHub")
        XCTAssertEqual(totp.account, "hong@example.com")
        XCTAssertEqual(totp.algorithm, .sha256)
        XCTAssertEqual(totp.digits, 8)
        XCTAssertEqual(totp.period, 60)
    }

    func testParseURIWithoutIssuerParameter() {
        let totp = TOTP.parse("otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP")
        XCTAssertEqual(totp?.issuer, "Example")
        XCTAssertEqual(totp?.account, "alice")
    }

    func testParseRejectsGarbage() {
        XCTAssertNil(TOTP.parse(""))
        XCTAssertNil(TOTP.parse("   "))
        XCTAssertNil(TOTP.parse("otpauth://hotp/Example?secret=JBSWY3DPEHPK3PXP"), "hotp 는 지원하지 않습니다.")
        XCTAssertNil(TOTP.parse("otpauth://totp/Example?issuer=Example"), "secret 없는 URI 를 통과시켰습니다.")
        XCTAssertNil(TOTP.parse("!!!!"))
    }
}
