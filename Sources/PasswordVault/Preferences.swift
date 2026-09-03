import Foundation

/// 사용자 설정. 값 자체는 비밀이 아니므로 UserDefaults 에 둡니다.
/// (금고 내용은 절대 여기에 들어가지 않습니다.)
enum PreferenceKey {
    static let autoLockMinutes = "autoLockMinutes"
    static let clipboardClearSeconds = "clipboardClearSeconds"
    static let lockOnSleep = "lockOnSleep"
    static let vaultPath = "vaultPath"
}

enum Preferences {

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PreferenceKey.autoLockMinutes: 5,
            PreferenceKey.clipboardClearSeconds: 30,
            PreferenceKey.lockOnSleep: true,
        ])
    }

    /// 0 이면 자동 잠금을 쓰지 않습니다.
    static var autoLockMinutes: Int {
        UserDefaults.standard.integer(forKey: PreferenceKey.autoLockMinutes)
    }

    /// 0 이면 클립보드를 비우지 않습니다.
    static var clipboardClearSeconds: Int {
        UserDefaults.standard.integer(forKey: PreferenceKey.clipboardClearSeconds)
    }

    static var lockOnSleep: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKey.lockOnSleep)
    }

    /// 사용자가 금고 위치를 옮겼다면 그 경로. 없으면 기본 위치를 씁니다.
    static var vaultPath: String? {
        get { UserDefaults.standard.string(forKey: PreferenceKey.vaultPath) }
        set {
            if let newValue = newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: PreferenceKey.vaultPath)
            } else {
                UserDefaults.standard.removeObject(forKey: PreferenceKey.vaultPath)
            }
        }
    }
}
