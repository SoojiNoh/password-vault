import AppKit
import SwiftUI
import VaultCore

/// 잠금 상태에 따라 화면을 갈아 끼우는 최상위 뷰.
struct RootView: View {

    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack(alignment: .bottom) {
            switch state.phase {
            case .needsSetup:
                CreateVaultView()
            case .locked:
                UnlockView()
            case .unlocked:
                MainWindowView()
            }

            if let toast = state.toast {
                ToastOverlay(toast: toast)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: state.toast)
        .alert(
            "문제가 생겼습니다",
            isPresented: Binding(
                get: { state.alertMessage != nil },
                set: { if !$0 { state.alertMessage = nil } }
            ),
            actions: {
                Button("확인", role: .cancel) { state.alertMessage = nil }
            },
            message: {
                Text(state.alertMessage ?? "")
            }
        )
        .sheet(item: $state.sheet) { request in
            sheetContent(for: request)
        }
    }

    @ViewBuilder
    private func sheetContent(for request: SheetRequest) -> some View {
        switch request.kind {
        case .editor(let item, let isNew):
            ItemEditorView(item: item, isNew: isNew)
                .environmentObject(state)
        case .generator:
            GeneratorView(onUse: nil)
                .environmentObject(state)
        case .changeMasterPassword:
            ChangeMasterPasswordView()
                .environmentObject(state)
        }
    }
}

// MARK: - 처음 실행: 금고 만들기

struct CreateVaultView: View {

    @EnvironmentObject private var state: AppState

    @State private var password = ""
    @State private var confirmation = ""
    @State private var suggestion = ""
    @FocusState private var focusedField: Field?

    private enum Field { case password, confirmation }

    private var strength: PasswordStrength { PasswordStrength.estimate(password) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(Color.accentColor)

                VStack(spacing: 6) {
                    Text("금고 만들기")
                        .font(.title2.weight(.semibold))
                    Text("마스터 비밀번호 하나로 나머지 비밀번호를 모두 지킵니다.\n이 비밀번호는 어디에도 저장되지 않으므로 잊어버리면 되돌릴 방법이 없습니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    RomanSecureField(placeholder: "마스터 비밀번호", text: $password)
                        .frame(height: 22)
                        .focused($focusedField, equals: .password)
                        .onSubmit { focusedField = .confirmation }

                    RomanSecureField(placeholder: "한 번 더 입력", text: $confirmation, onSubmit: create)
                        .frame(height: 22)
                        .focused($focusedField, equals: .confirmation)
                        .onSubmit(create)

                    if !password.isEmpty {
                        StrengthMeter(entropyBits: strength.entropyBits, level: strength.level)
                        if let advice = strength.advice.first {
                            Text(advice)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !suggestion.isEmpty {
                        HStack(spacing: 6) {
                            Text(suggestion)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                            Spacer(minLength: 4)
                            Button("쓰기") {
                                password = suggestion
                                confirmation = suggestion
                                suggestion = ""
                            }
                            .buttonStyle(.link)
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                    }

                    Button {
                        suggestion = (try? PasswordGenerator.makePassphrase(PassphraseOptions(wordCount: 6))) ?? ""
                    } label: {
                        Label("외우기 쉬운 비밀번호 제안받기", systemImage: "wand.and.stars")
                            .font(.callout)
                    }
                    .buttonStyle(.link)
                }
                .frame(width: 340)

                if let error = state.unlockError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 340)
                }

                Button(action: create) {
                    if state.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("금고 만들기").frame(width: 120)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .disabled(state.isBusy || password.isEmpty || confirmation.isEmpty)
            }

            Spacer(minLength: 0)

            VaultLocationFooter()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focusedField = .password }
    }

    private func create() {
        guard !state.isBusy else { return }
        state.createVault(masterPassword: password, confirmation: confirmation)
    }
}

// MARK: - 잠금 해제

struct UnlockView: View {

    @EnvironmentObject private var state: AppState

    @State private var password = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)

                Text(AppInfo.displayName)
                    .font(.title2.weight(.semibold))

                RomanSecureField(placeholder: "마스터 비밀번호", text: $password, onSubmit: unlock)
                    .frame(height: 22)
                    .frame(width: 300)
                    .focused($isFocused)
                    .onSubmit(unlock)
                    .disabled(state.isBusy)

                if let error = state.unlockError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 320)
                }

                Button(action: unlock) {
                    if state.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("잠금 해제").frame(width: 100)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .disabled(state.isBusy || password.isEmpty)
            }

            Spacer(minLength: 0)

            VaultLocationFooter()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isFocused = true }
        .onChange(of: state.unlockError) { error in
            // 틀렸으면 입력칸을 비우고 다시 커서를 둡니다.
            guard error != nil else { return }
            password = ""
            isFocused = true
        }
    }

    private func unlock() {
        guard !state.isBusy else { return }
        state.unlock(masterPassword: password)
        password = ""
    }
}

/// 금고 파일이 어디 있는지 아래에 작게 알려 줍니다.
struct VaultLocationFooter: View {

    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "internaldrive")
            Text("금고 파일: \(state.vaultURL.path)")
                .textSelection(.enabled)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([state.vaultURL])
            } label: {
                Text("Finder 에서 보기")
            }
            .buttonStyle(.link)
            .disabled(!FileManager.default.fileExists(atPath: state.vaultURL.path))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
    }
}
