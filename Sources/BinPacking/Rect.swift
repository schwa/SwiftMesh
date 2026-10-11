import simd

/// A scalar type usable as a coordinate in `Rect`.
///
/// Conformed to by `Int`, `Float`, `Double` (and other `SIMDScalar` numerics).
public protocol RectScalar: SIMDScalar, Numeric, Comparable, Hashable, Sendable, Codable where SIMD2Storage: Sendable, SIMD4Storage: Sendable, SIMD8Storage: Sendable, SIMD16Storage: Sendable, SIMD32Storage: Sendable, SIMD64Storage: Sendable, SIMDMaskScalar: Hashable {}

extension Int: RectScalar {}
extension Int32: RectScalar {}
extension Int64: RectScalar {}
extension Float: RectScalar {}
extension Double: RectScalar {}

/// An axis-aligned rectangle backed by SIMD vectors.
///
/// `origin` is the minimum corner (top-left in image / bottom-left in math conventions —
/// the packer is convention-agnostic, it just allocates regions).
public struct Rect<Scalar: RectScalar>: Hashable, Sendable {
    /// The minimum corner.
    public var origin: SIMD2<Scalar>
    /// Width and height. Expected to be non-negative.
    public var size: SIMD2<Scalar>

    public init(origin: SIMD2<Scalar>, size: SIMD2<Scalar>) {
        self.origin = origin
        self.size = size
    }

    public init(x: Scalar, y: Scalar, width: Scalar, height: Scalar) {
        self.origin = SIMD2(x, y)
        self.size = SIMD2(width, height)
    }

    /// Creates a rectangle of the given size at the origin.
    public init(size: SIMD2<Scalar>) {
        self.origin = SIMD2(repeating: .zero)
        self.size = size
    }

    public var width: Scalar { size.x }
    public var height: Scalar { size.y }
    public var minX: Scalar { origin.x }
    public var minY: Scalar { origin.y }
    public var maxX: Scalar { origin.x + size.x }
    public var maxY: Scalar { origin.y + size.y }
    /// The maximum corner (`origin + size`).
    public var max: SIMD2<Scalar> { SIMD2(maxX, maxY) }

    public var area: Scalar { size.x * size.y }

    /// Whether `other` lies entirely inside this rectangle. Shared edges count as inside.
    public func contains(_ other: Self) -> Bool {
        other.minX >= minX && other.minY >= minY && other.maxX <= maxX && other.maxY <= maxY
    }

    /// Whether the rectangles overlap with positive area. Touching edges don't count.
    public func intersects(_ other: Self) -> Bool {
        !(other.minX >= maxX || other.maxX <= minX || other.minY >= maxY || other.maxY <= minY)
    }
}
