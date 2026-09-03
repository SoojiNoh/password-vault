import Foundation

/// 금고 동작 중 사용자에게 그대로 보여줄 수 있는 오류.
///
/// 오류 메시지에는 절대로 비밀번호·키·평문 항목을 담지 않습니다.
public enum VaultError: Error, LocalizedError, Equatable {
    case randomGeneratorFailed(status: Int32)
    case keyDerivationFailed(status: Int32)
    case wrongMasterPassword
    case fileDamaged(reason: String)
    case unsupportedFormat(found: String)
    case unsupportedVersion(found: Int, supported: Int)
    case weakKDFParameters(iterations: Int, minimum: Int)
    case vaultAlreadyExists(path: String)
    case vaultNotFound(path: String)
    case locked
    case invalidInput(reason: String)

    public var errorDescription: String? {
        switch self {
        case .randomGeneratorFailed(let status):
            return "안전한 난수를 만들지 못했습니다. (코드 \(status))"
        case .keyDerivationFailed(let status):
            return "마스터 비밀번호로 키를 만들지 못했습니다. (코드 \(status))"
        case .wrongMasterPassword:
            return "마스터 비밀번호가 맞지 않습니다."
        case .fileDamaged(let reason):
            return "금고 파일을 읽을 수 없습니다. \(reason)"
        case .unsupportedFormat(let found):
            return "금고 파일 형식이 아닙니다. (\(found))"
        case .unsupportedVersion(let found, let supported):
            return "이 앱보다 새로운 금고 파일입니다. (파일 v\(found), 앱 v\(supported)) 앱을 최신 버전으로 올려 주세요."
        case .weakKDFParameters(let iterations, let minimum):
            return "금고 파일의 반복 횟수(\(iterations))가 안전 기준(\(minimum))보다 낮습니다. 위조된 파일일 수 있습니다."
        case .vaultAlreadyExists(let path):
            return "이미 금고가 있습니다: \(path)"
        case .vaultNotFound(let path):
            return "금고 파일이 없습니다: \(path)"
        case .locked:
            return "금고가 잠겨 있습니다."
        case .invalidInput(let reason):
            return reason
        }
    }
}
