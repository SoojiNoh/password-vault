import AppKit
import SwiftUI
import VaultCore

/// 잠금이 풀렸을 때 보이는 본 화면. 사이드바 · 목록 · 상세의 세 칸 구조입니다.
struct MainWindowView: View {

    @EnvironmentObject private var state: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 290)
        } content: {
            ItemListView()
                .navigationSplitViewColumnWidth(min: 250, ideal: 310, max: 440)
        } detail: {
            DetailColumn()
        }
        .navigationTitle(state.filter.title)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    state.sheet = SheetRequest(kind: .editor(item: newItemTemplate(), isNew: true))
                } label: {
                    Label("새 항목", systemImage: "plus")
                }
                .help("새 항목 (⌘N)")

                Button {
                    state.sheet = SheetRequest(kind: .generator)
                } label: {
                    Label("비밀번호 생성기", systemImage: "wand.and.stars")
                }
                .help("비밀번호 생성기 (⇧⌘G)")

                Button {
                    state.lock()
                } label: {
                    Label("잠그기", systemImage: "lock")
                }
                .help("지금 잠그기 (⌘L)")
            }
        }
    }

    /// 지금 보고 있는 분류에 맞춰 새 항목의 기본값을 정합니다.
    private func newItemTemplate() -> VaultItem {
        var item = VaultItem()
        switch state.filter {
        case .kind(let kind):
            item.kind = kind
        case .tag(let tag):
            item.tags = [tag]
        case .favorites:
            item.isFavorite = true
        default:
            break
        }
        return item
    }
}

// MARK: - 사이드바

struct SidebarView: View {

    @EnvironmentObject private var state: AppState

    private var selection: Binding<SidebarFilter?> {
        Binding(
            get: { state.filter },
            set: { if let value = $0 { state.filter = value } }
        )
    }

    var body: some View {
        List(selection: selection) {
            Section("보관함") {
                row(.all, count: state.items.count)
                row(.favorites, count: state.items.filter(\.isFavorite).count)
            }

            Section("종류") {
                ForEach(ItemKind.allCases, id: \.self) { kind in
                    row(.kind(kind), count: state.items.filter { $0.kind == kind }.count)
                }
            }

            Section("점검") {
                row(.weakPasswords, count: state.weakCount)
                row(.reusedPasswords, count: state.reusedCount)
            }

            if !state.allTags.isEmpty {
                Section("태그") {
                    ForEach(state.allTags, id: \.self) { tag in
                        row(.tag(tag), count: state.items.filter { $0.tags.contains(tag) }.count)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ filter: SidebarFilter, count: Int) -> some View {
        Label(filter.title, systemImage: filter.symbolName)
            .badge(count)
            .tag(filter)
    }
}

// MARK: - 가운데 목록

struct ItemListView: View {

    @EnvironmentObject private var state: AppState
    @State private var pendingDeletion: VaultItem?

    var body: some View {
        List(selection: $state.selectedItemID) {
            ForEach(state.visibleItems) { item in
                ItemRow(item: item)
                    .tag(item.id)
                    .contextMenu {
                        Button("비밀번호 복사") { state.copy(item.password, describedAs: "비밀번호") }
                            .disabled(item.password.isEmpty)
                        Button("아이디 복사") { state.copy(item.username, describedAs: "아이디") }
                            .disabled(item.username.isEmpty)

                        Divider()

                        Button(item.isFavorite ? "즐겨찾기 해제" : "즐겨찾기") {
                            state.toggleFavorite(item.id)
                        }
                        Button("수정…") {
                            state.sheet = SheetRequest(kind: .editor(item: item, isNew: false))
                        }

                        Divider()

                        Button("삭제…", role: .destructive) { pendingDeletion = item }
                    }
            }
        }
        .searchable(text: $state.searchText, placement: .automatic, prompt: "제목 · 아이디 · 주소 · 태그 검색")
        .overlay {
            if state.visibleItems.isEmpty {
                emptyState
            }
        }
        .confirmationDialog(
            "'\(pendingDeletion?.displayTitle ?? "")' 항목을 삭제할까요?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                if let item = pendingDeletion { state.delete(ids: [item.id]) }
                pendingDeletion = nil
            }
            Button("취소", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("되돌릴 수 없습니다.")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !state.searchText.isEmpty {
            EmptyStateView(
                systemName: "magnifyingglass",
                title: "결과 없음",
                message: "'\(state.searchText)' 와 맞는 항목이 없습니다."
            )
        } else if state.items.isEmpty {
            EmptyStateView(
                systemName: "key.horizontal",
                title: "아직 항목이 없습니다",
                message: "⌘N 을 눌러 첫 항목을 넣거나, 설정에서 다른 앱의 CSV 를 가져오세요."
            )
        } else {
            EmptyStateView(
                systemName: "tray",
                title: "이 분류는 비어 있습니다",
                message: "왼쪽에서 다른 분류를 골라 보세요."
            )
        }
    }
}

struct ItemRow: View {

    var item: VaultItem

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: item.kind.symbolName)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayTitle)
                    .lineLimit(1)
                Text(item.displaySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
            if item.totp != nil {
                Image(systemName: "clock.badge.checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 오른쪽 상세

struct DetailColumn: View {

    @EnvironmentObject private var state: AppState

    var body: some View {
        if let item = state.selectedItem {
            ItemDetailView(item: item)
        } else {
            EmptyStateView(
                systemName: "lock.doc",
                title: "항목을 고르세요",
                message: "왼쪽 목록에서 항목을 고르면 내용이 여기에 보입니다."
            )
        }
    }
}
