import AppKit
import Combine
import Foundation
import SwiftUI
import VaultCore

/// 사이드바에서 고른 분류.
enum SidebarFilter: Hashable {
    case all
    case favorites
    case kind(ItemKind)
    case tag(String)
    case weakPasswords
    case reusedPasswords

    var title: String {
        switch self {
        case .all: return "모든 항목"
        case .favorites: return "즐겨찾기"
        case .kind(let kind): return kind.displayName
        case .tag(let tag): return tag
        case .weakPasswords: return "약한 비밀번호"
        case .reusedPasswords: return "재사용한 비밀번호"
        }
    }

    var symbolName: String {
        switch self {
        case .all: return "tray.full"
        case .favorites: return "star"
        case .kind(let kind): return kind.symbolName
        case .tag: return "tag"
        case .weakPasswords: return "exclamationmark.shield"
        case .reusedPasswords: return "doc.on.doc"
        }
    }
}

/// 시트로 띄우는 화면.
struct SheetRequest: Identifiable {
    enum Kind {
        case editor(item: VaultItem, isNew: Bool)
        case generator
        case changeMasterPassword
    }

    let id = UUID()
    let kind: Kind
}

/// 화면 아래에 잠깐 떴다 사라지는 알림.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var isError: Bool = false

    static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
}

/// 앱 전체 상태.
///
/// 일부러 `@MainActor` 를 붙이지 않았습니다. 키 파생은 느려서 백그라운드 큐에서 돌리고,
/// 결과만 메인 큐로 되돌려 반영합니다. 아래 `assertMain()` 으로 그 규칙을 지키는지 확인합니다.
final class AppState: ObservableObject {

    enum Phase: Equatable {
        /// 금고 파일이 아직 없음 → 만들기 화면.
        case needsSetup
        /// 파일은 있고 잠겨 있음 → 잠금 해제 화면.
        case locked
        /// 열려 있음 → 본 화면.
        case unlocked
    }

    // MARK: - 게시되는 상태

    @Published private(set) var phase: Phase = .locked
    @Published private(set) var items: [VaultItem] = []
    @Published var selectedItemID: UUID?
    @Published var searchText: String = ""
    @Published var filter: SidebarFilter = .all
    @Published private(set) var isBusy: Bool = false
    @Published var unlockError: String?
    @Published var alertMessage: String?
    @Published var sheet: SheetRequest?
    @Published var toast: Toast?

    // MARK: - 내부

    private var vault: UnlockedVault?
    private var lastActivity = Date()
    private var autoLockTimer: Timer?
    private var activityMonitor: Any?
    private var sleepObservers: [NSObjectProtocol] = []

    /// 브라우저 자동완성용 소켓 서버. 잠금이 풀린 동안에만 떠 있습니다.
    private lazy var autofillServer = AutofillServer { [weak self] pageURL in
        guard let self, self.phase == .unlocked else { return nil }   // 잠겨 있으면 아무것도 안 준다
        guard Preferences.autofillEnabled else { return nil }
        return AutofillMatch.candidates(for: pageURL, in: self.items)
    }

    var vaultURL: URL {
        if let path = Preferences.vaultPath, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return VaultFile.defaultURL()
    }

    init() {
        Preferences.registerDefaults()
        refreshPhaseForCurrentFile()
        installSleepObservers()
        startAutofillIfEnabled()
    }

    deinit {
        autoLockTimer?.invalidate()
        if let monitor = activityMonitor { NSEvent.removeMonitor(monitor) }
        for observer in sleepObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    func refreshPhaseForCurrentFile() {
        phase = VaultFile.exists(at: vaultURL) ? .locked : .needsSetup
    }

    // MARK: - 잠금 해제 · 만들기

    /// 새 금고를 만듭니다. 느린 작업이라 백그라운드에서 돌립니다.
    func createVault(masterPassword: String, confirmation: String) {
        unlockError = nil

        guard masterPassword == confirmation else {
            unlockError = "두 번 입력한 비밀번호가 서로 다릅니다."
            return
        }
        guard masterPassword.count >= 8 else {
            unlockError = "마스터 비밀번호는 최소 8자 이상이어야 합니다."
            return
        }

        let url = vaultURL
        isBusy = true

        DispatchQueue.global(qos: .userInitiated).async {
            // 이 기기 속도에 맞춰 반복 횟수를 정합니다.
            let iterations = VaultCrypto.calibratedIterations()
            let outcome = Result {
                try VaultFile.create(at: url, masterPassword: masterPassword, iterations: iterations)
            }

            DispatchQueue.main.async {
                self.isBusy = false
                switch outcome {
                case .success(let vault):
                    self.vault = vault
                    self.items = []
                    self.phase = .unlocked
                    self.beginAutoLockWatch()
                    self.startAutofillIfEnabled()
                    self.show(Toast(text: "금고를 만들었습니다."))
                case .failure(let error):
                    self.unlockError = Self.message(for: error)
                }
            }
        }
    }

    /// 기존 금고를 엽니다.
    func unlock(masterPassword: String) {
        guard !masterPassword.isEmpty else {
            unlockError = "마스터 비밀번호를 입력해 주세요."
            return
        }

        unlockError = nil
        let url = vaultURL
        isBusy = true

        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Result { try VaultFile.unlock(at: url, masterPassword: masterPassword) }

            DispatchQueue.main.async {
                self.isBusy = false
                switch outcome {
                case .success(let (vault, document)):
                    self.vault = vault
                    self.items = document.items
                    self.selectedItemID = nil
                    self.phase = .unlocked
                    self.beginAutoLockWatch()
                    self.startAutofillIfEnabled()
                case .failure(let error):
                    self.unlockError = Self.message(for: error)
                }
            }
        }
    }

