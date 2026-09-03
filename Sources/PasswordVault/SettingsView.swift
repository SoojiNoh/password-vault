import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VaultCore

/// ⌘, 로 여는 설정 창.
struct SettingsView: View {

    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            SecuritySettingsTab()
                .tabItem { Label("보안", systemImage: "lock.shield") }

            VaultSettingsTab()
                .environmentObject(state)
                .tabItem { Label("금고", systemImage: "internaldrive") }

            TransferSettingsTab()
                .environmentObject(state)
                .tabItem { Label("가져오기·내보내기", systemImage: "arrow.left.arrow.right") }

            AboutTab()
                .tabItem { Label("정보", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 380)
    }
}

// MARK: - 보안

struct SecuritySettingsTab: View {

    @AppStorage(PreferenceKey.autoLockMinutes) private var autoLockMinutes: Int = 5
    @AppStorage(PreferenceKey.clipboardClearSeconds) private var clipboardClearSeconds: Int = 30
    @AppStorage(PreferenceKey.lockOnSleep) private var lockOnSleep: Bool = true

    var body: some View {
        Form {
            Picker("자동 잠금", selection: $autoLockMinutes) {
                Text("사용 안 함").tag(0)
                Text("1분").tag(1)
                Text("5분").tag(5)
                Text("15분").tag(15)
                Text("30분").tag(30)
                Text("1시간").tag(60)
            }
            Text("정해진 시간 동안 아무 조작이 없으면 금고를 잠급니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            Picker("클립보드 자동 지우기", selection: $clipboardClearSeconds) {
                Text("사용 안 함").tag(0)
                Text("15초").tag(15)
                Text("30초").tag(30)
                Text("1분").tag(60)
                Text("2분").tag(120)
            }
            Text("복사한 비밀번호를 정해진 시간 뒤에 클립보드에서 지웁니다. 그 사이 다른 것을 복사했다면 건드리지 않습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            Toggle("잠자기·화면 잠금 때 금고도 잠그기", isOn: $lockOnSleep)
        }
        .formStyle(.grouped)
        .padding(.vertical, 6)
    }
}

// MARK: - 금고

struct VaultSettingsTab: View {

    @EnvironmentObject private var state: AppState
    @State private var message: String?

