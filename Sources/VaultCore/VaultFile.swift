import Foundation
import CryptoKit

/// 키 파생 설정. 파일에 그대로 적히고, 잠금 해제할 때 다시 읽습니다.
public struct KDFParameters: Codable, Equatable {
    public var algorithm: String
    public var iterations: Int
    public var salt: Data

    public static let pbkdf2SHA256 = "pbkdf2-hmac-sha256"

    public init(algorithm: String = KDFParameters.pbkdf2SHA256, iterations: Int, salt: Data) {
        self.algorithm = algorithm
        self.iterations = iterations
        self.salt = salt
    }
}

/// 파일 머리말. 이 값 전체가 GCM 의 추가 인증 데이터로 묶여 위조를 막습니다.
public struct VaultFileHeader: Codable, Equatable {
    public var format: String
    public var version: Int
    public var kdf: KDFParameters
    public var cipher: String

    public static let aesGCM = "aes-256-gcm"

    public init(format: String, version: Int, kdf: KDFParameters, cipher: String = VaultFileHeader.aesGCM) {
        self.format = format
        self.version = version
        self.kdf = kdf
        self.cipher = cipher
    }
}

/// 디스크에 실제로 저장되는 JSON 한 덩어리.
struct VaultFileEnvelope: Codable {
    var header: VaultFileHeader
    /// `nonce + 암호문 + 인증태그` 를 base64 로.
    var payload: Data
    var updatedAt: Date
}

/// 잠금이 풀린 금고 손잡이. 파생된 키를 들고 있으며 저장할 때 다시 씁니다.
///
/// 이 값이 사라지면(=앱이 잠기면) 메모리에서 키도 함께 사라집니다.
public struct UnlockedVault {
    public let url: URL
    public let header: VaultFileHeader
    let key: SymmetricKey

    /// 현재 키로 금고 내용을 다시 암호화해 저장합니다.
    public func save(_ document: VaultDocument) throws {
        try VaultFile.write(document: document, url: url, header: header, key: key)
    }

    /// 파일에서 내용을 다시 읽습니다.
    public func loadDocument() throws -> VaultDocument {
        let envelope = try VaultFile.readEnvelope(at: url)
        let aad = try VaultFile.additionalAuthenticatedData(for: envelope.header)
        let plaintext = try VaultCrypto.open(envelope.payload, using: key, authenticating: aad)
        return try VaultFile.jsonDecoder.decode(VaultDocument.self, from: plaintext)
    }
}

/// 금고 파일 읽기·쓰기.
public enum VaultFile {

    /// 파일 형식 식별자.
    public static let formatIdentifier = "password-vault"

    /// 이 앱이 다룰 수 있는 파일 형식 버전.
    public static let currentVersion = 1

    public static let fileExtension = "pvault"

    // MARK: - 기본 위치