    /// 금고를 잠급니다. 메모리에서 키와 항목을 모두 버립니다.
    func lock() {
        assertMain()
        endAutoLockWatch()
        Clipboard.clearIfHoldingSecret()
        // 소켓은 열어 둔다. 잠긴 동안에는 조회 함수가 nil 을 돌려주므로 아무것도 나가지 않고,
        // 확장은 "잠겨 있다"는 사실만 알아 사용자에게 안내할 수 있다.

        vault = nil
        items = []
        selectedItemID = nil
        searchText = ""
        filter = .all
        sheet = nil
        phase = VaultFile.exists(at: vaultURL) ? .locked : .needsSetup
    }

    var isUnlocked: Bool { phase == .unlocked }

    /// 설정에서 켜 두었을 때만 브라우저용 통로를 엽니다.
    ///
    /// 잠겨 있어도 열어 둡니다. 잠긴 동안에는 조회 함수가 `nil` 을 돌려주므로
    /// 항목은 하나도 나가지 않고, 확장은 "잠겨 있으니 풀어 달라"고 안내만 합니다.
    func startAutofillIfEnabled() {
        assertMain()
        if Preferences.autofillEnabled {
            autofillServer.start()
        } else {
            autofillServer.stop()
        }
    }

    // MARK: - 항목 다루기

    func addItem(_ item: VaultItem) {
        assertMain()
        var new = item
        new.updatedAt = Date()
        new.createdAt = Date()
        if !new.password.isEmpty { new.passwordChangedAt = Date() }
        items.append(new)
        selectedItemID = new.id
        persist()
    }

    func update(_ item: VaultItem) {
        assertMain()
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        var updated = item
        updated.updatedAt = Date()
        if items[index].password != item.password && !item.password.isEmpty {
            updated.passwordChangedAt = Date()
        }
        items[index] = updated
        persist()
    }

    func delete(ids: Set<UUID>) {
        assertMain()
        guard !ids.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        if let selected = selectedItemID, ids.contains(selected) {
            selectedItemID = nil
        }
        persist()
        show(Toast(text: ids.count == 1 ? "항목을 삭제했습니다." : "항목 \(ids.count)개를 삭제했습니다."))
    }

    func toggleFavorite(_ id: UUID) {
        assertMain()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isFavorite.toggle()
        items[index].updatedAt = Date()
        persist()
    }

    func item(with id: UUID?) -> VaultItem? {
        guard let id = id else { return nil }
        return items.first { $0.id == id }
    }

    var selectedItem: VaultItem? { item(with: selectedItemID) }

    /// 가져온 항목들을 추가합니다.
    func merge(importedItems: [VaultItem]) {
        assertMain()
        guard !importedItems.isEmpty else { return }
        items.append(contentsOf: importedItems)
        persist()
        show(Toast(text: "\(importedItems.count)개 항목을 가져왔습니다."))
    }

    // MARK: - 저장

    /// 지금 상태를 파일에 씁니다. 실패하면 사용자에게 알립니다(조용히 넘어가면 안 되는 오류입니다).
    func persist() {
        assertMain()
        guard let vault = vault else { return }

        do {
            try vault.save(VaultDocument(items: items))
        } catch {
            alertMessage = """
            금고를 저장하지 못했습니다.

            \(Self.message(for: error))

            창을 닫지 마시고, 디스크 여유 공간과 파일 권한을 확인한 뒤 다시 시도해 주세요.
            """
        }
    }

    // MARK: - 목록 만들기

