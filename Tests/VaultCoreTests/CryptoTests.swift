import XCTest
@testable import VaultCore

final class CryptoTests: XCTestCase {

    private let iterations = 120_000  // 시험용. 실제 금고는 60만 회 이상을 씁니다.

    func testDerivedKeyLength() throws {
        let salt = try SecureRandom.bytes(32)
        let key = try VaultCrypto.deriveKey(masterPassword: "비밀번호", salt: salt, iterations: iterations)
        XCTAssertEqual(VaultCrypto.rawBytes(of: key).count, VaultCrypto.keyLength)
    }

    func testSameInputsGiveSameKey() throws {
        let salt = try SecureRandom.bytes(32)
        let first = try VaultCrypto.deriveKey(masterPassword: "같은 비밀번호", salt: salt, iterations: iterations)
        let second = try VaultCrypto.deriveKey(masterPassword: "같은 비밀번호", salt: salt, iterations: iterations)
        XCTAssertEqual(VaultCrypto.rawBytes(of: first), VaultCrypto.rawBytes(of: second))
    }

    func testDifferentSaltGivesDifferentKey() throws {
        let first = try VaultCrypto.deriveKey(
            masterPassword: "비밀번호",
            salt: try SecureRandom.bytes(32),
            iterations: iterations
        )
        let second = try VaultCrypto.deriveKey(
            masterPassword: "비밀번호",
            salt: try SecureRandom.bytes(32),
            iterations: iterations
        )
        XCTAssertNotEqual(VaultCrypto.rawBytes(of: first), VaultCrypto.rawBytes(of: second))
    }

    func testDifferentIterationsGiveDifferentKey() throws {
        let salt = try SecureRandom.bytes(32)
        let first = try VaultCrypto.deriveKey(masterPassword: "비밀번호", salt: salt, iterations: iterations)
        let second = try VaultCrypto.deriveKey(masterPassword: "비밀번호", salt: salt, iterations: iterations + 1)
        XCTAssertNotEqual(VaultCrypto.rawBytes(of: first), VaultCrypto.rawBytes(of: second))
    }

    func testKnownPBKDF2Vector() throws {
        // RFC 6070 스타일 시험값(HMAC-SHA256).
        // password="password", salt="salt", c=1, dkLen=32
        let key = try VaultCrypto.deriveKey(
            masterPassword: "password",
            salt: Data("salt".utf8),
            iterations: 1
        )
        let expected = "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"
        XCTAssertEqual(VaultCrypto.rawBytes(of: key).map { String(format: "%02x", $0) }.joined(), expected)
    }

    func testEmptySaltIsRejected() {
        XCTAssertThrowsError(try VaultCrypto.deriveKey(masterPassword: "비밀번호", salt: Data(), iterations: 1000))
    }

    func testZeroIterationsIsRejected() throws {
        let salt = try SecureRandom.bytes(32)
        XCTAssertThrowsError(try VaultCrypto.deriveKey(masterPassword: "비밀번호", salt: salt, iterations: 0))
    }

    func testSealAndOpen() throws {
        let salt = try SecureRandom.bytes(32)
        let key = try VaultCrypto.deriveKey(masterPassword: "열쇠", salt: salt, iterations: iterations)
        let message = Data("비밀 메시지 secret 🔐".utf8)
        let aad = Data("머리말".utf8)

        let sealed = try VaultCrypto.seal(message, using: key, authenticating: aad)
        XCTAssertNotEqual(sealed, message)
        XCTAssertEqual(try VaultCrypto.open(sealed, using: key, authenticating: aad), message)
    }

    func testSealUsesFreshNonce() throws {
        let salt = try SecureRandom.bytes(32)
        let key = try VaultCrypto.deriveKey(masterPassword: "열쇠", salt: salt, iterations: iterations)
        let message = Data("같은 내용".utf8)

        let first = try VaultCrypto.seal(message, using: key, authenticating: Data())
        let second = try VaultCrypto.seal(message, using: key, authenticating: Data())
        XCTAssertNotEqual(first, second, "같은 평문·같은 키인데 암호문이 같습니다. 논스를 재사용하고 있습니다.")
    }

    func testWrongKeyFails() throws {
        let salt = try SecureRandom.bytes(32)
        let key = try VaultCrypto.deriveKey(masterPassword: "열쇠", salt: salt, iterations: iterations)
        let other = try VaultCrypto.deriveKey(masterPassword: "다른열쇠", salt: salt, iterations: iterations)

        let sealed = try VaultCrypto.seal(Data("내용".utf8), using: key, authenticating: Data())
        XCTAssertThrowsError(try VaultCrypto.open(sealed, using: other, authenticating: Data())) { error in
            XCTAssertEqual(error as? VaultError, .wrongMasterPassword)
        }
    }

    func testChangedAADFails() throws {
        let salt = try SecureRandom.bytes(32)
        let key = try VaultCrypto.deriveKey(masterPassword: "열쇠", salt: salt, iterations: iterations)

        let sealed = try VaultCrypto.seal(Data("내용".utf8), using: key, authenticating: Data("머리말 A".utf8))
        XCTAssertThrowsError(try VaultCrypto.open(sealed, using: key, authenticating: Data("머리말 B".utf8)))
    }

    func testTruncatedCiphertextFails() throws {
        let salt = try SecureRandom.bytes(32)
        let key = try VaultCrypto.deriveKey(masterPassword: "열쇠", salt: salt, iterations: iterations)

        let sealed = try VaultCrypto.seal(Data("내용".utf8), using: key, authenticating: Data())
        let truncated = sealed.prefix(sealed.count - 1)
        XCTAssertThrowsError(try VaultCrypto.open(Data(truncated), using: key, authenticating: Data()))
    }

    func testCalibratedIterationsStayInSafeRange() {
        let value = VaultCrypto.calibratedIterations(targetSeconds: 0.05)
        XCTAssertGreaterThanOrEqual(value, VaultCrypto.defaultIterations)
        XCTAssertLessThanOrEqual(value, VaultCrypto.maximumIterations)
    }
}
