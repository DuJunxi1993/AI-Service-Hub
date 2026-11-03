#!/usr/bin/env swift
//
// 生成 macOS 应用图标（.iconset → .icns）
//
// 用法：
//   swift scripts/make-icon.swift <源PNG> <输出.iconset目录>
//
// 产物是一套常规尺寸的图标（10 个），供 iconutil 打包成 .icns。
//
// 注意：macOS 的 app 图标**不会**按系统明暗自动切换 ——
// asset catalog 里的 "luminosity: dark" 对 app icon 是空操作（actool 会静默丢弃）。
// 所以浅色/深色要生成两套独立的 .icns：
//   - 一套作为 bundle 图标（Finder / 未运行时），放进 Contents/Resources
//   - 另一套在运行时通过 NSApp.applicationIconImage 切换（运行中的 Dock 图标）
//
// 形状用 macOS 的圆角方形（squircle，超椭圆 n≈5），
// 占比约 84% —— 与系统自带 app 实测一致（Calculator 83.6%、DSHShell 84.4%）。
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - 参数

struct SizeEntry {
    let name: String
    let pixels: Int
}

/// 完整 iconset 需要的尺寸
let sizes: [SizeEntry] = [
    .init(name: "icon_16x16", pixels: 16),
    .init(name: "icon_16x16@2x", pixels: 32),
    .init(name: "icon_32x32", pixels: 32),
    .init(name: "icon_32x32@2x", pixels: 64),
    .init(name: "icon_128x128", pixels: 128),
    .init(name: "icon_128x128@2x", pixels: 256),
    .init(name: "icon_256x256", pixels: 256),
    .init(name: "icon_256x256@2x", pixels: 512),
    .init(name: "icon_512x512", pixels: 512),
    .init(name: "icon_512x512@2x", pixels: 1024),
]

/// 形状占画布的比例（与系统 app 实测一致）
let contentRatio: CGFloat = 0.84

/// 超椭圆指数：n=5 逼近 macOS 的 squircle
let squircleExponent: CGFloat = 5.0

// MARK: - 工具

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("错误：\(message)\n".utf8))
    exit(1)
}

func loadImage(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fail("无法读取图片：\(path)")
    }
    return image
}

/// macOS 圆角方形（squircle）路径
func squirclePath(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let centerX = rect.midX
    let centerY = rect.midY
    let a = rect.width / 2
    let b = rect.height / 2
    let exponent = squircleExponent
    let steps = 512

    for index in 0...steps {
        let t = CGFloat(index) / CGFloat(steps) * 2 * .pi
        let cosT = cos(t)
        let sinT = sin(t)
        // 超椭圆参数方程
        let x = centerX + a * copysign(pow(abs(cosT), 2 / exponent), cosT)
        let y = centerY + b * copysign(pow(abs(sinT), 2 / exponent), sinT)
        if index == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

/// 渲染一个尺寸：把原图缩放铺满形状区域，再用 squircle 裁切
func render(source: CGImage, pixels: Int) -> CGImage? {
    let side = CGFloat(pixels)
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.clear(CGRect(x: 0, y: 0, width: side, height: side))
    context.interpolationQuality = .high

    // 形状区域（居中）
    let content = side * contentRatio
    let shapeRect = CGRect(
        x: (side - content) / 2,
        y: (side - content) / 2,
        width: content,
        height: content
    )

    context.saveGState()
    context.addPath(squirclePath(in: shapeRect))
    context.clip()
    // 原图缩放铺满**形状区域**（而不是整个画布）——
    // 否则图形超出形状的部分会被圆角裁掉（A 的两条腿曾被切掉）
    context.draw(source, in: shapeRect)
    context.restoreGState()

    return context.makeImage()
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else {
        fail("无法创建 PNG 输出：\(path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fail("写入 PNG 失败：\(path)")
    }
}

// MARK: - 主流程

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fail("用法：swift make-icon.swift <源PNG> <输出.iconset目录>")
}

let sourcePath = arguments[1]
let outputDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)

let sourceImage = loadImage(sourcePath)

try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for entry in sizes {
    guard let image = render(source: sourceImage, pixels: entry.pixels) else {
        fail("渲染失败：\(entry.name)")
    }
    writePNG(image, to: outputDirectory.appendingPathComponent("\(entry.name).png").path)
}

print("已生成 \(sizes.count) 个文件 → \(outputDirectory.path)")
