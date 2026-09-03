import Foundation
import Security

/// 암호학적으로 안전한 난수.
///
/// `Int.random(in:)` 도 애플 플랫폼에서는 안전하지만, 비밀번호를 만드는 코드에서는
/// 무엇을 쓰는지가 눈에 보여야 해서 `SecRandomCopyBytes` 를 직접 씁니다.
public enum SecureRandom {

    /// 지정한 바이트 수만큼 난수를 만듭니다.
    public static func bytes(_ count: Int) throws -> Data {
        guard count >= 0 else {
            throw VaultError.invalidInput(reason: "난수 길이는 0 이상이어야 합니다.")
        }
        if count == 0 { return Data() }

        var buffer = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &buffer)
        guard status == errSecSuccess else {
            throw VaultError.randomGeneratorFailed(status: status)
        }
        return Data(buffer)
    }

    /// `0 ..< upperBound` 범위의 정수를 치우침 없이 고릅니다.
    ///
    /// 단순히 `난수 % upperBound` 를 쓰면 앞쪽 값이 조금 더 자주 나옵니다(모듈로 편향).
    /// 나누어떨어지지 않는 꼬리 구간을 버리는 방식(rejection sampling)으로 균등하게 만듭니다.
    public static func index(below upperBound: Int) throws -> Int {
        guard upperBound > 0 else {
            throw VaultError.invalidInput(reason: "범위는 1 이상이어야 합니다.")
        }
        guard upperBound <= Int(UInt32.max) else {
            throw VaultError.invalidInput(reason: "범위가 너무 큽니다.")
        }
        if upperBound == 1 { return 0 }

        let n = UInt32(upperBound)
        // 2^32 를 n 으로 나눈 나머지만큼을 위쪽에서 잘라내면 남은 구간이 n 의 배수가 됩니다.
        let excess = ((UInt32.max % n) &+ 1) % n
        let maxAcceptable = UInt32.max &- excess

        var value: UInt32
        repeat {
            value = try uint32()
        } while value > maxAcceptable

        return Int(value % n)
    }

    /// 컬렉션에서 하나를 균등하게 고릅니다.
    public static func element<T>(of items: [T]) throws -> T {
        guard !items.isEmpty else {
            throw VaultError.invalidInput(reason: "고를 수 있는 후보가 없습니다.")
        }
        return items[try index(below: items.count)]
    }

    /// 안전한 난수로 순서를 섞습니다(피셔–예이츠).
    public static func shuffled<T>(_ items: [T]) throws -> [T] {
        var result = items
        guard result.count > 1 else { return result }
        for i in stride(from: result.count - 1, to: 0, by: -1) {
            let j = try index(below: i + 1)
            if i != j { result.swapAt(i, j) }
        }
        return result
    }

    private static func uint32() throws -> UInt32 {
        let raw = [UInt8](try bytes(4))
        return (UInt32(raw[0]) << 24)
            | (UInt32(raw[1]) << 16)
            | (UInt32(raw[2]) << 8)
            | UInt32(raw[3])
    }
}
