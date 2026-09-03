import Foundation

/// 만들어진 앱이 실제로 동작하는지 스스로 확인합니다.
///
/// `PasswordVault.app/Contents/MacOS/PasswordVault --selftest` 로 실행되며,
/// 여기서 하나라도 실패하면 CI 가 배포를 중단합니다.
/// "빌드가 됐다" 와 "금고가 제대로 잠기고 열린다" 는 다른 문제이기 때문입니다.
public enum SelfTest {

    public struct Report {
        public var passed: [String] = []
        public var failed: [String] = []
        public var isSuccess: Bool { failed.isEmpty }
    }

    /// 모든 검사를 돌리고 결과를 표준 출력에 적습니다. 성공하면 `true`.
    public static func run(log: (String) -> Void = { print($0) }) -> Bool {
        var report = Report()

        func check(_ name: String, _ body: () throws -> Void) {
            do {
                try body()
                report.passed.append(name)
                log("  통과  \(name)")
            } catch {
                report.failed.append(name)
                log("  실패  \(name) — \(error.localizedDescription)")
            }
        }

        log("비밀번호 금고 자체 검사")
        log("")

        check("난수가 매번 다르게 나온다", checkRandomness)
        check("같은 비밀번호·솔트는 같은 키를 만든다", checkKeyDerivationIsDeterministic)
        check("암호화한 내용을 그대로 되돌린다", checkRoundTrip)
        check("틀린 마스터 비밀번호는 거부된다", checkWrongPasswordIsRejected)
        check("파일을 한 글자만 고쳐도 열리지 않는다", checkTamperDetection)
        check("반복 횟수를 낮춘 파일은 거부된다", checkDowngradeIsRejected)
        check("저장하고 다시 읽으면 항목이 같다", checkVaultFileRoundTrip)
        check("마스터 비밀번호를 바꿔도 내용이 남는다", checkMasterPasswordChange)
        check("생성기가 조건에 맞는 비밀번호를 만든다", checkGenerator)
        check("암구호 단어 목록이 충분히 크다", checkWordList)
        check("OTP 코드가 RFC 6238 예시와 일치한다", checkTOTPVectors)
        check("CSV 를 읽고 쓴다", checkCSV)

        log("")
        if report.isSuccess {
            log("검사 \(report.passed.count)개 모두 통과했습니다.")
        } else {
            log("검사 \(report.failed.count)개가 실패했습니다: \(report.failed.joined(separator: ", "))")
        }
        return report.isSuccess
    }

    // MARK: - 개별 검사

