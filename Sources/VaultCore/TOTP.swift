import Foundation
import CryptoKit

/// 2단계 인증(OTP) 코드 생성기. RFC 4226(HOTP) / RFC 6238(TOTP) 구현입니다.
public struct TOTP: Equatable {

    public enum Algorithm: String, Equatable, CaseIterable {
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"
    }

    public var secret: Data
    public var digits: Int
    public var period: Int
    public var algorithm: Algorithm
    public var issuer: String?
    public var account: String?

    public init(
        secret: Data,
        digits: Int = 6,
        period: Int = 30,
        algorithm: Algorithm = .sha1,
        issuer: String? = nil,
        account: String? = nil
    ) {
        self.secret = secret
        self.digits = digits
        self.period = period
        self.algorithm = algorithm
        self.issuer = issuer
        self.account = account
    }

    // MARK: - 코드 만들기

    /// 지정한 시각의 코드. 자리수에 맞춰 앞을 0 으로 채웁니다.
    public func code(at date: Date = Date()) -> String {
        let counter = UInt64(max(0, floor(date.timeIntervalSince1970)) / Double(max(period, 1)))
        return code(counter: counter)
    }

    /// 현재 주기가 끝날 때까지 남은 초.
    public func secondsRemaining(at date: Date = Date()) -> Int {
        let step = Double(max(period, 1))
        let elapsed = max(0, date.timeIntervalSince1970).truncatingRemainder(dividingBy: step)
        return Int((step - elapsed).rounded(.up))
    }

    /// 0.0 ~ 1.0. 진행 표시 원을 그릴 때 씁니다.
    public func progress(at date: Date = Date()) -> Double {
        let step = Double(max(period, 1))
        let elapsed = max(0, date.timeIntervalSince1970).truncatingRemainder(dividingBy: step)
        return min(max(elapsed / step, 0), 1)
    }

    func code(counter: UInt64) -> String {
        var bigEndian = counter.bigEndian
        let counterData = withUnsafeBytes(of: &bigEndian) { Data($0) }
        let key = SymmetricKey(data: secret)

        let mac: [UInt8]
        switch algorithm {
        case .sha1:
            mac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: key))
        case .sha256:
            mac = Array(HMAC<SHA256>.authenticationCode(for: counterData, using: key))
        case .sha512:
            mac = Array(HMAC<SHA512>.authenticationCode(for: counterData, using: key))
        }

        guard mac.count >= 20 else { return String(repeating: "0", count: digits) }

        // RFC 4226 의 동적 절단(dynamic truncation).
        let offset = Int(mac[mac.count - 1] & 0x0f)
        let truncated =
            (UInt32(mac[offset] & 0x7f) << 24) |
            (UInt32(mac[offset + 1]) << 16) |
            (UInt32(mac[offset + 2]) << 8) |
            UInt32(mac[offset + 3])

        // 9자리 이상은 10^n 이 UInt32 를 넘칩니다. 실제로 쓰이지도 않으므로 8 에서 자릅니다.
        let clampedDigits = min(max(digits, 6), 8)
        let modulus = UInt32(pow(10.0, Double(clampedDigits)))
        let value = truncated % modulus

        return String(format: "%0\(clampedDigits)u", value)
    }

    // MARK: - 문자열에서 읽어들이기

    /// 사용자가 붙여넣은 문자열을 해석합니다.
    ///
    /// `otpauth://totp/...` URI 도 되고, 사이트가 보여 주는 Base32 시크릿만 붙여넣어도 됩니다.
    public static func parse(_ raw: String) -> TOTP? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("otpauth://") {
            return parseURI(trimmed)
        }
        guard let secret = Base32.decode(trimmed), !secret.isEmpty else { return nil }
        return TOTP(secret: secret)
    }

    static func parseURI(_ uri: String) -> TOTP? {
        guard let components = URLComponents(string: uri) else { return nil }
        guard components.host?.lowercased() == "totp" else { return nil }

        let queryItems = components.queryItems ?? []
        func value(_ name: String) -> String? {
            queryItems.first { $0.name.lowercased() == name }?.value
        }

        guard let secretString = value("secret"),
              let secret = Base32.decode(secretString),
              !secret.isEmpty
        else { return nil }

        // 경로는 `/Issuer:account` 또는 `/account` 형태입니다.
        var label = components.path
        if label.hasPrefix("/") { label.removeFirst() }
        label = label.removingPercentEncoding ?? label

        var issuer = value("issuer")
        var account: String? = label.isEmpty ? nil : label
        if let separator = label.firstIndex(of: ":") {
            let prefix = String(label[label.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
            let suffix = String(label[label.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if issuer == nil || issuer?.isEmpty == true { issuer = prefix.isEmpty ? nil : prefix }
            account = suffix.isEmpty ? nil : suffix
        }

        let digits = value("digits").flatMap(Int.init) ?? 6
        let period = value("period").flatMap(Int.init) ?? 30
        let algorithm = value("algorithm")
            .flatMap { Algorithm(rawValue: $0.uppercased()) } ?? .sha1

        return TOTP(
            secret: secret,
            digits: min(max(digits, 6), 8),
            period: period > 0 ? period : 30,
            algorithm: algorithm,
            issuer: issuer,
            account: account
        )
    }
}

/// RFC 4648 Base32. OTP 시크릿이 이 형식으로 오갑니다.
public enum Base32 {

    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// 공백·하이픈·소문자·패딩을 모두 너그럽게 받아 줍니다.
    public static func decode(_ string: String) -> Data? {
        var bits = 0
        var accumulator = 0
        var output: [UInt8] = []

        for character in string.uppercased() {
            if character == "=" || character == " " || character == "-" || character == "\n" || character == "\t" {
                continue
            }
            guard let index = alphabet.firstIndex(of: character) else { return nil }
            accumulator = (accumulator << 5) | index
            bits += 5
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((accumulator >> bits) & 0xff))
            }
        }

        // 남은 비트는 패딩이어야 하므로 0 이 아니면 잘못된 입력입니다.
        if bits > 0 && (accumulator & ((1 << bits) - 1)) != 0 { return nil }

        return Data(output)
    }

    public static func encode(_ data: Data) -> String {
        var bits = 0
        var accumulator = 0
        var output = ""

        for byte in data {
            accumulator = (accumulator << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                output.append(alphabet[(accumulator >> bits) & 0x1f])
            }
        }
        if bits > 0 {
            output.append(alphabet[(accumulator << (5 - bits)) & 0x1f])
        }
        while output.count % 8 != 0 {
            output.append("=")
        }
        return output
    }
}
