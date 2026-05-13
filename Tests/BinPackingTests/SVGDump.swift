@testable import BinPacking
import Foundation
import simd

/// Test-only SVG dumper for visualizing packing results.
///
/// Always writes to `/tmp/swift-bin-packing/<name>.svg` when called.
enum SVGDump {
    static let outputDir = "/tmp/swift-bin-packing"

    static func dump<ID: Hashable & Sendable, Scalar: RectScalar & BinaryFloatingPoint>(_ result: PackingResult<ID, Scalar>, name: String) {
        write(svg(result), name: name)
    }

    static func dump<ID: Hashable & Sendable, Scalar: RectScalar & BinaryInteger>(_ result: PackingResult<ID, Scalar>, name: String) {
        write(svg(result), name: name)
    }

    private static func write(_ svg: String, name: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        let path = "\(outputDir)/\(name).svg"
        try? svg.write(toFile: path, atomically: true, encoding: .utf8)
        FileHandle.standardError.write(Data("[SVGDump] wrote \(path)\n".utf8))
    }

    private static func svg<ID: Hashable & Sendable, Scalar: RectScalar & BinaryInteger>(_ result: PackingResult<ID, Scalar>) -> String {
        render(result: result) { Double(Int64($0)) }
    }

    private static func svg<ID: Hashable & Sendable, Scalar: RectScalar & BinaryFloatingPoint>(_ result: PackingResult<ID, Scalar>) -> String {
        render(result: result) { Double($0) }
    }

    private static func render<ID: Hashable & Sendable, Scalar: RectScalar>(result: PackingResult<ID, Scalar>, toDouble: (Scalar) -> Double) -> String {
        let bw = toDouble(result.binSize.x)
        let bh = toDouble(result.binSize.y)
        var lines: [String] = []
        // Flip y so (0,0) is bottom-left (math convention) rather than SVG's top-left.
        // We do this by mapping packer-y -> bh - packer-y - height for each rect.
        lines.append("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 \(bw) \(bh)' width='\(bw)' height='\(bh)'>")
        lines.append("<rect x='0' y='0' width='\(bw)' height='\(bh)' fill='#f4f4f4' stroke='#888' stroke-width='1'/>")
        for (i, p) in result.placements.enumerated() {
            let x = toDouble(p.rect.minX)
            let w = toDouble(p.rect.size.x)
            let h = toDouble(p.rect.size.y)
            let y = bh - toDouble(p.rect.minY) - h
            let hue = (i * 47) % 360
            let fill = "hsl(\(hue),70%,75%)"
            lines.append("<rect x='\(x)' y='\(y)' width='\(w)' height='\(h)' fill='\(fill)' stroke='#333' stroke-width='0.5'/>")
            let cx = x + w / 2
            let cy = y + h / 2
            let fontSize = Swift.max(6.0, Swift.min(w, h) / 4)
            let label = "\(p.id)\(p.rotated ? "↻" : "")"
            lines.append("<text x='\(cx)' y='\(cy)' font-size='\(fontSize)' text-anchor='middle' dominant-baseline='central' font-family='monospace'>\(label)</text>")
        }
        lines.append("</svg>")
        return lines.joined(separator: "\n")
    }
}
