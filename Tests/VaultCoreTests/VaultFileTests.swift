import XCTest
@testable import VaultCore

final class VaultFileTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vault-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var vaultURL: URL {
        directory.appendingPathComponent("vault.pvault")
    }

    // 테스트가 오래 걸리지 않도록 최소 허용치를 씁니다.
    private let testIterations = VaultCrypto.defaultIterations

    func testCreateAndUnlock() throws {
        let item = VaultItem(title: "은행", username: "hong", password: "s3cret!")
        _ = try VaultFile.create(
            at: vaultURL,
            masterPassword: "마스터-비밀번호",
            document: VaultDocument(items: [item]),
            iterations: testIterations
        )

        XCTAssertTrue(VaultFile.exists(at: vaultURL))

        let (_, document) = try VaultFile.unlock(at: vaultURL, masterPassword: "마스터-비밀번호")
        XCTAssertEqual(document.items.count, 1)
        XCTAssertEqual(document.items[0].title, "은행")
        XCTAssertEqual(document.items[0].password, "s3cret!")
    }

    func testCreateRefusesToOverwrite() throws {
        _ = try VaultFile.create(at: vaultURL, masterPassword: "하나", iterations: testIterations)

        XCTAssertThrowsError(try VaultFile.create(at: vaultURL, masterPassword: "둘", iterations: testIterations)) { error in
            guard case VaultError.vaultAlreadyExists = error else {
                return XCTFail("덮어쓰기를 막지 못했습니다: \(error)")
            }
        }
    }

    func testWrongPasswordThrows() throws {
        _ = try VaultFile.create(at: vaultURL, masterPassword: "정답", iterations: testIterations)

        XCTAssertThrowsError(try VaultFile.unlock(at: vaultURL, masterPassword: "오답")) { error in
            XCTAssertEqual(error as? VaultError, .wrongMasterPassword)
        }
    }

    func testEmptyMasterPasswordIsRejected() {
        XCTAssertThrowsError(try VaultFile.create(at: vaultURL, masterPassword: "", iterations: testIterations))
    }

    func testUnlockMissingFileThrows() {
        let missing = directory.appendingPathComponent("없는금고.pvault")
        XCTAssertThrowsError(try VaultFile.unlock(at: missing, masterPassword: "무엇이든")) { error in
            guard case VaultError.vaultNotFound = error else {
                return XCTFail("없는 파일을 다르게 처리했습니다: \(error)")
            }
        }
    }

    func testSaveThenReload() throws {
        let vault = try VaultFile.create(at: vaultURL, masterPassword: "마스터", iterations: testIterations)

        var document = VaultDocument()
        document.items.append(VaultItem(title: "첫 항목"))
        try vault.save(document)

        document.items.append(VaultItem(title: "둘째 항목"))
        try vault.save(document)

        let reloaded = try vault.loadDocument()
        XCTAssertEqual(reloaded.items.map(\.title), ["첫 항목", "둘째 항목"])
    }

    func testChangeMasterPassword() throws {
        let document = VaultDocument(items: [VaultItem(title: "메일")])
        let vault = try VaultFile.create(
            at: vaultURL,
            masterPassword: "예전",
            document: document,
            iterations: testIterations
        )

        _ = try VaultFile.changeMasterPassword(
            vault: vault,
            document: document,
            newPassword: "새것",
            iterations: testIterations
        )

        XCTAssertThrowsError(try VaultFile.unlock(at: vaultURL, masterPassword: "예전"))
        let (_, reloaded) = try VaultFile.unlock(at: vaultURL, masterPassword: "새것")
        XCTAssertEqual(reloaded.items.first?.title, "메일")
    }

    func testSaltAndPayloadChangeOnEverySave() throws {
        let vault = try VaultFile.create(at: vaultURL, masterPassword: "마스터", iterations: testIterations)
        let document = VaultDocument(items: [VaultItem(title: "고정된 내용")])

        try vault.save(document)
        let first = try Data(contentsOf: vaultURL)
        try vault.save(document)
        let second = try Data(contentsOf: vaultURL)

        // 같은 내용을 저장해도 논스가 달라지므로 암호문이 같으면 안 됩니다.
        XCTAssertNotEqual(first, second, "저장할 때마다 새 논스를 쓰지 않고 있습니다.")
    }

    func testTamperedPayloadIsRejected() throws {
        _ = try VaultFile.create(
            at: vaultURL,
            masterPassword: "마스터",
            document: VaultDocument(items: [VaultItem(title: "항목")]),
            iterations: testIterations
        )

        var envelope = try VaultFile.readEnvelope(at: vaultURL)
        var payload = [UInt8](envelope.payload)
        payload[payload.count - 1] ^= 0x01
        envelope.payload = Data(payload)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(envelope).write(to: vaultURL)

        XCTAssertThrowsError(try VaultFile.unlock(at: vaultURL, masterPassword: "마스터")) { error in
            XCTAssertEqual(error as? VaultError, .wrongMasterPassword)
        }
    }

    func testTamperedHeaderIsRejected() throws {
        _ = try VaultFile.create(at: vaultURL, masterPassword: "마스터", iterations: testIterations)

        var envelope = try VaultFile.readEnvelope(at: vaultURL)
        // 반복 횟수만 바꿔치기. 검증을 통과할 만큼 높게 두어도 AAD 불일치로 막혀야 합니다.
        envelope.header.kdf.iterations = VaultCrypto.defaultIterations + 1

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(envelope).write(to: vaultURL)

        XCTAssertThrowsError(try VaultFile.unlock(at: vaultURL, masterPassword: "마스터")) { error in
            XCTAssertEqual(error as? VaultError, .wrongMasterPassword)
        }
    }

    func testWeakIterationsAreRejected() throws {
        _ = try VaultFile.create(at: vaultURL, masterPassword: "마스터", iterations: testIterations)

        var envelope = try VaultFile.readEnvelope(at: vaultURL)
        envelope.header.kdf.iterations = 1_000

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(envelope).write(to: vaultURL)

        XCTAssertThrowsError(try VaultFile.unlock(at: vaultURL, masterPassword: "마스터")) { error in
            guard case VaultError.weakKDFParameters = error else {
                return XCTFail("낮은 반복 횟수를 거부하지 않았습니다: \(error)")
            }
        }
    }

    func testFutureVersionIsRejected() throws {
        _ = try VaultFile.create(at: vaultURL, masterPassword: "마스터", iterations: testIterations)

        var envelope = try VaultFile.readEnvelope(at: vaultURL)
        envelope.header.version = VaultFile.currentVersion + 1

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(envelope).write(to: vaultURL)

        XCTAssertThrowsError(try VaultFile.unlock(at: vaultURL, masterPassword: "마스터")) { error in
            guard case VaultError.unsupportedVersion = error else {
                return XCTFail("미래 버전을 거부하지 않았습니다: \(error)")
            }
        }
    }

    func testNoPlaintextOnDisk() throws {
        let secret = "아무도-몰라야-하는-값-9f3a"
        _ = try VaultFile.create(
            at: vaultURL,
            masterPassword: "마스터",
            document: VaultDocument(items: [VaultItem(title: "제목", password: secret)]),
            iterations: testIterations
        )

        let raw = try String(contentsOf: vaultURL, encoding: .utf8)
        XCTAssertFalse(raw.contains(secret))
        XCTAssertFalse(raw.contains("제목"))
    }

    func testFilePermissionsAreOwnerOnly() throws {
        _ = try VaultFile.create(at: vaultURL, masterPassword: "마스터", iterations: testIterations)

        let attributes = try FileManager.default.attributesOfItem(atPath: vaultURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(permissions & 0o077, 0, "다른 사용자가 금고 파일을 읽을 수 있습니다.")
    }

    func testBackupIsKeptOnOverwrite() throws {
        let vault = try VaultFile.create(at: vaultURL, masterPassword: "마스터", iterations: testIterations)
        try vault.save(VaultDocument(items: [VaultItem(title: "두 번째 저장")]))

        let backup = vaultURL.appendingPathExtension("bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path), "직전 파일 사본이 없습니다.")
    }
}
