import Foundation
import VaultCore

/// 크롬 확장 ↔ 이 앱을 잇는 다리.
///
/// 구조는 이렇습니다.
///
/// ```
/// 크롬 확장  ──(네이티브 메시징, 표준입출력)──▶  PasswordVault --native-host
///                                                        │  유닉스 소켓
///                                                        ▼
///                                            실행 중인 금고 앱 (잠금 해제 상태에서만 응답)
/// ```
///
/// 비밀번호를 다루므로 아래를 지킵니다.
/// - 소켓은 사용자 홈 안에, 권한 `0600` 으로 만듭니다. 다른 계정은 열 수 없습니다.
/// - **잠겨 있으면 아무것도 내주지 않습니다.** 키가 메모리에 없으니 애초에 읽을 수도 없습니다.
/// - 금고 전체를 넘기지 않습니다. 물어본 주소에 해당하는 항목만 골라 보냅니다.
/// - 채워 넣는 것은 사람이 목록에서 고른 뒤에만 일어납니다(확장 쪽 규칙).
enum AutofillBridge {

    static let protocolVersion = 1

    /// 소켓 경로. 금고 파일과 같은 폴더(`0700`)에 둡니다.
    static func socketURL() -> URL {
        VaultFile.defaultDirectory().appendingPathComponent("autofill.sock")
    }
}

// MARK: - 주고받는 형식

struct AutofillRequest: Decodable {
    var op: String
    var url: String?
}

struct AutofillCandidate: Encodable {
    var id: String
    var title: String
    var username: String
    var password: String
}

struct AutofillResponse: Encodable {
    var ok: Bool
    var locked: Bool = false
    var items: [AutofillCandidate] = []
    var error: String?
}

// MARK: - 앱 안에서 도는 소켓 서버

/// 잠금이 풀려 있는 동안에만 떠 있는 아주 작은 서버.
final class AutofillServer {

    /// 요청이 오면 이 함수로 항목을 물어봅니다. 잠겨 있으면 `nil` 을 돌려주세요.
    private let lookup: (String) -> [VaultItem]?

    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "vault.autofill", qos: .userInitiated)

    init(lookup: @escaping (String) -> [VaultItem]?) {
        self.lookup = lookup
    }

    var isRunning: Bool { listenFD >= 0 }

    func start() {
        guard listenFD < 0 else { return }
        let url = AutofillBridge.socketURL()
        let path = url.path

        // 유닉스 소켓 경로는 104자 제한이 있습니다. 넘으면 조용히 포기합니다.
        guard path.utf8.count < 104 else { return }

        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        unlink(path)   // 지난번에 남은 소켓 파일 정리

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { p in
            path.withCString { s in
                strncpy(UnsafeMutableRawPointer(p).assumingMemoryBound(to: CChar.self), s, 103)
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bound == 0, listen(fd, 4) == 0 else { close(fd); return }

        // 나만 열 수 있게.
        chmod(path, 0o600)

        listenFD = fd
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptOne() }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        unlink(AutofillBridge.socketURL().path)
    }

    deinit { stop() }

    /// 앱이 끝날 때 소켓 파일을 지웁니다. 남아 있어도 다음 실행에서 지우고 새로 만들지만,
    /// 쓰지도 않는 파일을 굳이 남길 이유가 없습니다.
    static func removeStaleSocket() {
        unlink(AutofillBridge.socketURL().path)
    }

    private func acceptOne() {
        let client = accept(listenFD, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }

        guard let line = readLine(fd: client), let data = line.data(using: .utf8) else { return }

        var response = AutofillResponse(ok: false, error: "잘못된 요청입니다.")
        if let req = try? JSONDecoder().decode(AutofillRequest.self, from: data) {
            switch req.op {
            case "ping":
                response = AutofillResponse(ok: true)
            case "lookup":
                let url = req.url ?? ""
                // lookup 은 앱 상태를 읽으므로 메인 큐에서 돌립니다.
                var found: [VaultItem]?
                DispatchQueue.main.sync { found = self.lookup(url) }
                if let items = found {
                    response = AutofillResponse(ok: true, items: items.map {
                        AutofillCandidate(id: $0.id.uuidString,
                                          title: $0.displayTitle,
                                          username: $0.username,
                                          password: $0.password)
                    })
                } else {
                    response = AutofillResponse(ok: true, locked: true)
                }
            default:
                response = AutofillResponse(ok: false, error: "모르는 요청입니다.")
            }
        }

        if var out = try? JSONEncoder().encode(response) {
            out.append(0x0A)
            out.withUnsafeBytes { _ = write(client, $0.baseAddress, out.count) }
        }
    }

    /// 줄바꿈까지 한 줄 읽습니다. 요청이 짧으므로 상한을 둡니다.
    private func readLine(fd: Int32, limit: Int = 64 * 1024) -> String? {
        var buf = [UInt8]()
        var byte: UInt8 = 0
        while buf.count < limit {
            let n = read(fd, &byte, 1)
            if n <= 0 { break }
            if byte == 0x0A { break }
            buf.append(byte)
        }
        guard !buf.isEmpty else { return nil }
        return String(bytes: buf, encoding: .utf8)
    }
}

// MARK: - `--native-host` 모드

/// 크롬이 직접 띄우는 모드. 표준입출력 ↔ 유닉스 소켓을 그대로 이어 줍니다.
///
/// 크롬의 네이티브 메시징은 `4바이트 길이(리틀엔디언) + JSON` 형식입니다.
enum AutofillNativeHost {

    static func run() -> Never {
        let input = FileHandle.standardInput
        let output = FileHandle.standardOutput

        while true {
            guard let header = try? input.read(upToCount: 4), header.count == 4 else { break }
            let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
            // 크롬 규격상 한 번에 64MB 를 넘지 않습니다. 말도 안 되는 값이면 끊습니다.
            guard length > 0, length <= 1_000_000 else { break }
            guard let body = try? input.read(upToCount: Int(length)), body.count == Int(length) else { break }

            let reply = forward(body) ?? Data(#"{"ok":false,"error":"금고 앱이 실행 중이 아닙니다."}"#.utf8)

            var out = Data()
            withUnsafeBytes(of: UInt32(reply.count).littleEndian) { out.append(contentsOf: $0) }
            out.append(reply)
            output.write(out)
        }
        exit(0)
    }

    /// 소켓으로 한 번 물어보고 답을 그대로 돌려줍니다.
    private static func forward(_ body: Data) -> Data? {
        let path = AutofillBridge.socketURL().path
        guard path.utf8.count < 104 else { return nil }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { p in
            path.withCString { s in
                strncpy(UnsafeMutableRawPointer(p).assumingMemoryBound(to: CChar.self), s, 103)
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let ok = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
        }
        guard ok == 0 else { return nil }

        var request = body
        request.append(0x0A)
        let sent = request.withUnsafeBytes { write(fd, $0.baseAddress, request.count) }
        guard sent > 0 else { return nil }

        var out = Data()
        var byte: UInt8 = 0
        while out.count < 1_000_000 {
            let n = read(fd, &byte, 1)
            if n <= 0 { break }
            if byte == 0x0A { break }
            out.append(byte)
        }
        return out.isEmpty ? nil : out
    }
}
