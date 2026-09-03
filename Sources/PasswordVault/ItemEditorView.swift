import SwiftUI
import VaultCore

/// 항목을 새로 만들거나 고치는 화면.
struct ItemEditorView: View {

    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var draft: VaultItem
    @State private var urlText: String
    @State private var tagText: String
    @State private var totpText: String
    @State private var isPasswordRevealed = false
    @State private var isGeneratorShown = false

    private let isNew: Bool

    init(item: VaultItem, isNew: Bool) {
        _draft = State(initialValue: item)
        _urlText = State(initialValue: item.urls.first ?? "")
        _tagText = State(initialValue: item.tags.joined(separator: ", "))
        _totpText = State(initialValue: item.totp ?? "")
        self.isNew = isNew
    }

    private var strength: PasswordStrength { PasswordStrength.estimate(draft.password) }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    basicSection

                    if draft.kind == .login {
                        loginSection
                    }

                    if draft.kind == .card {
                        cardTemplateSection
                    }

                    customFieldsSection
                    notesSection
                }
                .padding(20)
            }

            Divider()

            footer
        }
        .frame(width: 520, height: 620)
    }

    // MARK: - 조각들

    private var header: some View {
        HStack {
            Text(isNew ? "새 항목" : "항목 수정")
                .font(.headline)
            Spacer()
            Toggle(isOn: $draft.isFavorite) {
                Label("즐겨찾기", systemImage: draft.isFavorite ? "star.fill" : "star")
            }
            .toggleStyle(.button)
            .help("즐겨찾기")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var basicSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("종류", selection: $draft.kind) {
                ForEach(ItemKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            LabeledField(label: "제목") {
                TextField("예: 지메일", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledField(label: "태그") {
                TextField("쉼표로 구분 (예: 업무, 금융)", text: $tagText)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var loginSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledField(label: "아이디") {
                TextField("아이디 또는 이메일", text: $draft.username)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledField(label: "비밀번호") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Group {
                            if isPasswordRevealed {
                                TextField("비밀번호", text: $draft.password)
                                    .font(.body.monospaced())
                            } else {
                                SecureField("비밀번호", text: $draft.password)
                            }
                        }
                        .textFieldStyle(.roundedBorder)

                        IconButton(
                            systemName: isPasswordRevealed ? "eye.slash" : "eye",
                            help: isPasswordRevealed ? "가리기" : "보기"
                        ) {
                            isPasswordRevealed.toggle()
                        }

                        IconButton(systemName: "wand.and.stars", help: "생성기") {
                            isGeneratorShown = true
                        }
                        .popover(isPresented: $isGeneratorShown, arrowEdge: .bottom) {
                            GeneratorView(onUse: { generated in
                                draft.password = generated
                                isPasswordRevealed = true
                                isGeneratorShown = false
                            })
                            .environmentObject(state)
                            .frame(width: 380)
                        }
                    }

                    if !draft.password.isEmpty {
                        StrengthMeter(entropyBits: strength.entropyBits, level: strength.level)
                            .frame(maxWidth: 260, alignment: .leading)
                    }
                }
            }

            LabeledField(label: "웹사이트") {
                TextField("example.com", text: $urlText)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledField(label: "인증 코드") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("otpauth://... 또는 Base32 시크릿", text: $totpText)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout.monospaced())
                    Text(totpHint)
                        .font(.caption)
                        .foregroundStyle(isTOTPTextUsable ? Color.secondary : Color.red)
                }
            }
        }
    }

    private var isTOTPTextUsable: Bool {
        totpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || TOTP.parse(totpText) != nil
    }

    private var totpHint: String {
        if totpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "2단계 인증을 쓰는 사이트라면 설정 화면의 '수동 입력' 값을 붙여넣으세요."
        }
        if let totp = TOTP.parse(totpText) {
            return "확인됨 · \(totp.digits)자리 · \(totp.period)초 · \(totp.algorithm.rawValue)"
        }
        return "해석하지 못했습니다. Base32 시크릿이나 otpauth:// 주소인지 확인해 주세요."
    }

    private var cardTemplateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("카드 정보")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(Self.cardTemplates) { template in
                    Button(template.label) {
                        addField(label: template.label, isSecret: template.isSecret)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(draft.customFields.contains { $0.label == template.label })
                }
            }
        }
    }

    struct CardTemplate: Identifiable {
        var label: String
        var isSecret: Bool
        var id: String { label }
    }

    private static let cardTemplates: [CardTemplate] = [
        CardTemplate(label: "카드 번호", isSecret: true),
        CardTemplate(label: "유효기간", isSecret: false),
        CardTemplate(label: "CVC", isSecret: true),
        CardTemplate(label: "카드 비밀번호", isSecret: true),
    ]

    private var customFieldsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("추가 항목")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    addField(label: "", isSecret: false)
                } label: {
                    Label("추가", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            if draft.customFields.isEmpty {
                Text("복구 코드, 계좌번호처럼 따로 적어 둘 값이 있으면 여기에 넣으세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach($draft.customFields) { $field in
                HStack(spacing: 6) {
                    TextField("이름", text: $field.label)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)

                    if field.isSecret {
                        SecureField("값", text: $field.value)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        TextField("값", text: $field.value)
                            .textFieldStyle(.roundedBorder)
                    }

                    IconButton(
                        systemName: field.isSecret ? "lock.fill" : "lock.open",
                        help: field.isSecret ? "가려서 보관 중" : "그대로 보이게 보관 중"
                    ) {
                        $field.wrappedValue.isSecret.toggle()
                    }

                    IconButton(systemName: "minus.circle", help: "이 줄 지우기") {
                        draft.customFields.removeAll { $0.id == field.id }
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("메모")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $draft.notes)
                .font(.body)
                .frame(minHeight: 90)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3))
                )
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("취소", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("저장", action: save)
                .keyboardShortcut(.defaultAction)
                .disabled(!isSavable)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// 완전히 빈 항목만 막습니다. 어디든 채워져 있으면 저장할 수 있습니다.
    private var isSavable: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.username.isEmpty
            || !draft.password.isEmpty
            || !draft.notes.isEmpty
            || draft.customFields.contains { !$0.value.isEmpty }
    }

    // MARK: - 동작

    private func addField(label: String, isSecret: Bool) {
        draft.customFields.append(CustomField(label: label, value: "", isSecret: isSecret))
    }

    private func save() {
        var item = draft

        let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        item.urls = url.isEmpty ? [] : [url]

        item.tags = tagText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let totp = totpText.trimmingCharacters(in: .whitespacesAndNewlines)
        item.totp = totp.isEmpty ? nil : totp

        // 이름도 값도 없는 빈 줄은 저장하지 않습니다.
        item.customFields = item.customFields.filter {
            !($0.label.trimmingCharacters(in: .whitespaces).isEmpty && $0.value.isEmpty)
        }

        if isNew {
            state.addItem(item)
        } else {
            state.update(item)
        }
        dismiss()
    }
}

/// 왼쪽에 이름, 오른쪽에 입력칸을 두는 한 줄.
struct LabeledField<Content: View>: View {
    var label: String
    var content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .trailing)
            content
        }
    }
}
