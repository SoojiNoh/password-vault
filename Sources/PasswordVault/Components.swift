import SwiftUI
import VaultCore

// MARK: - 세기 표시

/// 비밀번호 세기를 막대와 글씨로 보여 줍니다.
struct StrengthMeter: View {
    var entropyBits: Double
    var level: PasswordStrength.Level
    /// 무작위로 만든 값이면 계산이 정확합니다. 사람이 지은 값이면 어림값이라 "약" 을 붙입니다.
    var isExact: Bool = false

    private var filledSegments: Int { level.rawValue + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(index < filledSegments ? color : Color.secondary.opacity(0.18))
                        .frame(height: 5)
                }
            }

            HStack(spacing: 6) {
                Text(level.label)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(isExact ? "· \(Int(entropyBits.rounded()))비트" : "· 약 \(Int(entropyBits.rounded()))비트")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var color: Color {
        switch level {
        case .veryWeak: return .red
        case .weak: return .orange
        case .fair: return .yellow
        case .strong: return .green
        case .veryStrong: return .teal
        }
    }
}

// MARK: - 값 한 줄

/// 항목 상세에서 쓰는 한 줄. 이름 · 값 · 복사 단추로 이루어집니다.
struct FieldRow<Trailing: View>: View {
    var label: String
    var value: String
    var isSecret: Bool
    var isMonospaced: Bool
    var onCopy: (() -> Void)?
    var trailing: Trailing

    @State private var isRevealed = false

    init(
        label: String,
        value: String,
        isSecret: Bool = false,
        isMonospaced: Bool = false,
        onCopy: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.label = label
        self.value = value
        self.isSecret = isSecret
        self.isMonospaced = isMonospaced
        self.onCopy = onCopy
        self.trailing = trailing()
    }

    private var shouldConceal: Bool { isSecret && !isRevealed }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)

            Group {
                if value.isEmpty {
                    Text("—").foregroundStyle(.tertiary)
                } else if shouldConceal {
                    Text(String(repeating: "•", count: min(max(value.count, 8), 24)))
                        .foregroundStyle(.primary)
                } else {
                    Text(value)
                        .textSelection(.enabled)
                        .font(isMonospaced ? .body.monospaced() : .body)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(isSecret ? 1 : nil)

            HStack(spacing: 2) {
                trailing

                if isSecret && !value.isEmpty {
                    IconButton(
                        systemName: isRevealed ? "eye.slash" : "eye",
                        help: isRevealed ? "가리기" : "보기"
                    ) {
                        isRevealed.toggle()
                    }
                }

                if let onCopy = onCopy, !value.isEmpty {
                    IconButton(systemName: "doc.on.doc", help: "복사") { onCopy() }
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: value) { _ in
            // 다른 항목으로 옮겨 갔는데 이전 항목의 "보기" 상태가 남아 있으면 안 됩니다.
            isRevealed = false
        }
    }
}

extension FieldRow where Trailing == EmptyView {
    /// 오른쪽에 덧붙일 것이 없을 때 쓰는 간단한 형태.
    init(label: String, value: String, isSecret: Bool = false, isMonospaced: Bool = false, onCopy: (() -> Void)? = nil) {
        self.init(
            label: label,
            value: value,
            isSecret: isSecret,
            isMonospaced: isMonospaced,
            onCopy: onCopy,
            trailing: { EmptyView() }
        )
    }
}

/// 툴바·행에서 쓰는 작은 아이콘 단추.
struct IconButton: View {
    var systemName: String
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

// MARK: - OTP

/// 30초마다 바뀌는 OTP 코드와 남은 시간을 보여 줍니다.
struct TOTPRow: View {
    var totp: TOTP
    var onCopy: (String) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let code = totp.code(at: context.date)
            let remaining = totp.secondsRemaining(at: context.date)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("인증 코드")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 96, alignment: .leading)

                Text(spaced(code))
                    .font(.title3.monospacedDigit())
                    .textSelection(.enabled)

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    CountdownRing(progress: totp.progress(at: context.date))
                        .frame(width: 15, height: 15)
                    Text("\(remaining)초")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(remaining <= 5 ? Color.orange : Color.secondary)
                }

                IconButton(systemName: "doc.on.doc", help: "코드 복사") { onCopy(code) }
            }
            .padding(.vertical, 4)
        }
    }

    /// `123456` → `123 456`. 읽고 옮겨 적기 쉽게.
    private func spaced(_ code: String) -> String {
        guard code.count == 6 || code.count == 8 else { return code }
        let middle = code.index(code.startIndex, offsetBy: code.count / 2)
        return "\(code[code.startIndex..<middle]) \(code[middle...])"
    }
}

struct CountdownRing: View {
    var progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.001, 1 - progress))
                .stroke(progress > 0.83 ? Color.orange : Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - 알림

/// 화면 아래쪽에 잠깐 떴다 사라지는 알림.
struct ToastOverlay: View {
    var toast: Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? Color.orange : Color.green)
            Text(toast.text)
                .font(.callout)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .padding(.bottom, 22)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - 빈 화면

struct EmptyStateView: View {
    var systemName: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title3.weight(.medium))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
