import SwiftUI
import VaultCore

/// 마스터 비밀번호 바꾸기.
struct ChangeMasterPasswordView: View {

    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var new = ""
    @State private var confirmation = ""
    @State private var errorText: String?
    @FocusState private var focusedField: Field?

    private enum Field { case current, new, confirmation }

    private var strength: PasswordStrength { PasswordStrength.estimate(new) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("마스터 비밀번호 바꾸기")
                .font(.headline)

            Text("바꾸면 금고 전체를 새 비밀번호로 다시 암호화합니다. 예전 비밀번호로는 더 이상 열 수 없습니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                RomanSecureField(placeholder: "현재 마스터 비밀번호", text: $current)
                    .frame(height: 22)

                RomanSecureField(placeholder: "새 마스터 비밀번호", text: $new)
                    .frame(height: 22)

                RomanSecureField(placeholder: "새 비밀번호 한 번 더", text: $confirmation, onSubmit: apply)
                    .frame(height: 22)

                if !new.isEmpty {
                    StrengthMeter(entropyBits: strength.entropyBits, level: strength.level)
                        .padding(.top, 2)
                }
            }

            if let errorText = errorText {
                Text(errorText)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("취소", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(action: apply) {
                    if state.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("바꾸기")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(state.isBusy || current.isEmpty || new.isEmpty || confirmation.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { focusedField = .current }
    }

    private func apply() {
        guard !state.isBusy else { return }
        errorText = nil

        state.changeMasterPassword(current: current, new: new, confirmation: confirmation) { failure in
            if let failure = failure {
                errorText = failure
            } else {
                dismiss()
            }
        }
    }
}
