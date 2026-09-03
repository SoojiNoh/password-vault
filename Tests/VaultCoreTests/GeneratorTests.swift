import XCTest
@testable import VaultCore

final class SecureRandomTests: XCTestCase {

    func testBytesLength() throws {
        XCTAssertEqual(try SecureRandom.bytes(0).count, 0)
        XCTAssertEqual(try SecureRandom.bytes(1).count, 1)
        XCTAssertEqual(try SecureRandom.bytes(64).count, 64)
    }

    func testIndexStaysInRange() throws {
        for bound in [1, 2, 3, 7, 26, 95, 1000] {
            for _ in 0..<200 {
                let value = try SecureRandom.index(below: bound)
                XCTAssertTrue(value >= 0 && value < bound, "\(value) 가 0..<\(bound) 밖입니다.")
            }
        }
    }

    func testIndexRejectsBadBounds() {
        XCTAssertThrowsError(try SecureRandom.index(below: 0))
        XCTAssertThrowsError(try SecureRandom.index(below: -5))
    }

    /// 완벽한 균등성을 증명할 수는 없지만, 한쪽으로 심하게 쏠리면 잡아냅니다.
    func testIndexIsRoughlyUniform() throws {
        let bound = 6
        let draws = 6_000
        var counts = [Int](repeating: 0, count: bound)
        for _ in 0..<draws {
            counts[try SecureRandom.index(below: bound)] += 1
        }
        let expected = Double(draws) / Double(bound)
        for (value, count) in counts.enumerated() {
            let ratio = Double(count) / expected
            XCTAssertTrue(ratio > 0.75 && ratio < 1.25, "값 \(value) 가 \(count)번 나왔습니다(기대 \(Int(expected))).")
        }
    }

    func testShuffleKeepsEveryElement() throws {
        let original = Array(0..<50)
        let shuffled = try SecureRandom.shuffled(original)
        XCTAssertEqual(shuffled.sorted(), original)
    }

    func testShuffleActuallyChangesOrder() throws {
        let original = Array(0..<50)
        var sawDifferentOrder = false
        for _ in 0..<10 {
            if try SecureRandom.shuffled(original) != original {
                sawDifferentOrder = true
                break
            }
        }
        XCTAssertTrue(sawDifferentOrder, "열 번을 섞었는데 한 번도 순서가 바뀌지 않았습니다.")
    }
}

final class PasswordGeneratorTests: XCTestCase {

    func testLengthIsHonored() throws {
        for length in [4, 8, 16, 32, 64, 128] {
            let password = try PasswordGenerator.makePassword(PasswordOptions(length: length))
            XCTAssertEqual(password.count, length)
        }
    }

    func testLengthIsClamped() throws {
        let tooShort = try PasswordGenerator.makePassword(PasswordOptions(length: 1))
        XCTAssertEqual(tooShort.count, PasswordOptions.minimumLength)

        let tooLong = try PasswordGenerator.makePassword(PasswordOptions(length: 9_999))
        XCTAssertEqual(tooLong.count, PasswordOptions.maximumLength)
    }

    func testOnlySelectedCharacterSetsAppear() throws {
        let digitsOnly = PasswordOptions(
            length: 40,
            useLowercase: false,
            useUppercase: false,
            useDigits: true,
            useSymbols: false
        )
        let password = try PasswordGenerator.makePassword(digitsOnly)
        XCTAssertTrue(password.allSatisfy { $0.isNumber })
    }

    func testEverySelectedSetAppears() throws {
        let options = PasswordOptions(length: 8, requireEverySelectedSet: true)
        for _ in 0..<50 {
            let password = try PasswordGenerator.makePassword(options)
            XCTAssertTrue(password.contains(where: { $0.isLowercase }))
            XCTAssertTrue(password.contains(where: { $0.isUppercase }))
            XCTAssertTrue(password.contains(where: { $0.isNumber }))
            XCTAssertTrue(password.contains(where: { PasswordGenerator.symbolSet.contains($0) }))
        }
    }

    func testNoCharacterSetSelectedThrows() {
        let options = PasswordOptions(
            length: 12,
            useLowercase: false,
            useUppercase: false,
            useDigits: false,
            useSymbols: false
        )
        XCTAssertThrowsError(try PasswordGenerator.makePassword(options))
    }

    func testAmbiguousCharactersAreExcluded() throws {
        let options = PasswordOptions(length: 100, avoidAmbiguous: true)
        let password = try PasswordGenerator.makePassword(options)
        for character in password {
            XCTAssertFalse(
                PasswordGenerator.ambiguousCharacters.contains(character),
                "'\(character)' 가 남아 있습니다."
            )
        }
    }

    func testPasswordsDoNotRepeat() throws {
        var seen = Set<String>()
        for _ in 0..<200 {
            seen.insert(try PasswordGenerator.makePassword(PasswordOptions(length: 16)))
        }
        XCTAssertEqual(seen.count, 200)
    }

