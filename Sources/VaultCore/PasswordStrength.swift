import Foundation

/// 사용자가 직접 입력한 비밀번호의 세기 어림값.
///
/// 무작위로 만든 비밀번호는 `PasswordGenerator.entropyBits(for:)` 로 정확히 계산할 수 있지만,
/// 사람이 지은 비밀번호는 그럴 수 없습니다. 여기서 나오는 값은 **어림값**이고,
/// 실제보다 후하게 나올 수 있다는 전제로 화면에 "약" 을 붙여 보여 줍니다.
public struct PasswordStrength: Equatable {

    public enum Level: Int, Comparable, Equatable {
        case veryWeak = 0
        case weak
        case fair
        case strong
        case veryStrong

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

        public var label: String {
            switch self {
            case .veryWeak: return "매우 약함"
            case .weak: return "약함"
            case .fair: return "보통"
            case .strong: return "강함"
            case .veryStrong: return "매우 강함"
            }
        }
    }

    public var entropyBits: Double
    public var level: Level
    public var advice: [String]

    public init(entropyBits: Double, level: Level, advice: [String] = []) {
        self.entropyBits = entropyBits
        self.level = level
        self.advice = advice
    }

    // MARK: - 계산

    public static func level(forEntropyBits bits: Double) -> Level {
        switch bits {
        case ..<35: return .veryWeak
        case ..<55: return .weak
        case ..<75: return .fair
        case ..<100: return .strong
        default: return .veryStrong
        }
    }

    public static func estimate(_ password: String) -> PasswordStrength {
        guard !password.isEmpty else {
            return PasswordStrength(entropyBits: 0, level: .veryWeak, advice: ["비밀번호를 입력해 주세요."])
        }

        let characters = Array(password)
        let pool = poolSize(for: characters)
        let effective = effectiveLength(of: characters)
        var bits = effective * log2(Double(max(pool, 2)))

        var advice: [String] = []

        if isCommon(password) {
            // 사전에 있는 값이면 길이와 상관없이 사실상 즉시 뚫립니다.
            bits = min(bits, 12)
            advice.append("널리 알려진 비밀번호입니다. 다른 것으로 바꾸세요.")
        }

        if characters.count < 12 {
            advice.append("12자 이상으로 늘리면 훨씬 안전해집니다.")
        }
        if pool <= 26 {
            advice.append("대문자·숫자·기호를 섞어 보세요.")
        }
        if hasLongRun(characters) {
            advice.append("`1234`, `abcd`, `aaaa` 같은 이어지는 글자는 쉽게 추측됩니다.")
        }

        let level = level(forEntropyBits: bits)
        if level >= .strong && advice.isEmpty {
            advice.append("충분히 강합니다.")
        }

        return PasswordStrength(entropyBits: bits, level: level, advice: advice)
    }

    // MARK: - 내부 계산기

    /// 쓰인 글자 종류로 후보 글자 수를 어림합니다.
    static func poolSize(for characters: [Character]) -> Int {
        var pool = 0
        var hasLower = false, hasUpper = false, hasDigit = false, hasSymbol = false, hasOther = false

        for character in characters {
            if character.isLowercase && character.isASCII { hasLower = true }
            else if character.isUppercase && character.isASCII { hasUpper = true }
            else if character.isNumber && character.isASCII { hasDigit = true }
            else if character.isASCII { hasSymbol = true }
            else { hasOther = true }
        }

        if hasLower { pool += 26 }
        if hasUpper { pool += 26 }
        if hasDigit { pool += 10 }
        if hasSymbol { pool += 33 }
        // 한글·이모지 등. 후보가 훨씬 많지만 후하게 잡지 않도록 보수적으로 더합니다.
        if hasOther { pool += 128 }

        return pool
    }

    /// 반복과 연속을 감안한 "실질 길이".
    ///
    /// `aaaaaaaa` 는 8자여도 8자만큼의 값어치가 없습니다.
    static func effectiveLength(of characters: [Character]) -> Double {
        guard let first = characters.first else { return 0 }
        var total = 1.0
        var previous = first

        for index in 1..<characters.count {
            let current = characters[index]
            if current == previous {
                total += 0.35
            } else if isConsecutive(previous, current) {
                total += 0.5
            } else {
                total += 1.0
            }
            previous = current
        }
        return total
    }

    /// `a`→`b`, `3`→`4` 처럼 바로 이어지는지(오르막·내리막 모두).
    static func isConsecutive(_ lhs: Character, _ rhs: Character) -> Bool {
        guard let a = lhs.asciiValue, let b = rhs.asciiValue else { return false }
        let difference = Int(a) - Int(b)
        return difference == 1 || difference == -1
    }

    /// 4글자 이상 이어지거나 반복되는 구간이 있는지.
    static func hasLongRun(_ characters: [Character]) -> Bool {
        guard characters.count >= 4 else { return false }
        var run = 1
        for index in 1..<characters.count {
            if characters[index] == characters[index - 1] || isConsecutive(characters[index - 1], characters[index]) {
                run += 1
                if run >= 4 { return true }
            } else {
                run = 1
            }
        }
        return false
    }

    /// 흔한 비밀번호인지. 뒤에 붙은 숫자는 떼고 봅니다(`password123` → `password`).
    static func isCommon(_ password: String) -> Bool {
        var normalized = password.lowercased()
        while let last = normalized.last, last.isNumber {
            normalized.removeLast()
        }
        if normalized.isEmpty { normalized = password.lowercased() }

        if commonPasswords.contains(normalized) { return true }
        if commonPasswords.contains(password.lowercased()) { return true }

        // 키보드 줄을 그대로 친 경우.
        for row in keyboardRows where row.count >= 4 {
            if row.hasPrefix(normalized) && normalized.count >= 4 { return true }
            if String(row.reversed()).hasPrefix(normalized) && normalized.count >= 4 { return true }
        }
        return false
    }

    static let keyboardRows = [
        "qwertyuiop",
        "asdfghjkl",
        "zxcvbnm",
        "1234567890",
    ]

    static let commonPasswords: Set<String> = [
        "password", "passwd", "pass", "admin", "administrator", "root", "guest",
        "welcome", "letmein", "login", "changeme", "secret", "master", "manager",
        "qwerty", "qwertyuiop", "asdf", "asdfgh", "zxcvbn", "abc", "abcd", "abcdef",
        "iloveyou", "sunshine", "princess", "dragon", "monkey", "football", "baseball",
        "superman", "batman", "trustno", "starwars", "whatever", "shadow", "michael",
        "computer", "internet", "samsung", "korea", "seoul", "hangul", "test", "temp",
        "hello", "hellow", "helloworld", "default", "user", "username", "system",
    ]
}
