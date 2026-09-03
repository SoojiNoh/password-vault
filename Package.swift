// swift-tools-version: 5.7
import PackageDescription

// 비밀번호 금고 (macOS)
//
// - VaultCore     : 암호화 · 파일 형식 · 생성기 · TOTP 등 UI 와 무관한 로직 (테스트 대상)
// - PasswordVault : SwiftUI 앱 실행 파일
//
// Xcode 프로젝트 파일 없이 명령줄 도구(Xcode Command Line Tools)만으로 빌드됩니다.
// 실제 `.app` 번들 조립은 Scripts/build-app.sh 가 합니다.
let package = Package(
    name: "PasswordVault",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PasswordVault", targets: ["PasswordVault"]),
        .library(name: "VaultCore", targets: ["VaultCore"]),
    ],
    targets: [
        .target(name: "VaultCore"),
        .executableTarget(
            name: "PasswordVault",
            dependencies: ["VaultCore"]
        ),
        .testTarget(
            name: "VaultCoreTests",
            dependencies: ["VaultCore"]
        ),
    ]
)
