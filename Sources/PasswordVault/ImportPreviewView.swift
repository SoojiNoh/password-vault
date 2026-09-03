import SwiftUI
import VaultCore

/// CSV 를 실제로 넣기 전에 무엇이 들어오는지 보여 주는 화면.
///
/// 남의 파일을 그대로 삼키지 않고, 어떤 열을 무엇으로 읽었는지 먼저 확인시킵니다.
struct ImportPreviewView: View {

    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    let result: CSVImportResult

    @State private var skipDuplicates = true

    /// 제목과 아이디가 모두 같은 항목은 이미 있는 것으로 봅니다.
    private var duplicates: Set<UUID> {
        let existing = Set(state.items.map { "\($0.title)\u{1}\($0.username)" })
        return Set(
            result.items
                .filter { existing.contains("\($0.title)\u{1}\($0.username)") }
                .map(\.id)
        )
    }

    private var itemsToImport: [VaultItem] {
        skipDuplicates ? result.items.filter { !duplicates.contains($0.id) } : result.items
    }

    /// "제목 ← name" 처럼 어떤 열을 무엇으로 읽었는지 보여 줄 문구들.
    private var columnLabels: [String] {
        result.columnMapping
            .sorted { $0.key < $1.key }
            .map { "\($0.key) ← \($0.value)" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("가져오기 미리 보기")
                    .font(.headline)

                Text("항목 \(result.items.count)개를 찾았습니다." + (result.skippedRows > 0 ? " (빈 줄 \(result.skippedRows)개는 건너뜁니다.)" : ""))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if !columnLabels.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(columnLabels, id: \.self) { label in
                            Text(label)
                                .font(.caption)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.14), in: Capsule())
                        }
                        Spacer(minLength: 0)
                    }
                }

                if !duplicates.isEmpty {
                    Toggle("이미 있는 항목 \(duplicates.count)개 건너뛰기", isOn: $skipDuplicates)
                        .font(.callout)
                }
            }
            .padding(20)

            Divider()

            List(result.items) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.kind.symbolName)
                        .foregroundStyle(duplicates.contains(item.id) && skipDuplicates ? Color.secondary : Color.accentColor)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.displayTitle)
                            .lineLimit(1)
                        Text(item.displaySubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if duplicates.contains(item.id) {
                        Text(skipDuplicates ? "건너뜀" : "중복")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if item.password.isEmpty {
                        Text("비밀번호 없음")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .opacity(duplicates.contains(item.id) && skipDuplicates ? 0.45 : 1)
            }

            Divider()

            HStack {
                Text("가져온 비밀번호는 원래 파일에도 그대로 남아 있습니다. 다 옮겼으면 원본 CSV 를 지우세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                Button("취소", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("\(itemsToImport.count)개 가져오기") {
                    state.merge(importedItems: itemsToImport)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(itemsToImport.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 560, height: 520)
    }
}
