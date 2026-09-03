import Foundation

/// 앱 이름·버전 같은 고정 정보.
enum AppInfo {
    static let displayName = "비밀번호 금고"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }
}