    func testEntropyMatchesAlphabet() {
        let options = PasswordOptions(length: 10, useSymbols: false)
        // 소문자 26 + 대문자 26 + 숫자 10 = 62
        XCTAssertEqual(PasswordGenerator.alphabetSize(for: options), 62)
        XCTAssertEqual(PasswordGenerator.entropyBits(for: options), 10 * log2(62.0), accuracy: 0.0001)
    }

    func testPassphraseShape() throws {
        let options = PassphraseOptions(wordCount: 5, separator: ".", capitalize: true)
        let phrase = try PasswordGenerator.makePassphrase(options)
        let words = phrase.split(separator: ".").map(String.init)

        XCTAssertEqual(words.count, 5)
        for word in words {
            XCTAssertTrue(word.first?.isUppercase == true, "'\(word)' 의 첫 글자가 대문자가 아닙니다.")
        }
    }

    func testPassphraseWordCountIsClamped() throws {
        let tooFew = try PasswordGenerator.makePassphrase(PassphraseOptions(wordCount: 1))
        XCTAssertEqual(tooFew.split(separator: "-").count, PassphraseOptions.minimumWordCount)
    }

    func testPassphraseNumberOption() throws {
        let options = PassphraseOptions(wordCount: 4, includeNumber: true)
        let phrase = try PasswordGenerator.makePassphrase(options)
        XCTAssertTrue(phrase.contains(where: { $0.isNumber }), "숫자가 들어가지 않았습니다.")
        XCTAssertEqual(phrase.split(separator: "-").count, 4)
    }

    func testPassphraseEntropyUsesRealWordCount() {
        let expected = 6 * log2(Double(WordList.words.count))
        XCTAssertEqual(
            PasswordGenerator.entropyBits(for: PassphraseOptions(wordCount: 6)),
            expected,
            accuracy: 0.0001
        )
    }

    func testWordListIsClean() {
        let words = WordList.words
        XCTAssertGreaterThanOrEqual(words.count, 1_000)
        XCTAssertEqual(Set(words).count, words.count, "중복된 단어가 있습니다.")
        for word in words {
            XCTAssertTrue(word.allSatisfy { $0.isLowercase && $0.isASCII }, "'\(word)' 에 이상한 글자가 있습니다.")
            XCTAssertGreaterThanOrEqual(word.count, 3)
        }
    }
}

final class PasswordStrengthTests: XCTestCase {

    func testEmptyIsVeryWeak() {
        XCTAssertEqual(PasswordStrength.estimate("").level, .veryWeak)
    }

    func testCommonPasswordsAreVeryWeak() {
        for password in ["password", "Password1", "qwerty", "123456", "letmein", "admin"] {
            XCTAssertEqual(
                PasswordStrength.estimate(password).level,
                .veryWeak,
                "'\(password)' 를 약하다고 보지 않았습니다."
            )
        }
    }

    func testRepeatedCharactersScoreLow() {
        let repeated = PasswordStrength.estimate("aaaaaaaaaaaaaaaaaaaa")
        let varied = PasswordStrength.estimate("kQ7#vLm2Rz9!pWx4Ns6")
        XCTAssertLessThan(repeated.entropyBits, varied.entropyBits)
    }

    func testGeneratedPasswordIsStrong() throws {
        let password = try PasswordGenerator.makePassword(PasswordOptions(length: 20))
        XCTAssertGreaterThanOrEqual(PasswordStrength.estimate(password).level, .strong)
    }

    func testLongPassphraseIsStrong() throws {
        let phrase = try PasswordGenerator.makePassphrase(PassphraseOptions(wordCount: 6))
        XCTAssertGreaterThanOrEqual(PasswordStrength.estimate(phrase).level, .fair)
    }

    func testLevelThresholds() {
        XCTAssertEqual(PasswordStrength.level(forEntropyBits: 0), .veryWeak)
        XCTAssertEqual(PasswordStrength.level(forEntropyBits: 34.9), .veryWeak)
        XCTAssertEqual(PasswordStrength.level(forEntropyBits: 35), .weak)
        XCTAssertEqual(PasswordStrength.level(forEntropyBits: 55), .fair)
        XCTAssertEqual(PasswordStrength.level(forEntropyBits: 75), .strong)
        XCTAssertEqual(PasswordStrength.level(forEntropyBits: 100), .veryStrong)
    }

    func testRunDetection() {
        XCTAssertTrue(PasswordStrength.hasLongRun(Array("abcd")))
        XCTAssertTrue(PasswordStrength.hasLongRun(Array("x1234y")))
        XCTAssertTrue(PasswordStrength.hasLongRun(Array("aaaa")))
        XCTAssertFalse(PasswordStrength.hasLongRun(Array("a1b2c3")))
    }
}
