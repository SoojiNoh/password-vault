import SwiftUI
import VaultCore

/// 비밀번호 생성기.
///
/// 시트로 혼자 띄울 수도 있고, 항목 수정 화면에서 팝오버로 띄워 바로 값을 넣을 수도 있습니다.
struct GeneratorView: View {

    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    /// 값이 있으면 "이 비밀번호 쓰기" 단추가 나타납니다.
    var onUse: ((String) -> Void)?

    @AppStorage("generatorMode") private var modeRawValue: String = Mode.characters.rawValue
    @AppStorage("generatorLength") private var length: Int = 20
    @AppStorage("generatorUppercase") private var useUppercase: Bool = true
    @AppStorage("generatorDigits") private var useDigits: Bool = true
    @AppStorage("generatorSymbols") private var useSymbols: Bool = true
    @AppStorage("generatorAvoidAmbiguous") private var avoidAmbiguous: Bool = false
    @AppStorage("generatorWordCount") private var wordCount: Int = 6
    @AppStorage("generatorSeparator") private var separator: String = "-"
    @AppStorage("generatorCapitalize") private var capitalize: Bool = false
    @AppStorage("generatorIncludeNumber") private var includeNumber: Bool = false

    @State private var generated: String = ""
    @State private var errorText: String?

    enum Mode: String, CaseIterable {
        case characters
        case words

        var title: String {
            switch self {
            case .characters: return "무작위 문자"
            case .words: return "외우기 쉬운 단어"
            }
        }
    }

    private var mode: Mode { Mode(rawValue: modeRawValue) ?? .characters }

    private var passwordOptions: PasswordOptions {
        PasswordOptions(
            length: length,
            useLowercase: true,
            useUppercase: useUppercase,
            useDigits: useDigits,
            useSymbols: useSymbols,
            avoidAmbiguous: avoidAmbiguous,
            requireEverySelectedSet: true
        )
    }

    private var passphraseOptions: PassphraseOptions {
        PassphraseOptions(
            wordCount: wordCount,
            separator: separator,
            capitalize: capitalize,
            includeNumber: includeNumber
        )
    }

    /// 생성기가 만든 값이므로 엔트로피를 정확히 계산할 수 있습니다.
    private var entropyBits: Double {
        switch mode {
        case .characters: return PasswordGenerator.entropyBits(for: passwordOptions)
        case .words: return PasswordGenerator.entropyBits(for: passphraseOptions)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: Binding(get: { mode }, set: { modeRawValue = $0.rawValue; regenerate() })) {
                ForEach(Mode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            display

            StrengthMeter(
                entropyBits: entropyBits,
                level: PasswordStrength.level(forEntropyBits: entropyBits),
                isExact: true
            )

            Divider()

            switch mode {
            case .characters:
                characterOptions
            case .words:
                wordOptions
            }

            if let errorText = errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            HStack {
                Button {
                    regenerate()
                } label: {
                    Label("다시 만들기", systemImage: "arrow.clockwise")
                }

                Spacer()

                Button("복사") {
                    state.copy(generated, describedAs: "비밀번호")
                }
                .disabled(generated.isEmpty)

                if let onUse = onUse {
                    Button("이 비밀번호 쓰기") { onUse(generated) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(generated.isEmpty)
                } else {
                    Button("닫기") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(18)
        .frame(minWidth: 380)
        .onAppear { if generated.isEmpty { regenerate() } }
    }

    // MARK: - 조각들

    private var display: some View {
        HStack(alignment: .top, spacing: 8) {
            colorized(generated)
                .font(.system(.title3, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            IconButton(systemName: "arrow.clockwise", help: "다시 만들기") { regenerate() }
        }
        .padding(12)
        .frame(minHeight: 64, alignment: .topLeading)
        .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// 숫자와 기호에 색을 달리 입혀 눈으로 옮겨 적기 쉽게 합니다.
    private func colorized(_ text: String) -> Text {
        text.reduce(Text("")) { partial, character in
            partial + Text(String(character)).foregroundColor(color(for: character))
        }
    }

    private func color(for character: Character) -> Color {
        if character.isNumber { return .blue }
        if character.isLetter { return .primary }
        return .pink
    }

    private var characterOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("길이")
                    .frame(width: 44, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { Double(length) },
                        set: { length = Int($0.rounded()); regenerate() }
                    ),
                    in: 8...64,
                    step: 1
                )
                Text("\(length)")
                    .font(.body.monospacedDigit())
                    .frame(width: 28, alignment: .trailing)
            }

            HStack(spacing: 14) {
                Toggle("대문자", isOn: toggle($useUppercase))
                Toggle("숫자", isOn: toggle($useDigits))
                Toggle("기호", isOn: toggle($useSymbols))
            }

            Toggle("헷갈리는 글자 빼기 (0 O 1 l I 등)", isOn: toggle($avoidAmbiguous))
                .font(.callout)
        }
    }

    private var wordOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("단어 수")
                    .frame(width: 54, alignment: .leading)
                Stepper(
                    value: Binding(get: { wordCount }, set: { wordCount = $0; regenerate() }),
                    in: PassphraseOptions.minimumWordCount...PassphraseOptions.maximumWordCount
                ) {
                    Text("\(wordCount)개")
                        .font(.body.monospacedDigit())
                }
            }

            HStack {
                Text("구분 기호")
                    .frame(width: 66, alignment: .leading)
                Picker("", selection: Binding(get: { separator }, set: { separator = $0; regenerate() })) {
                    Text("하이픈 -").tag("-")
                    Text("밑줄 _").tag("_")
                    Text("마침표 .").tag(".")
                    Text("공백").tag(" ")
                }
                .labelsHidden()
                .frame(width: 130)
                Spacer()
            }

            HStack(spacing: 14) {
                Toggle("첫 글자 대문자", isOn: toggle($capitalize))
                Toggle("숫자 넣기", isOn: toggle($includeNumber))
            }
            .font(.callout)
        }
    }

    /// 설정을 건드리면 곧바로 새 비밀번호를 보여 주도록 감싼 바인딩.
    private func toggle(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { binding.wrappedValue },
            set: { binding.wrappedValue = $0; regenerate() }
        )
    }

    private func regenerate() {
        do {
            switch mode {
            case .characters:
                generated = try PasswordGenerator.makePassword(passwordOptions)
            case .words:
                generated = try PasswordGenerator.makePassphrase(passphraseOptions)
            }
            errorText = nil
        } catch {
            generated = ""
            errorText = AppState.message(for: error)
        }
    }
}
