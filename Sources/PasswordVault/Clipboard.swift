import AppKit

/// 클립보드에 비밀을 잠깐만 올려 두기 위한 도우미.
enum Clipboard {

    /// 클립보드 관리자 앱들이 "이건 비밀이니 기록하지 말라" 고 알아듣는 표시.
    /// (nspasteboard.org 의 관례입니다.)
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// 값을 복사하고, 정해진 시간 뒤에 자동으로 지웁니다.
    ///
    /// 지우기 직전에 `changeCount` 를 확인해, 그 사이 사용자가 다른 것을 복사했다면 건드리지 않습니다.
    static func copy(_ value: String, clearAfter seconds: Int) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        pasteboard.setString(value, forType: concealedType)

        guard seconds > 0 else { return }

        let stamp = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) {
            let current = NSPasteboard.general
            guard current.changeCount == stamp else { return }
            current.clearContents()
        }
    }

    /// 지금 당장 비웁니다(잠글 때 호출).
    static func clearIfHoldingSecret() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.types?.contains(concealedType) == true else { return }
        pasteboard.clearContents()
    }
}
