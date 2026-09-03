import Foundation

/// 무작위 문자 비밀번호 만들기 설정.
public struct PasswordOptions: Equatable {
    public var length: Int
    public var useLowercase: Bool
    public var useUppercase: Bool
    public var useDigits: Bool
    public var useSymbols: Bool
    /// `0 O o I l 1` 처럼 눈으로 구분하기 어려운 글자를 뺍니다.
    public var avoidAmbiguous: Bool
    /// 켜져 있는 문자 종류마다 최소 한 글자씩 반드시 넣습니다.
    public var requireEverySelectedSet: Bool

    public init(
        length: Int = 20,
        useLowercase: Bool = true,
        useUppercase: Bool = true,
        useDigits: Bool = true,
        useSymbols: Bool = true,
        avoidAmbiguous: Bool = false,
        requireEverySelectedSet: Bool = true
    ) {
        self.length = length
        self.useLowercase = useLowercase
        self.useUppercase = useUppercase
        self.useDigits = useDigits
        self.useSymbols = useSymbols
        self.avoidAmbiguous = avoidAmbiguous
        self.requireEverySelectedSet = requireEverySelectedSet
    }

    public static let minimumLength = 4
    public static let maximumLength = 128
}

/// 단어를 이어 붙이는 암구호 만들기 설정. 외워야 하는 마스터 비밀번호에 적합합니다.
public struct PassphraseOptions: Equatable {
    public var wordCount: Int
    public var separator: String
    public var capitalize: Bool
    /// 단어 하나 뒤에 숫자 한 자리를 붙입니다. "숫자를 포함해야 한다" 는 규칙이 있는 사이트용입니다.
    public var includeNumber: Bool

    public init(
        wordCount: Int = 6,
        separator: String = "-",
        capitalize: Bool = false,
        includeNumber: Bool = false
    ) {
        self.wordCount = wordCount
        self.separator = separator
        self.capitalize = capitalize
        self.includeNumber = includeNumber
    }

    public static let minimumWordCount = 3
    public static let maximumWordCount = 12
}

/// 비밀번호 생성기.
public enum PasswordGenerator {

    static let lowercaseSet = "abcdefghijklmnopqrstuvwxyz"
    static let uppercaseSet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    static let digitSet = "0123456789"
    static let symbolSet = "!@#$%^&*()-_=+[]{};:,.?/"

    /// 서로 헷갈리는 글자들.
    static let ambiguousCharacters = Set("0O1lI|`'\"~,;:.")

    // MARK: - 문자 비밀번호

    public static func makePassword(_ options: PasswordOptions) throws -> String {
        let length = min(max(options.length, PasswordOptions.minimumLength), PasswordOptions.maximumLength)

        let pools = enabledPools(for: options)
        guard !pools.isEmpty else {
            throw VaultError.invalidInput(reason: "문자 종류를 최소 하나는 선택해야 합니다.")
        }

        let alphabet = pools.flatMap { $0 }
        guard !alphabet.isEmpty else {
            throw VaultError.invalidInput(reason: "쓸 수 있는 글자가 없습니다. '헷갈리는 글자 제외'를 꺼 보세요.")
        }

        var characters: [Character] = []

        if options.requireEverySelectedSet && pools.count <= length {
            // 종류마다 한 글자씩 확보한 뒤 나머지를 채우고 전체를 섞습니다.
            for pool in pools {
                characters.append(try SecureRandom.element(of: pool))
            }
        }

        while characters.count < length {
            characters.append(try SecureRandom.element(of: alphabet))
        }

        return String(try SecureRandom.shuffled(characters))
    }

    /// `options` 로 만든 비밀번호 한 글자가 갖는 후보 개수.
    public static func alphabetSize(for options: PasswordOptions) -> Int {
        enabledPools(for: options).reduce(0) { $0 + $1.count }
    }

    static func enabledPools(for options: PasswordOptions) -> [[Character]] {
        var pools: [[Character]] = []
        func add(_ source: String) {
            var characters = Array(source)
            if options.avoidAmbiguous {
                characters.removeAll { ambiguousCharacters.contains($0) }
            }
            if !characters.isEmpty { pools.append(characters) }
        }
        if options.useLowercase { add(lowercaseSet) }
        if options.useUppercase { add(uppercaseSet) }
        if options.useDigits { add(digitSet) }
        if options.useSymbols { add(symbolSet) }
        return pools
    }

    // MARK: - 암구호

    public static func makePassphrase(_ options: PassphraseOptions) throws -> String {
        let count = min(max(options.wordCount, PassphraseOptions.minimumWordCount), PassphraseOptions.maximumWordCount)
        let words = WordList.words
        guard !words.isEmpty else {
            throw VaultError.invalidInput(reason: "단어 목록이 비어 있습니다.")
        }

        var chosen: [String] = []
        for _ in 0..<count {
            var word = try SecureRandom.element(of: words)
            if options.capitalize {
                word = word.prefix(1).uppercased() + word.dropFirst()
            }
            chosen.append(word)
        }

        if options.includeNumber {
            let position = try SecureRandom.index(below: chosen.count)
            let digit = try SecureRandom.index(below: 10)
            chosen[position] += String(digit)
        }

        return chosen.joined(separator: options.separator)
    }

    // MARK: - 세기

    /// 우리가 방금 만든 비밀번호의 엔트로피(비트). 무작위로 뽑았다는 사실을 알고 계산하므로 정확합니다.
    ///
    /// `requireEverySelectedSet` 을 켜면 실제 값은 이보다 아주 조금(보통 1비트 미만) 낮습니다.
    public static func entropyBits(for options: PasswordOptions) -> Double {
        let size = alphabetSize(for: options)
        guard size > 1 else { return 0 }
        let length = min(max(options.length, PasswordOptions.minimumLength), PasswordOptions.maximumLength)
        return Double(length) * log2(Double(size))
    }

    /// 암구호의 엔트로피(비트). 실제 단어 개수로 계산하므로 목록이 바뀌어도 값이 정직합니다.
    public static func entropyBits(for options: PassphraseOptions) -> Double {
        let words = WordList.words.count
        guard words > 1 else { return 0 }
        let count = min(max(options.wordCount, PassphraseOptions.minimumWordCount), PassphraseOptions.maximumWordCount)
        var bits = Double(count) * log2(Double(words))
        if options.includeNumber {
            // 어느 단어 뒤에 어떤 숫자가 붙는지가 더해집니다.
            bits += log2(10.0) + log2(Double(count))
        }
        return bits
    }
}
