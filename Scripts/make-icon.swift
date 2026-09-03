#!/usr/bin/env swift

// 앱 아이콘 PNG(1024×1024)를 그립니다.
//
// build-app.sh 가 부르고, 결과를 sips/iconutil 로 .icns 로 만듭니다.
// 실패해도 앱 빌드는 계속됩니다(아이콘만 기본값이 됩니다).

import AppKit
import Foundation

func reportFailure(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    reportFailure("사용법: make-icon.swift <출력.png>")
    exit(1)
}

let outputPath = arguments[1]
let side: CGFloat = 1024
let image = NSImage(size: NSSize(width: side, height: side))

image.lockFocus()

// 1. 둥근 사각형 바탕에 세로 그러데이션.
//    macOS 아이콘은 가장자리에 여백을 조금 두는 것이 관례입니다.
let inset = side * 0.085
let plate = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
let corner = plate.width * 0.225
let platePath = NSBezierPath(roundedRect: plate, xRadius: corner, yRadius: corner)

let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.29, green: 0.52, blue: 0.96, alpha: 1),
    NSColor(srgbRed: 0.16, green: 0.28, blue: 0.72, alpha: 1),
])
gradient?.draw(in: platePath, angle: -90)

// 2. 가운데 자물쇠 기호를 흰색으로.
if let symbol = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil) {
    let configured = symbol.withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: side * 0.5, weight: .regular)
    ) ?? symbol

    let glyphSize = configured.size
    if glyphSize.width > 0 && glyphSize.height > 0 {
        // 기호를 따로 그린 뒤 흰색으로 덧칠합니다. 바탕까지 물들이지 않기 위해서입니다.
        let tinted = NSImage(size: glyphSize)
        tinted.lockFocus()
        configured.draw(in: NSRect(origin: .zero, size: glyphSize))
        NSColor.white.set()
        NSRect(origin: .zero, size: glyphSize).fill(using: .sourceAtop)
        tinted.unlockFocus()

        let target = NSRect(
            x: (side - glyphSize.width) / 2,
            y: (side - glyphSize.height) / 2,
            width: glyphSize.width,
            height: glyphSize.height
        )
        tinted.draw(in: target, from: .zero, operation: .sourceOver, fraction: 0.96)
    }
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else {
    reportFailure("아이콘을 PNG 로 바꾸지 못했습니다.")
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: outputPath))
} catch {
    reportFailure("아이콘을 저장하지 못했습니다: \(error.localizedDescription)")
    exit(1)
}
