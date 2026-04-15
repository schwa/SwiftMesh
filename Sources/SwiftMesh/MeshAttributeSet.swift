/// Attributes that a mesh primitive can generate during construction.
public struct MeshAttributes: OptionSet, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    /// Generate flat (per-face) normals.
    public static let flatNormals = MeshAttributes(rawValue: 1 << 0)

    /// Generate smooth (averaged) normals.
    public static let smoothNormals = MeshAttributes(rawValue: 1 << 1)

    /// Generate texture coordinates.
    public static let textureCoordinates = MeshAttributes(rawValue: 1 << 2)

    /// Generate tangents (requires both normals and texture coordinates).
    public static let tangents = MeshAttributes(rawValue: 1 << 3)

    /// Generate bitangents (requires both normals and texture coordinates).
    public static let bitangents = MeshAttributes(rawValue: 1 << 4)

    /// Invert normals (face inward). Requires `.flatNormals` or `.smoothNormals`.
    public static let invertedNormals = MeshAttributes(rawValue: 1 << 5)

    public static let `default`: MeshAttributes = [.flatNormals, .textureCoordinates]

    public static let `all`: MeshAttributes = [.flatNormals, .textureCoordinates, .tangents, .bitangents]

    /// Validate that the requested combination is legal.
    /// Calls `fatalError` for programmer errors.
    internal func validate() {
        if contains(.flatNormals), contains(.smoothNormals) {
            fatalError("MeshAttributes: cannot request both .flatNormals and .smoothNormals")
        }
        let hasNormals = !isDisjoint(with: [.flatNormals, .smoothNormals])
        if contains(.tangents), !hasNormals || !contains(.textureCoordinates) {
            fatalError("MeshAttributes: .tangents requires normals (.flatNormals or .smoothNormals) and .textureCoordinates")
        }
        if contains(.bitangents), !hasNormals || !contains(.textureCoordinates) {
            fatalError("MeshAttributes: .bitangents requires normals (.flatNormals or .smoothNormals) and .textureCoordinates")
        }
        if contains(.invertedNormals), !hasNormals {
            fatalError("MeshAttributes: .invertedNormals requires .flatNormals or .smoothNormals")
        }
    }
}

internal extension Mesh {
    /// Apply derived attributes (normals, tangents, bitangents) based on the requested set.
    /// Texture coordinates must already be assigned by the primitive before calling this.
    mutating func applyAttributes(_ attributes: MeshAttributes) {
        attributes.validate()

        if attributes.contains(.flatNormals) {
            self = withFlatNormals()
        } else if attributes.contains(.smoothNormals) {
            self = withSmoothNormals()
        }

        if attributes.contains(.invertedNormals), var existingNormals = normals {
            for i in existingNormals.indices {
                existingNormals[i] = -existingNormals[i]
            }
            normals = existingNormals
        }

        if attributes.contains(.tangents) || attributes.contains(.bitangents) {
            let withTB = withTangents()
            if attributes.contains(.tangents) {
                tangents = withTB.tangents
            }
            if attributes.contains(.bitangents) {
                bitangents = withTB.bitangents
            }
        }
    }
}