    var body: some View {
        Form {
            LabeledContent("금고 파일") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.vaultURL.path)
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    HStack(spacing: 10) {
                        Button("Finder 에서 보기") {
                            NSWorkspace.shared.activateFileViewerSelecting([state.vaultURL])
                        }
                        .buttonStyle(.link)
                        .disabled(!FileManager.default.fileExists(atPath: state.vaultURL.path))

                        Button("다른 금고 파일 열기…") { chooseAnotherVault() }
                            .buttonStyle(.link)

                        if Preferences.vaultPath != nil {
                            Button("기본 위치로 되돌리기") {
                                Preferences.vaultPath = nil
                                state.lock()
                                state.refreshPhaseForCurrentFile()
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
            }

            Divider().padding(.vertical, 4)

            LabeledContent("마스터 비밀번호") {
                Button("바꾸기…") {
                    state.sheet = SheetRequest(kind: .changeMasterPassword)
                }
                .disabled(!state.isUnlocked)
            }

            LabeledContent("암호화") {
                Text("PBKDF2-HMAC-SHA256 으로 키를 만들고 AES-256-GCM 으로 저장합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 6)
    }

    private func chooseAnotherVault() {
        guard let url = FileDialogs.chooseVaultFile() else { return }
        state.lock()
        Preferences.vaultPath = url.path
        state.refreshPhaseForCurrentFile()
        message = "이제 이 파일을 씁니다. 잠금 해제 화면에서 그 금고의 마스터 비밀번호를 입력하세요."
    }
}

// MARK: - 가져오기 · 내보내기

struct TransferSettingsTab: View {

    @EnvironmentObject private var state: AppState
    @State private var message: String?
    @State private var isError = false
    @State private var showPlaintextWarning = false
    @State private var pendingImport: PendingImport?

    /// `.sheet(item:)` 에 넘기려면 Identifiable 이어야 해서 감싼 값.
    struct PendingImport: Identifiable {
        let id = UUID()
        let result: CSVImportResult
    }

    var body: some View {
        Form {
            LabeledContent("CSV 가져오기") {
                VStack(alignment: .leading, spacing: 4) {
                    Button("CSV 파일 고르기…") { importCSV() }
                        .disabled(!state.isUnlocked)
                    Text("크롬·사파리·1Password·Bitwarden 이 내보낸 CSV 를 읽습니다. 가져오기 전에 무엇이 들어올지 먼저 보여 줍니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider().padding(.vertical, 4)

            LabeledContent("암호화 백업") {
                VStack(alignment: .leading, spacing: 4) {
                    Button("백업 파일 저장…") { exportEncryptedBackup() }
                        .disabled(!FileManager.default.fileExists(atPath: state.vaultURL.path))
                    Text("지금 금고 파일을 그대로 복사합니다. 암호화된 상태라 외장 디스크나 클라우드에 둬도 됩니다. 복원하려면 같은 마스터 비밀번호가 필요합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider().padding(.vertical, 4)

            LabeledContent("평문 CSV 내보내기") {
                VStack(alignment: .leading, spacing: 4) {
                    Button("내보내기…", role: .destructive) { showPlaintextWarning = true }
                        .disabled(!state.isUnlocked || state.items.isEmpty)
                    Text("모든 비밀번호가 그대로 읽히는 파일이 만들어집니다. 다른 앱으로 옮길 때만 쓰고, 끝나면 반드시 지우세요.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let message = message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(isError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 6)
        .confirmationDialog(
            "정말 평문으로 내보낼까요?",
            isPresented: $showPlaintextWarning,
            titleVisibility: .visible
        ) {
            Button("내보내기", role: .destructive) { exportPlaintextCSV() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("만들어진 파일에는 모든 비밀번호가 그대로 적힙니다. 누구든 그 파일을 열면 전부 볼 수 있습니다.")
        }
        .sheet(item: $pendingImport) { pending in
            ImportPreviewView(result: pending.result)
                .environmentObject(state)
        }
    }

    // MARK: 동작

    private func importCSV() {
        guard let url = FileDialogs.chooseCSVToImport() else { return }

        do {
            let text = try readTextFile(at: url)
            let result = try VaultImporter.importCSV(text)
            guard !result.items.isEmpty else {
                report("가져올 항목을 찾지 못했습니다.", isError: true)
                return
            }
            pendingImport = PendingImport(result: result)
            message = nil
        } catch {
            report(AppState.message(for: error), isError: true)
        }
    }

    /// CSV 는 UTF-8 이 아닐 수도 있습니다(윈도우 엑셀 등). 몇 가지 인코딩을 차례로 시도합니다.
    private func readTextFile(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let candidates: [String.Encoding] = [.utf8, .utf16, .windowsCP1252, .isoLatin1]
        for encoding in candidates {
            if let text = String(data: data, encoding: encoding), !text.isEmpty {
                return text
            }
        }
        throw VaultError.invalidInput(reason: "파일의 글자 인코딩을 알아내지 못했습니다. UTF-8 로 저장한 뒤 다시 시도해 주세요.")
    }

    private func exportEncryptedBackup() {
        guard let destination = FileDialogs.chooseSaveLocation(
            suggestedName: FileDialogs.datedFileName(prefix: "금고-백업", extension: VaultFile.fileExtension),
            contentTypes: [UTType(filenameExtension: VaultFile.fileExtension) ?? .data],
            message: "암호화된 금고 파일을 그대로 복사합니다."
        ) else { return }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: state.vaultURL, to: destination)
            report("백업을 저장했습니다: \(destination.lastPathComponent)", isError: false)
        } catch {
            report("백업에 실패했습니다. \(error.localizedDescription)", isError: true)
        }
    }

    private func exportPlaintextCSV() {
        guard let destination = FileDialogs.chooseSaveLocation(
            suggestedName: FileDialogs.datedFileName(prefix: "비밀번호-평문", extension: "csv"),
            contentTypes: [.commaSeparatedText],
            message: "주의: 이 파일에는 비밀번호가 그대로 적힙니다."
        ) else { return }

        do {
            let csv = VaultExporter.csv(for: state.items)
            // 엑셀이 한글을 깨뜨리지 않도록 BOM 을 붙입니다.
            var data = Data([0xEF, 0xBB, 0xBF])
            data.append(Data(csv.utf8))
            try data.write(to: destination, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            report("\(state.items.count)개 항목을 내보냈습니다. 다 쓰면 파일을 지우세요.", isError: false)
        } catch {
            report("내보내기에 실패했습니다. \(error.localizedDescription)", isError: true)
        }
    }

    private func report(_ text: String, isError: Bool) {
        message = text
        self.isError = isError
    }
}

// MARK: - 정보

struct AboutTab: View {

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)

            Text(AppInfo.displayName)
                .font(.title3.weight(.semibold))
            Text("버전 \(AppInfo.version) (\(AppInfo.build))")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("""
            비밀번호는 이 맥 안의 파일 한 개에만 들어 있습니다.
            서버로 보내지 않고, 계정도 만들지 않습니다.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
