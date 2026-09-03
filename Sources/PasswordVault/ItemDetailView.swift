import AppKit
import SwiftUI
import VaultCore

/// 고른 항목의 내용을 보여 줍니다.
struct ItemDetailView: View {

    @EnvironmentObject private var state: AppState
    var item: VaultItem

    @State private var showDeleteConfirmation = false

    private var strength: PasswordStrength { PasswordStrength.estimate(item.password) }
    private var isReused: Bool {
        !item.password.isEmpty && state.reusedPasswordValues.contains(item.password)
    }
    private var totp: TOTP? {
        guard let raw = item.totp else { return nil }
        return TOTP.parse(raw)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if !warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(warnings, id: \.self) { warning in
                            WarningBanner(text: warning)
                        }
                    }
                }

                switch item.kind {
                case .login:
                    loginFields
                case .card:
                    cardFields
                case .secureNote:
                    EmptyView()
                }

                if !item.customFields.isEmpty {
                    section("추가 항목") {
                        ForEach(item.customFields) { field in
                            FieldRow(
                                label: field.label,
                                value: field.value,
                                isSecret: field.isSecret,
                                onCopy: { state.copy(field.value, describedAs: field.label) }
                            )
                        }
                    }
                }

                if !item.notes.isEmpty {
                    section("메모") {
                        Text(item.notes)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !item.tags.isEmpty {
                    section("태그") {
                        HStack(spacing: 6) {
                            ForEach(item.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.14), in: Capsule())
                            }
                            Spacer()
                        }
                    }
                }

                timestamps
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .confirmationDialog(
            "'\(item.displayTitle)' 항목을 삭제할까요?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) { state.delete(ids: [item.id]) }
            Button("취소", role: .cancel) {}
        } message: {
            Text("되돌릴 수 없습니다.")
        }
    }

    // MARK: - 조각들

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: item.kind.symbolName)
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                Text(item.kind.displayName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                IconButton(
                    systemName: item.isFavorite ? "star.fill" : "star",
                    help: item.isFavorite ? "즐겨찾기 해제" : "즐겨찾기"
                ) {
                    state.toggleFavorite(item.id)
                }

                Button {
                    state.sheet = SheetRequest(kind: .editor(item: item, isNew: false))
                } label: {
                    Label("수정", systemImage: "pencil")
                }

                IconButton(systemName: "trash", help: "삭제") {
                    showDeleteConfirmation = true
                }
            }
        }
    }

    @ViewBuilder
    private var loginFields: some View {
        section("로그인") {
            FieldRow(
                label: "아이디",
                value: item.username,
                onCopy: { state.copy(item.username, describedAs: "아이디") }
            )

            VStack(alignment: .leading, spacing: 2) {
                FieldRow(
                    label: "비밀번호",
                    value: item.password,
                    isSecret: true,
                    isMonospaced: true,
                    onCopy: { state.copy(item.password, describedAs: "비밀번호") }
                )
                if !item.password.isEmpty {
                    StrengthMeter(entropyBits: strength.entropyBits, level: strength.level)
                        .padding(.leading, 108)
                        .frame(maxWidth: 260, alignment: .leading)
                }
            }

            // 값이 비어 있으면 FieldRow 가 복사 단추를 감춥니다.
            FieldRow(
                label: "웹사이트",
                value: item.primaryURL ?? "",
                onCopy: { state.copy(item.primaryURL ?? "", describedAs: "주소") }
            ) {
                if let raw = item.primaryURL, let url = URL(string: VaultItem.normalizedURLString(raw)) {
                    IconButton(systemName: "arrow.up.forward.app", help: "브라우저에서 열기") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            if let totp = totp {
                Divider()
                TOTPRow(totp: totp) { code in
                    state.copy(code, describedAs: "인증 코드")
                }
            } else if let raw = item.totp, !raw.isEmpty {
                FieldRow(label: "인증 코드", value: "형식을 알 수 없는 OTP 시크릿입니다")
            }
        }
    }

    @ViewBuilder
    private var cardFields: some View {
        if item.customFields.isEmpty {
            section("카드") {
                Text("수정을 눌러 카드 번호·유효기간 같은 항목을 추가하세요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timestamps: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("만든 날짜  \(Self.formatter.string(from: item.createdAt))")
            Text("수정한 날짜  \(Self.formatter.string(from: item.updatedAt))")
            if let changed = item.passwordChangedAt {
                Text("비밀번호를 바꾼 날짜  \(Self.formatter.string(from: changed))")
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    private var warnings: [String] {
        var result: [String] = []
        if AppState.isWeak(item) {
            result.append("이 비밀번호는 추측하기 쉽습니다. 생성기로 새로 만들어 바꾸는 것을 권합니다.")
        }
        if isReused {
            result.append("같은 비밀번호를 다른 항목에서도 쓰고 있습니다. 한 곳이 뚫리면 함께 뚫립니다.")
        }
        if let changed = item.passwordChangedAt,
           Date().timeIntervalSince(changed) > 60 * 60 * 24 * 365 {
            result.append("비밀번호를 바꾼 지 1년이 넘었습니다.")
        }
        return result
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

struct WarningBanner: View {
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