    struct SelfTestFailure: Error, LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw SelfTestFailure(message: message) }
    }

    static func checkRandomness() throws {
        let a = try SecureRandom.bytes(32)
        let b = try SecureRandom.bytes(32)
        try expect(a.count == 32 && b.count == 32, "길이가 32바이트가 아닙니다.")
        try expect(a != b, "두 번 뽑은 난수가 같습니다.")
        try expect(a != Data(repeating: 0, count: 32), "난수가 전부 0 입니다.")
    }

    static func checkKeyDerivationIsDeterministic() throws {
        let salt = try SecureRandom.bytes(32)
        let first = VaultCrypto.rawBytes(
            of: try VaultCrypto.deriveKey(masterPassword: "동일한-비밀번호", salt: salt, iterations: 200_000)
        )
        let second = VaultCrypto.rawBytes(
            of: try VaultCrypto.deriveKey(masterPassword: "동일한-비밀번호", salt: salt, iterations: 200_000)
        )
        let other = VaultCrypto.rawBytes(
            of: try VaultCrypto.deriveKey(masterPassword: "다른-비밀번호", salt: salt, iterations: 200_000)
        )

        try expect(first.count == VaultCrypto.keyLength, "키 길이가 \(VaultCrypto.keyLength)바이트가 아닙니다.")
        try expect(first == second, "같은 입력인데 다른 키가 나왔습니다.")
        try expect(first != other, "다른 비밀번호인데 같은 키가 나왔습니다.")
    }

    static func checkRoundTrip() throws {
        let salt = try SecureRandom.bytes(32)
        let key = try VaultCrypto.deriveKey(masterPassword: "열쇠", salt: salt, iterations: 200_000)
        let message = Data("비밀 메시지 secret 🔐".utf8)
        let aad = Data("머리말".utf8)

        let sealed = try VaultCrypto.seal(message, using: key, authenticating: aad)
        try expect(sealed != message, "암호문이 평문과 같습니다.")
        let opened = try VaultCrypto.open(sealed, using: key, authenticating: aad)
        try expect(opened == message, "복호화 결과가 원본과 다릅니다.")
    }

    static func checkWrongPasswordIsRejected() throws {
        try withTemporaryVault { url in
            _ = try VaultFile.create(
                at: url,
                masterPassword: "올바른-비밀번호",
                document: VaultDocument(items: [VaultItem(title: "은행")]),
                iterations: VaultCrypto.defaultIterations
            )

            do {
                _ = try VaultFile.unlock(at: url, masterPassword: "틀린-비밀번호")
                throw SelfTestFailure(message: "틀린 비밀번호로 금고가 열렸습니다.")
            } catch VaultError.wrongMasterPassword {
                // 기대한 결과.
            }
        }
    }

    static func checkTamperDetection() throws {
        try withTemporaryVault { url in
            _ = try VaultFile.create(at: url, masterPassword: "비밀번호", document: VaultDocument(items: [VaultItem(title: "메일")]))

            // 암호문 한 글자를 바꿉니다.
            var raw = try String(contentsOf: url, encoding: .utf8)
            guard let range = raw.range(of: "\"payload\" : \"") ?? raw.range(of: "\"payload\":\"") else {
                throw SelfTestFailure(message: "payload 필드를 찾지 못했습니다.")
            }
            let position = range.upperBound
            let original = raw[position]
            let replacement: Character = original == "A" ? "B" : "A"
            raw.replaceSubrange(position...position, with: String(replacement))
            try raw.write(to: url, atomically: true, encoding: .utf8)

            do {
                _ = try VaultFile.unlock(at: url, masterPassword: "비밀번호")
                throw SelfTestFailure(message: "변조된 파일이 그대로 열렸습니다.")
            } catch VaultError.wrongMasterPassword {
                // 인증 태그 검증 실패. 기대한 결과.
            } catch VaultError.fileDamaged {
                // base64 자체가 깨진 경우. 이것도 막힌 것이므로 통과.
            }
        }
    }

    static func checkDowngradeIsRejected() throws {
        try withTemporaryVault { url in
            _ = try VaultFile.create(at: url, masterPassword: "비밀번호")

            var raw = try String(contentsOf: url, encoding: .utf8)
            raw = raw.replacingOccurrences(
                of: "\"iterations\" : \(VaultCrypto.defaultIterations)",
                with: "\"iterations\" : 1000"
            )
            raw = raw.replacingOccurrences(
                of: "\"iterations\":\(VaultCrypto.defaultIterations)",
                with: "\"iterations\":1000"
            )
            try raw.write(to: url, atomically: true, encoding: .utf8)

            do {
                _ = try VaultFile.unlock(at: url, masterPassword: "비밀번호")
                throw SelfTestFailure(message: "반복 횟수를 1000 으로 낮춘 파일이 열렸습니다.")
            } catch VaultError.weakKDFParameters {
                // 기대한 결과.
            }
        }
    }

    static func checkVaultFileRoundTrip() throws {
        try withTemporaryVault { url in
            let item = VaultItem(
                kind: .login,
                title: "지메일",
                username: "someone@example.com",
                password: "긴-비밀번호-1234!",
                urls: ["https://mail.google.com"],
                notes: "메모 줄1\n메모 줄2",
                totp: "JBSWY3DPEHPK3PXP",
                customFields: [CustomField(label: "복구 코드", value: "9999", isSecret: true)],
                tags: ["업무"],
                isFavorite: true
            )

            let vault = try VaultFile.create(at: url, masterPassword: "마스터", document: VaultDocument(items: [item]))
            try vault.save(VaultDocument(items: [item]))

            let (_, loaded) = try VaultFile.unlock(at: url, masterPassword: "마스터")
            try expect(loaded.items.count == 1, "항목 개수가 다릅니다.")

            let restored = loaded.items[0]
            try expect(restored.title == item.title, "제목이 다릅니다.")
            try expect(restored.password == item.password, "비밀번호가 다릅니다.")
            try expect(restored.notes == item.notes, "메모가 다릅니다.")
            try expect(restored.totp == item.totp, "OTP 시크릿이 다릅니다.")
            try expect(restored.customFields.first?.value == "9999", "사용자 지정 필드가 다릅니다.")
            try expect(restored.isFavorite, "즐겨찾기 표시가 사라졌습니다.")

            // 파일 안에 평문이 남아 있으면 안 됩니다.
            let rawFile = try String(contentsOf: url, encoding: .utf8)
            try expect(!rawFile.contains("긴-비밀번호-1234!"), "파일에 비밀번호가 평문으로 들어 있습니다.")
            try expect(!rawFile.contains("someone@example.com"), "파일에 아이디가 평문으로 들어 있습니다.")
        }
    }

    static func checkMasterPasswordChange() throws {
        try withTemporaryVault { url in
            let document = VaultDocument(items: [VaultItem(title: "카드", password: "1234")])
            let vault = try VaultFile.create(at: url, masterPassword: "예전-비밀번호", document: document)

            _ = try VaultFile.changeMasterPassword(vault: vault, document: document, newPassword: "새-비밀번호")

            do {
                _ = try VaultFile.unlock(at: url, masterPassword: "예전-비밀번호")
                throw SelfTestFailure(message: "예전 비밀번호로 아직 열립니다.")
            } catch VaultError.wrongMasterPassword {
                // 기대한 결과.
            }

            let (_, loaded) = try VaultFile.unlock(at: url, masterPassword: "새-비밀번호")
            try expect(loaded.items.first?.title == "카드", "비밀번호를 바꾼 뒤 내용이 사라졌습니다.")
        }
    }

    static func checkGenerator() throws {
        let options = PasswordOptions(length: 24, useSymbols: true, requireEverySelectedSet: true)
        var seen = Set<String>()
        for _ in 0..<20 {
            let password = try PasswordGenerator.makePassword(options)
            try expect(password.count == 24, "길이가 24가 아닙니다. (\(password.count))")
            try expect(password.contains(where: { $0.isLowercase }), "소문자가 없습니다.")
            try expect(password.contains(where: { $0.isUppercase }), "대문자가 없습니다.")
            try expect(password.contains(where: { $0.isNumber }), "숫자가 없습니다.")
            try expect(
                password.contains(where: { PasswordGenerator.symbolSet.contains($0) }),
                "기호가 없습니다."
            )
            seen.insert(password)
        }
        try expect(seen.count == 20, "같은 비밀번호가 두 번 나왔습니다.")

        let ambiguous = PasswordOptions(length: 40, avoidAmbiguous: true)
        let safe = try PasswordGenerator.makePassword(ambiguous)
        try expect(
            !safe.contains(where: { PasswordGenerator.ambiguousCharacters.contains($0) }),
            "헷갈리는 글자를 빼지 못했습니다."
        )
    }

    static func checkWordList() throws {
        let words = WordList.words
        try expect(words.count >= 1000, "단어가 \(words.count)개뿐입니다.")
        try expect(Set(words).count == words.count, "중복된 단어가 있습니다.")

        let phrase = try PasswordGenerator.makePassphrase(PassphraseOptions(wordCount: 6))
        try expect(phrase.split(separator: "-").count == 6, "단어 6개가 나오지 않았습니다.")
        try expect(
            PasswordGenerator.entropyBits(for: PassphraseOptions(wordCount: 6)) > 55,
            "6단어 암구호의 엔트로피가 너무 낮습니다."
        )
    }

    static func checkTOTPVectors() throws {
        // RFC 6238 부록 B 의 SHA-1 시험값. 시크릿은 ASCII "12345678901234567890".
        guard let secret = Base32.decode("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ") else {
            throw SelfTestFailure(message: "Base32 해석에 실패했습니다.")
        }
        try expect(secret == Data("12345678901234567890".utf8), "Base32 결과가 다릅니다.")

        let totp = TOTP(secret: secret, digits: 8, period: 30, algorithm: .sha1)
        let vectors: [(TimeInterval, String)] = [
            (59, "94287082"),
            (1111111109, "07081804"),
            (1111111111, "14050471"),
            (1234567890, "89005924"),
            (2000000000, "69279037"),
        ]
        for (seconds, expected) in vectors {
            let produced = totp.code(at: Date(timeIntervalSince1970: seconds))
            try expect(produced == expected, "t=\(Int(seconds)) 에서 \(expected) 이어야 하는데 \(produced) 가 나왔습니다.")
        }

        guard let parsed = TOTP.parse("otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example&digits=6&period=30") else {
            throw SelfTestFailure(message: "otpauth URI 해석에 실패했습니다.")
        }
        try expect(parsed.issuer == "Example", "issuer 를 읽지 못했습니다.")
        try expect(parsed.account == "alice@example.com", "계정 이름을 읽지 못했습니다.")
        try expect(parsed.code().count == 6, "코드 자리수가 6이 아닙니다.")
    }

    static func checkCSV() throws {
        let text = """
        name,url,username,password,note
        지메일,https://mail.google.com,me@example.com,"쉼표, 포함",첫 줄
        빈칸없음,https://example.com,user2,pw2,"여러
        줄 메모"
        """
        let result = try VaultImporter.importCSV(text)
        try expect(result.items.count == 2, "항목 2개가 나와야 하는데 \(result.items.count)개입니다.")
        try expect(result.items[0].password == "쉼표, 포함", "따옴표 안의 쉼표를 처리하지 못했습니다.")
        try expect(result.items[1].notes.contains("\n"), "따옴표 안의 줄바꿈을 처리하지 못했습니다.")

        // 윈도우·엑셀이 만든 CRLF 파일. 스위프트에서 CRLF 는 한 글자라 따로 확인합니다.
        let windows = "\u{FEFF}name,username,password\r\n가나다,hong,pw1\r\n라마바,kim,pw2\r\n"
        let windowsResult = try VaultImporter.importCSV(windows)
        try expect(windowsResult.items.count == 2, "CRLF 줄바꿈을 처리하지 못했습니다. (\(windowsResult.items.count)개)")
        try expect(windowsResult.items[0].title == "가나다", "CRLF 파일의 첫 항목이 이상합니다.")

        let exported = VaultExporter.csv(for: result.items)
        let reimported = try VaultImporter.importCSV(exported)
        try expect(reimported.items.count == 2, "내보낸 CSV 를 다시 읽지 못했습니다.")
        try expect(reimported.items[0].password == "쉼표, 포함", "왕복 후 비밀번호가 달라졌습니다.")
    }

    // MARK: - 도우미

    static func withTemporaryVault(_ body: (URL) throws -> Void) throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("password-vault-selftest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("vault.pvault")
        try body(url)
    }
}
