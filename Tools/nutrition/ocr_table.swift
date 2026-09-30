// 用 macOS 內建的 Vision 文字辨識讀表格圖片或 PDF，依位置排回一列一列，輸出 JSON。
// 用法：swift ocr_table.swift 圖片或PDF [更多檔案…]
// 輸出：[{"file": "...", "page": 1, "rows": [["品名", "熱量", ...], ...]}]

import AppKit
import Foundation
import PDFKit
import Vision

struct Cell {
    let text: String
    let box: CGRect
}

func images(from path: String) -> [CGImage] {
    let url = URL(fileURLWithPath: path)
    if url.pathExtension.lowercased() == "pdf", let document = PDFDocument(url: url) {
        return (0..<document.pageCount).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 3
            let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
            let image = page.thumbnail(of: size, for: .mediaBox)
            return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
    }
    guard let image = NSImage(contentsOf: url) else { return [] }
    return [image.cgImage(forProposedRect: nil, context: nil, hints: nil)].compactMap { $0 }
}

func recognize(_ image: CGImage) -> [Cell] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hant", "en-US"]
    request.usesLanguageCorrection = false
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([request])
    return (request.results ?? []).compactMap { observation in
        guard let text = observation.topCandidates(1).first?.string else { return nil }
        return Cell(text: text, box: observation.boundingBox)
    }
}

/// 中心點高度差不多的格子算同一列，由左到右排
func rows(from cells: [Cell]) -> [[String]] {
    let sorted = cells.sorted { $0.box.midY > $1.box.midY }
    var groups: [[Cell]] = []
    for cell in sorted {
        if let last = groups.last, let reference = last.first,
           abs(reference.box.midY - cell.box.midY) < max(reference.box.height, cell.box.height) * 0.55 {
            groups[groups.count - 1].append(cell)
        } else {
            groups.append([cell])
        }
    }
    return groups.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text) }
}

var output: [[String: Any]] = []
for path in CommandLine.arguments.dropFirst() {
    for (index, image) in images(from: path).enumerated() {
        output.append(["file": path, "page": index + 1, "rows": rows(from: recognize(image))])
    }
}
let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted])
FileHandle.standardOutput.write(data)
