import AppKit
import SwiftUI
import VaultCore

/// 앱 본체. `main.swift` 에서 `VaultApp.main()` 으로 시작합니다.
struct VaultApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 880, minHeight: 560)
        }
        .defaultSize(width: 1080, height: 700)
        .commands {
            VaultCommands(state: state)
        }

        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 번들 없이 실행 파일만 직접 돌릴 때도 정상적인 앱처럼 보이게 합니다.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 브라우저용 소켓 파일을 남기지 않고 나갑니다.
        AutofillServer.removeStaleSocket()
    }
}

/// 메뉴 막대와 단축키.
struct VaultCommands: Commands {

    @ObservedObject var state: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("새 항목") {
                state.sheet = SheetRequest(kind: .editor(item: VaultItem(), isNew: true))
            }
            .keyboardShortcut("n")
            .disabled(!state.isUnlocked)
        }

        CommandGroup(replacing: .appInfo) {
            Button("\(AppInfo.displayName) 정보") {
                NSApp.orderFrontStandardAboutPanel(options: [
                    .applicationName: AppInfo.displayName,
                    .applicationVersion: AppInfo.version,
                    .version: AppInfo.build,
                ])
            }
        }

        CommandMenu("금고") {
            Button("지금 잠그기") { state.lock() }
                .keyboardShortcut("l")
                .disabled(!state.isUnlocked)

            Divider()

            Button("비밀번호 복사") {
                if let item = state.selectedItem { state.copy(item.password, describedAs: "비밀번호") }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(state.selectedItem == nil)

            Button("아이디 복사") {
                if let item = state.selectedItem { state.copy(item.username, describedAs: "아이디") }
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(state.selectedItem == nil)

            Button("웹사이트 열기") {
                if let raw = state.selectedItem?.primaryURL,
                   let url = URL(string: VaultItem.normalizedURLString(raw)) {
                    NSWorkspace.shared.open(url)
                }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(state.selectedItem?.primaryURL == nil)

            Divider()

            Button("비밀번호 생성기") {
                state.sheet = SheetRequest(kind: .generator)
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])

            Button("마스터 비밀번호 바꾸기…") {
                state.sheet = SheetRequest(kind: .changeMasterPassword)
            }
            .disabled(!state.isUnlocked)
        }
    }
}
