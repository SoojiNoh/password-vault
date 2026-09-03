import Foundation
import CryptoKit
import CommonCrypto

/// 금고 암호화의 밑바탕.
///
/// 설계 요약
/// - 마스터 비밀번호 → PBKDF2-HMAC-SHA256 (임의 솔트 32바이트, 기본 60만 회) → 256비트 키
/// - 금고 내용 → AES-256-GCM 으로 암호화. 인증 태그가 붙어 있어 한 바이트라도 바뀌면 복호화가 실패합니다.
/// - 파일 머리말(형식·버전·반복 횟수·솔트)을 GCM 의 추가 인증 데이터(AAD)로 묶습니다.
///   그래서 공격자가 "반복 횟수 1회" 같은 값으로 머리말만 바꿔치기 할 수 없습니다.
public enum VaultCrypto {

    /// 파생 키 길이(바이트). AES-256 이므로 32.
    public static let keyLength = 32

    /// 솔트 길이(바이트).
    public static let saltLength = 32

    /// 새 금고를 만들 때의 기본 반복 횟수.
    /// OWASP 의 PBKDF2-HMAC-SHA256 권고치(2023) 이상입니다.
    public static let defaultIterations = 600_000

    /// 파일에서 읽어들일 때 허용하는 최소 반복 횟수.
    /// 이보다 낮으면 손댄 파일로 보고 거부합니다.
    public static let minimumIterations = 200_000

    /// 보정으로 올릴 수 있는 상한. 너무 커지면 잠금 해제가 답답해집니다.
    public static let maximumIterations = 4_000_000

    // MARK: - 키 파생

    /// 마스터 비밀번호와 솔트로 대칭키를 만듭니다.
    public static func deriveKey(masterPassword: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        guard iterations > 0 else {
            throw VaultError.invalidInput(reason: "반복 횟수는 1 이상이어야 합니다.")
        }
        guard !salt.isEmpty else {
            throw VaultError.invalidInput(reason: "솔트가 비어 있습니다.")
        }

        let passwordLength = masterPassword.utf8.count
        let saltBytes = [UInt8](salt)
        var derived = [UInt8](repeating: 0, count: keyLength)

        // CCKeyDerivationPBKDF 의 password 인자는 `const char *` 이고,
        // 스위프트는 String 을 그대로 넘길 수 있습니다(길이는 UTF-8 바이트 수).
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            masterPassword,
            passwordLength,
            saltBytes,
            saltBytes.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            UInt32(clamping: iterations),
            &derived,
            derived.count
        )

        guard status == Int32(kCCSuccess) else {
            throw VaultError.keyDerivationFailed(status: status)
        }

        let key = SymmetricKey(data: Data(derived))
        // 파생된 키 사본은 바로 지웁니다. (스위프트가 남긴 다른 복사본까지 보장하지는 못하지만,
        // 우리가 직접 들고 있던 버퍼는 남겨 두지 않습니다.)
        for i in derived.indices { derived[i] = 0 }
        return key
    }

    /// 이 기기에서 목표 시간(초)만큼 걸리는 반복 횟수를 고릅니다.
    ///
    /// 빠른 기기에서는 더 튼튼하게, 느린 기기에서는 기본값을 유지합니다.
    /// 결과는 항상 `defaultIterations ... maximumIterations` 안으로 들어옵니다.
    public static func calibratedIterations(targetSeconds: Double = 0.5) -> Int {
        let probeIterations = 50_000
        let salt = (try? bytes(saltLength)) ?? Data(repeating: 0x41, count: saltLength)

        let start = Date()
        let probe = try? deriveKey(masterPassword: "calibration-probe", salt: salt, iterations: probeIterations)
        guard probe != nil else { return defaultIterations }
        let elapsed = Date().timeIntervalSince(start)

        // 측정이 너무 짧으면 잡음이 커서 신뢰할 수 없습니다. 그냥 기본값을 씁니다.
        guard elapsed > 0.005 else { return defaultIterations }

        let perSecond = Double(probeIterations) / elapsed
        let target = Int((perSecond * targetSeconds).rounded())

        // 만 단위로 반올림해서 값이 지저분해지지 않게 합니다.
        let rounded = (target / 10_000) * 10_000
        return min(max(rounded, defaultIterations), maximumIterations)
    }

    // MARK: - 암·복호화

    /// AES-256-GCM 으로 봉인합니다. 반환값은 `nonce(12) + 암호문 + 태그(16)` 입니다.
    public static func seal(_ plaintext: Data, using key: SymmetricKey, authenticating aad: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: aad)
        guard let combined = sealed.combined else {
            throw VaultError.fileDamaged(reason: "암호문을 만들지 못했습니다.")
        }
        return combined
    }

    /// `seal` 로 만든 데이터를 풉니다.
    ///
    /// 마스터 비밀번호가 틀리면 인증 태그 검증에서 실패하므로 `wrongMasterPassword` 로 바꿔 던집니다.
    public static func open(_ combined: Data, using key: SymmetricKey, authenticating aad: Data) throws -> Data {
        let box: AES.GCM.SealedBox
        do {
            box = try AES.GCM.SealedBox(combined: combined)
        } catch {
            throw VaultError.fileDamaged(reason: "암호문 길이가 올바르지 않습니다.")
        }

        do {
            return try AES.GCM.open(box, using: key, authenticating: aad)
        } catch {
            throw VaultError.wrongMasterPassword
        }
    }

    // MARK: - 도우미

    public static func bytes(_ count: Int) throws -> Data {
        try SecureRandom.bytes(count)
    }

    /// 키를 바이트로 꺼냅니다. 검사·시험용입니다.
    public static func rawBytes(of key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }
}