    /// `~/Library/Application Support/PasswordVault`
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("PasswordVault", isDirectory: true)
    }

    /// `~/Library/Application Support/PasswordVault/vault.pvault`
    public static func defaultURL() -> URL {
        defaultDirectory().appendingPathComponent("vault").appendingPathExtension(fileExtension)
    }

    public static func exists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - 만들기 · 열기

    /// 새 금고를 만듭니다. 이미 파일이 있으면 실패합니다(덮어쓰기 사고 방지).
    @discardableResult
    public static func create(
        at url: URL,
        masterPassword: String,
        document: VaultDocument = VaultDocument(),
        iterations: Int? = nil
    ) throws -> UnlockedVault {
        guard !exists(at: url) else {
            throw VaultError.vaultAlreadyExists(path: url.path)
        }
        guard !masterPassword.isEmpty else {
            throw VaultError.invalidInput(reason: "마스터 비밀번호를 입력해 주세요.")
        }

        let salt = try VaultCrypto.bytes(VaultCrypto.saltLength)
        let rounds = max(iterations ?? VaultCrypto.defaultIterations, VaultCrypto.defaultIterations)
        let header = VaultFileHeader(
            format: formatIdentifier,
            version: currentVersion,
            kdf: KDFParameters(iterations: rounds, salt: salt)
        )
        let key = try VaultCrypto.deriveKey(masterPassword: masterPassword, salt: salt, iterations: rounds)

        try write(document: document, url: url, header: header, key: key)
        return UnlockedVault(url: url, header: header, key: key)
    }

    /// 기존 금고를 엽니다. 비밀번호가 틀리면 `wrongMasterPassword` 를 던집니다.
    public static func unlock(at url: URL, masterPassword: String) throws -> (vault: UnlockedVault, document: VaultDocument) {
        guard exists(at: url) else {
            throw VaultError.vaultNotFound(path: url.path)
        }

        let envelope = try readEnvelope(at: url)
        try validate(header: envelope.header)

        let key = try VaultCrypto.deriveKey(
            masterPassword: masterPassword,
            salt: envelope.header.kdf.salt,
            iterations: envelope.header.kdf.iterations
        )
        let aad = try additionalAuthenticatedData(for: envelope.header)
        let plaintext = try VaultCrypto.open(envelope.payload, using: key, authenticating: aad)

        let document: VaultDocument
        do {
            document = try jsonDecoder.decode(VaultDocument.self, from: plaintext)
        } catch {
            // 복호화는 됐는데 JSON 이 깨진 경우. 비밀번호 문제는 아닙니다.
            throw VaultError.fileDamaged(reason: "금고 내용을 해석하지 못했습니다.")
        }

        return (UnlockedVault(url: url, header: envelope.header, key: key), document)
    }

    /// 마스터 비밀번호를 바꿉니다. 솔트와 반복 횟수를 새로 뽑아 처음부터 다시 암호화합니다.
    public static func changeMasterPassword(
        vault: UnlockedVault,
        document: VaultDocument,
        newPassword: String,
        iterations: Int? = nil
    ) throws -> UnlockedVault {
        guard !newPassword.isEmpty else {
            throw VaultError.invalidInput(reason: "새 마스터 비밀번호를 입력해 주세요.")
        }

        let salt = try VaultCrypto.bytes(VaultCrypto.saltLength)
        let rounds = max(iterations ?? VaultCrypto.defaultIterations, VaultCrypto.defaultIterations)
        let header = VaultFileHeader(
            format: formatIdentifier,
            version: currentVersion,
            kdf: KDFParameters(iterations: rounds, salt: salt)
        )
        let key = try VaultCrypto.deriveKey(masterPassword: newPassword, salt: salt, iterations: rounds)

        try write(document: document, url: vault.url, header: header, key: key)
        return UnlockedVault(url: vault.url, header: header, key: key)
    }

    // MARK: - 내부

    static func validate(header: VaultFileHeader) throws {
        guard header.format == formatIdentifier else {
            throw VaultError.unsupportedFormat(found: header.format)
        }
        guard header.version <= currentVersion else {
            throw VaultError.unsupportedVersion(found: header.version, supported: currentVersion)
        }
        guard header.cipher == VaultFileHeader.aesGCM else {
            throw VaultError.unsupportedFormat(found: header.cipher)
        }
        guard header.kdf.algorithm == KDFParameters.pbkdf2SHA256 else {
            throw VaultError.unsupportedFormat(found: header.kdf.algorithm)
        }
        guard header.kdf.iterations >= VaultCrypto.minimumIterations else {
            throw VaultError.weakKDFParameters(
                iterations: header.kdf.iterations,
                minimum: VaultCrypto.minimumIterations
            )
        }
        guard header.kdf.salt.count >= 16 else {
            throw VaultError.fileDamaged(reason: "솔트가 너무 짧습니다.")
        }
    }

    /// 머리말을 결정적인 바이트열로 만들어 GCM 의 추가 인증 데이터로 씁니다.
    ///
    /// 키 정렬(`sortedKeys`)을 켜야 저장할 때와 읽을 때 같은 바이트가 나옵니다.
    static func additionalAuthenticatedData(for header: VaultFileHeader) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        do {
            return try encoder.encode(header)
        } catch {
            throw VaultError.fileDamaged(reason: "머리말을 인코딩하지 못했습니다.")
        }
    }

    static func readEnvelope(at url: URL) throws -> VaultFileEnvelope {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw VaultError.fileDamaged(reason: "파일을 읽지 못했습니다. (\(error.localizedDescription))")
        }
        do {
            return try jsonDecoder.decode(VaultFileEnvelope.self, from: data)
        } catch {
            throw VaultError.fileDamaged(reason: "JSON 구조가 올바르지 않습니다.")
        }
    }

    static func write(document: VaultDocument, url: URL, header: VaultFileHeader, key: SymmetricKey) throws {
        let plaintext = try jsonEncoder.encode(document)
        let aad = try additionalAuthenticatedData(for: header)
        let payload = try VaultCrypto.seal(plaintext, using: key, authenticating: aad)

        let envelope = VaultFileEnvelope(header: header, payload: payload, updatedAt: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let fileData = try encoder.encode(envelope)

        try atomicallyWrite(fileData, to: url)
    }

    /// 쓰다 말고 죽어도 기존 파일이 남도록 임시 파일에 쓴 뒤 바꿔 끼웁니다.
    ///
    /// 바꾸기 직전에 직전 내용을 `.bak` 으로 남겨 둡니다.
    /// 디스크가 가득 차거나 전원이 나가는 상황에서 금고를 통째로 잃지 않기 위한 보험입니다.
    static func atomicallyWrite(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()

        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        if fm.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("bak")
            if fm.fileExists(atPath: backup.path) {
                try? fm.removeItem(at: backup)
            }
            try? fm.copyItem(at: url, to: backup)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }

        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        // 소유자만 읽고 쓸 수 있게. 다른 사용자 계정이 금고 파일을 열어 보지 못하게 합니다.
        try data.write(to: temporary, options: [.atomic])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)

        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: temporary)
        } else {
            try fm.moveItem(at: temporary, to: url)
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: - 공용 JSON 설정

    static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