    /// 사이드바 분류와 검색어를 적용한 목록.
    var visibleItems: [VaultItem] {
        let reused = reusedPasswordValues

        let filtered = items.filter { item in
            switch filter {
            case .all:
                return true
            case .favorites:
                return item.isFavorite
            case .kind(let kind):
                return item.kind == kind
            case .tag(let tag):
                return item.tags.contains(tag)
            case .weakPasswords:
                return Self.isWeak(item)
            case .reusedPasswords:
                return !item.password.isEmpty && reused.contains(item.password)
            }
        }

        let searched = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? filtered
            : filtered.filter { $0.matches(query: searchText) }

        return searched.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
        }
    }

    var allTags: [String] { VaultDocument(items: items).allTags }

    static func isWeak(_ item: VaultItem) -> Bool {
        guard item.kind == .login, !item.password.isEmpty else { return false }
        return PasswordStrength.estimate(item.password).level <= .weak
    }

    /// 두 개 이상의 항목에서 똑같이 쓰인 비밀번호들.
    var reusedPasswordValues: Set<String> {
        var counts: [String: Int] = [:]
        for item in items where !item.password.isEmpty {
            counts[item.password, default: 0] += 1
        }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    var weakCount: Int { items.filter(Self.isWeak).count }

    var reusedCount: Int {
        let reused = reusedPasswordValues
        return items.filter { !$0.password.isEmpty && reused.contains($0.password) }.count
    }

    // MARK: - 복사

    func copy(_ value: String, describedAs label: String) {
        assertMain()
        guard !value.isEmpty else {
            show(Toast(text: "\(label)이(가) 비어 있습니다.", isError: true))
            return
        }

        let seconds = Preferences.clipboardClearSeconds
        Clipboard.copy(value, clearAfter: seconds)
        noteActivity()

        if seconds > 0 {
            show(Toast(text: "\(label) 복사됨 · \(seconds)초 뒤 지워집니다"))
        } else {
            show(Toast(text: "\(label) 복사됨"))
        }
    }

    func show(_ toast: Toast) {
        assertMain()
        self.toast = toast
        let shown = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if self.toast == shown { self.toast = nil }
        }
    }

    // MARK: - 마스터 비밀번호 바꾸기

    func changeMasterPassword(current: String, new: String, confirmation: String, completion: @escaping (String?) -> Void) {
        assertMain()

        guard let vault = vault else {
            completion("금고가 잠겨 있습니다.")
            return
        }
        guard new == confirmation else {
            completion("새 비밀번호를 두 번 다르게 입력했습니다.")
            return
        }
        guard new.count >= 8 else {
            completion("새 마스터 비밀번호는 최소 8자 이상이어야 합니다.")
            return
        }

        let url = vault.url
        let document = VaultDocument(items: items)
        isBusy = true

        DispatchQueue.global(qos: .userInitiated).async {
            // 현재 비밀번호가 맞는지 먼저 확인합니다.
            do {
                _ = try VaultFile.unlock(at: url, masterPassword: current)
            } catch {
                DispatchQueue.main.async {
                    self.isBusy = false
                    completion("현재 마스터 비밀번호가 맞지 않습니다.")
                }
                return
            }

            let iterations = VaultCrypto.calibratedIterations()
            let outcome = Result {
                try VaultFile.changeMasterPassword(
                    vault: vault,
                    document: document,
                    newPassword: new,
                    iterations: iterations
                )
            }

            DispatchQueue.main.async {
                self.isBusy = false
                switch outcome {
                case .success(let updated):
                    self.vault = updated
                    self.show(Toast(text: "마스터 비밀번호를 바꿨습니다."))
                    completion(nil)
                case .failure(let error):
                    completion(Self.message(for: error))
                }
            }
        }
    }

    // MARK: - 자동 잠금

    func noteActivity() {
        lastActivity = Date()
    }

    private func beginAutoLockWatch() {
        assertMain()
        endAutoLockWatch()
        noteActivity()

        activityMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .mouseMoved]
        ) { [weak self] event in
            self?.lastActivity = Date()
            return event
        }

        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.checkIdleTimeout() }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoLockTimer = timer
    }

    private func endAutoLockWatch() {
        autoLockTimer?.invalidate()
        autoLockTimer = nil
        if let monitor = activityMonitor {
            NSEvent.removeMonitor(monitor)
            activityMonitor = nil
        }
    }

    private func checkIdleTimeout() {
        guard isUnlocked else { return }
        let minutes = Preferences.autoLockMinutes
        guard minutes > 0 else { return }

        if Date().timeIntervalSince(lastActivity) >= Double(minutes) * 60 {
            lock()
            show(Toast(text: "\(minutes)분 동안 조작이 없어 잠갔습니다."))
        }
    }

    private func installSleepObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        let sleepNames: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
        ]
        for name in sleepNames {
            let observer = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.lockIfPreferred()
            }
            sleepObservers.append(observer)
        }

        // 화면 잠금(⌃⌘Q 등)은 배포된 알림으로 옵니다.
        let lockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.lockIfPreferred()
        }
        sleepObservers.append(lockObserver)
    }

    private func lockIfPreferred() {
        guard isUnlocked, Preferences.lockOnSleep else { return }
        lock()
    }

    // MARK: - 도우미

    static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// 게시 상태를 메인 스레드 밖에서 건드리면 SwiftUI 가 조용히 깨집니다. 개발 중에 바로 잡습니다.
    private func assertMain() {
        assert(Thread.isMainThread, "AppState 는 메인 스레드에서만 바꿔야 합니다.")
    }
}
