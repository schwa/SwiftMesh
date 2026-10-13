import simd

/// A scalar type usable as a coordinate in `Rect`.
///
/// Conformed to by `Int`, `Float`, `Double` (and other `SIMDScalar` numerics).
package protocol RectScalar: SIMDScalar, Numeric, Comparable, Hashable, Sendable, Codable where SIMD2Storage: Sendable, SIMD4Storage: Sendable, SIMD8Storage: Sendable, SIMD16Storage: Sendable, SIMD32Storage: Sendable, SIMD64Storage: Sendable, SIMDMaskScalar: Hashable {}

extension Int: RectScalar {}
extension Int32: RectScalar {}
extension Int64: RectScalar {}
extension Float: RectScalar {}
extension Double: RectScalar {}

/// An axis-aligned rectangle backed by SIMD vectors.
///
/// `origin` is the minimum corner (top-left in image / bottom-left in math conventions —
/// the packer is convention-agnostic, it just allocates regions).
package struct Rect<Scalar: RectScalar>: Hashable, Sendable {
    /// The minimum corner.
    package var origin: SIMD2<Scalar>
    /// Width and height. Expected to be non-negative.
    package var size: SIMD2<Scalar>

    package init(origin: SIMD2<Scalar>, size: SIMD2<Scalar>) {
        self.origin = origin
        self.size = size
    }

    package init(x: Scalar, y: Scalar, width: Scalar, height: Scalar) {
        self.origin = SIMD2(x, y)
        self.size = SIMD2(width, height)
    }

    /// Creates a rectangle of the given size at the origin.
    package init(size: SIMD2<Scalar>) {
        self.origin = SIMD2(repeating: .zero)
        self.size = size
    }

    package var width: Scalar { size.x }
    package var height: Scalar { size.y }
    package var minX: Scalar { origin.x }
    package var minY: Scalar { origin.y }
    package var maxX: Scalar { origin.x + size.x }
    package var maxY: Scalar { origin.y + size.y }
    /// The maximum corner (`origin + size`).
    package var max: SIMD2<Scalar> { SIMD2(maxX, maxY) }

    package var area: Scalar { size.x * size.y }

    /// Whether `other` lies entirely inside this rectangle. Shared edges count as inside.
    package func contains(_ other: Self) -> Bool {
        other.minX >= minX && other.minY >= minY && other.maxX <= maxX && other.maxY <= maxY
    }

    /// Whether the rectangles overlap with positive area. Touching edges don't count.
    package func intersects(_ other: Self) -> Bool {
        !(other.minX >= maxX || other.maxX <= minX || other.minY >= maxY || other.maxY <= minY)
    }
}
