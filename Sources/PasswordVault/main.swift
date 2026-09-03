import Foundation
import VaultCore

// 앱의 시작 지점.
//
// `--selftest` 로 실행하면 창을 띄우지 않고 자체 검사만 돌린 뒤 종료합니다.
// CI 가 이 결과로 배포 여부를 정합니다.
if CommandLine.arguments.contains("--selftest") {
    exit(SelfTest.run() ? 0 : 1)
}

if CommandLine.arguments.contains("--version") {
    print("비밀번호 금고 \(AppInfo.version) (\(AppInfo.build))")
    exit(0)
}

if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    print("""
    비밀번호 금고 \(AppInfo.version)

    옵션 없이 실행하면 창이 열립니다.

      --selftest   창 없이 자체 검사만 실행합니다(개발·배포 검증용).
      --version    버전을 출력합니다.
      --help       이 도움말을 출력합니다.

    금고 파일 위치: \(VaultFile.defaultURL().path)
    """)
    exit(0)
}

VaultApp.main()
