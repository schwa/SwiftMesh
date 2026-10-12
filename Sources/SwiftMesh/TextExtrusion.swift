import CoreGraphics
import CoreText
import Foundation

public extension Mesh {
    /// Extrude a string into a solid using the glyph outlines of `font`.
    ///
    /// The text is laid out on one line with its baseline on y = 0, reading along +x with
    /// y up. Units are the font's points; scale the mesh afterwards for other sizes.
    /// Glyph holes (e.g. in "o") become holes in the caps. Outlines are classified with
    /// the even-odd rule, so fonts that rely on overlapping contours may render overlaps
    /// as holes.
    static func extrudedText(_ string: String, font: CTFont, depth: Float, mode: ExtrusionMode = .solid, curveSegments: Int = 6, attributes: MeshAttributes = .default) -> Mesh {
        extruded(textPath(string, font: font), depth: depth, mode: mode, curveSegments: curveSegments, attributes: attributes)
    }

    /// Extrude a string using a font looked up by name and size. See ``extrudedText(_:font:depth:mode:curveSegments:attributes:)``.
    static func extrudedText(_ string: String, fontName: String = "Helvetica", size: CGFloat = 1, depth: Float, mode: ExtrusionMode = .solid, curveSegments: Int = 6, attributes: MeshAttributes = .default) -> Mesh {
        extrudedText(string, font: CTFontCreateWithName(fontName as CFString, size, nil), depth: depth, mode: mode, curveSegments: curveSegments, attributes: attributes)
    }
}

private extension Mesh {
    /// Glyph outlines at their laid-out positions, flipped to screen (y-down) coordinates
    /// because `extruded(_:)` flips y back.
    static func textPath(_ string: String, font: CTFont) -> CGPath {
        let attributed = NSAttributedString(string: string, attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
        let line = CTLineCreateWithAttributedString(attributed)
        let path = CGMutablePath()
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let runAttributes = CTRunGetAttributes(run) as NSDictionary
            // swiftlint:disable:next force_cast
            let runFont = runAttributes[kCTFontAttributeName] as! CTFont? ?? font
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for index in 0..<count {
                var transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: positions[index].x, y: positions[index].y)
                if let glyphPath = CTFontCreatePathForGlyph(runFont, glyphs[index], &transform) {
                    path.addPath(glyphPath)
                }
            }
        }
        return path
    }
}
