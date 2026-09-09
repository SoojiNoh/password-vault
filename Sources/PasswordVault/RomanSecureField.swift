import AppKit
import SwiftUI

/// 비밀번호 입력칸. 포커스가 오면 **입력기를 영문으로 자동 전환**합니다.
///
/// 왜 필요한가:
/// macOS 는 비밀번호 칸에 커서가 들어가면 "보안 입력 모드"를 켜서 입력기(IME)를 우회합니다.
/// 이때 한국어 두벌식처럼 조합이 필요한 입력기가 켜져 있으면 **영문자가 조합 단계에서
/// 사라지고 숫자만 들어갑니다.** 화면에는 아무 표시도 안 나서, 사용자는 자기가 친 대로
/// 들어간 줄 압니다.
///
/// 실제로 이것 때문에 금고를 못 여는 일이 생겼습니다. 영문 상태에서 문자로 만든 비밀번호를
/// 나중에 한글 상태에서 치면 숫자만 전달되어 "비밀번호가 맞지 않습니다"가 뜹니다.
///
/// `allowedInputSourceLocales` 에 로마자를 지정해 두면 이 칸에 들어올 때 시스템이 알아서
/// 영문 입력으로 바꿔 줍니다. 사용자가 한/영 키를 신경 쓸 필요가 없어집니다.
///
/// 실측(2026-09-09, 두벌식 켠 채 진짜 키코드로 `abc123` 입력):
///
///     일반 TextField      → 뮻123    (영문자가 한글로 조합됨)
///     예전 SecureField    → 123      (영문자가 통째로 사라짐 ← 제보된 증상)
///     이 RomanSecureField → abc123   (정상)
///
/// 실제 앱에서도 두벌식 상태로 `seoul2026` 을 쳐서 금고를 만든 뒤,
/// 그 비밀번호로 열리는 것까지 확인했습니다(숫자만인 `2026` 은 거부).
struct RomanSecureField: NSViewRepresentable {

    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = RomanSecureTextField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.isBordered = true
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        return field
    }

    func updateNSView(_ field: NSSecureTextField, context: Context) {
        context.coordinator.parent = self
        // 밖에서 값이 바뀐 경우(초기화 등)에만 맞춰 준다. 타이핑 중에는 건드리지 않는다.
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RomanSecureField
        init(_ parent: RomanSecureField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

/// 포커스를 받을 때 입력기를 영문으로 돌리는 비밀번호 칸.
final class RomanSecureTextField: NSSecureTextField {

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { forceRomanInput() }
        return became
    }

    /// 실제로 입력을 처리하는 것은 창이 빌려주는 편집기(field editor)입니다.
    /// 거기에 "로마자 입력만 쓴다"고 알려 주면 시스템이 입력기를 바꿔 줍니다.
    private func forceRomanInput() {
        guard let editor = currentEditor() as? NSTextView else { return }
        editor.allowedInputSourceLocales = [NSAllRomanInputSourcesLocaleIdentifier]
    }
}
