import AppKit
import Foundation
import UniformTypeIdentifiers
import VaultCore

/// 파일 열기·저장 대화상자.
///
/// SwiftUI 의 `fileImporter` 대신 AppKit 패널을 그대로 씁니다.
/// 맥에서 기대하는 동작(최근 위치 기억, 확장자 처리)이 그대로 나옵니다.
enum FileDialogs {

    static func chooseCSVToImport() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "가져올 CSV 고르기"
        panel.message = "다른 비밀번호 관리자나 브라우저에서 내보낸 CSV 파일을 고르세요."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]

        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseSaveLocation(
        suggestedName: String,
        contentTypes: [UTType],
        message: String
    ) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.message = message
        panel.allowedContentTypes = contentTypes
        panel.canCreateDirectories = true

        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseVaultFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "금고 파일 고르기"
        panel.message = "다른 곳에 있는 .pvault 파일을 고르세요."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowsOtherFileTypes = true
        if let type = UTType(filenameExtension: VaultFile.fileExtension) {
            panel.allowedContentTypes = [type]
        }

        return panel.runModal() == .OK ? panel.url : nil
    }

    /// 오늘 날짜가 붙은 파일 이름을 만듭니다.
    static func datedFileName(prefix: String, extension ext: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(prefix)-\(formatter.string(from: Date())).\(ext)"
    }
}
