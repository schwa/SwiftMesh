import Foundation
import simd
import SwiftMesh

// MARK: - PLY Errors

/// Errors from reading PLY data.
public enum PLYError: Error, CustomStringConvertible {
    /// The header is missing or malformed.
    case invalidHeader(String)
    /// The `format` line names an encoding other than ASCII or binary.
    case unsupportedFormat(String)
    /// The body doesn't match the header (bad value or early end of data).
    case parseError(String)

    public var description: String {
        switch self {
        case .invalidHeader(let msg): "PLY invalid header: \(msg)"
        case .unsupportedFormat(let msg): "PLY unsupported format: \(msg)"
        case .parseError(let msg): "PLY parse error: \(msg)"
        }
    }
}

// MARK: - PLY

/// Reads and writes Stanford PLY meshes (ASCII and binary).
public enum PLY {
    /// PLY body encoding.
    public enum Format: Sendable {
        case ascii
        case binaryLittleEndian
        case binaryBigEndian
    }

    /// Read a Mesh from PLY data (ASCII or binary, either endianness).
    ///
    /// Reads vertex positions (x, y, z), optional vertex normals (nx, ny, nz), and
    /// polygon faces (`vertex_indices` or `vertex_index`). Other elements and
    /// properties are skipped.
    public static func read(from data: Data) throws -> Mesh {
        let bytes = [UInt8](data)
        let (header, bodyStart) = try parseHeader(bytes)
        var reader: any ValueReader = switch header.format {
        case .ascii: try ASCIIReader(bytes: bytes[bodyStart...])
        case .binaryLittleEndian: BinaryReader(bytes: bytes, offset: bodyStart, bigEndian: false)
        case .binaryBigEndian: BinaryReader(bytes: bytes, offset: bodyStart, bigEndian: true)
        }

        var positions: [SIMD3<Float>] = []
        var vertexNormals: [SIMD3<Float>]?
        var faces: [[Int]] = []

        for element in header.elements {
            switch element.name {
            case "vertex":
                let names = element.properties.map(\.name)
                guard let x = names.firstIndex(of: "x"), let y = names.firstIndex(of: "y"), let z = names.firstIndex(of: "z") else {
                    throw PLYError.invalidHeader("Missing x/y/z vertex properties")
                }
                let normalIndices = ["nx", "ny", "nz"].compactMap { names.firstIndex(of: $0) }
                positions.reserveCapacity(element.count)
                if normalIndices.count == 3 {
                    vertexNormals = []
                    vertexNormals!.reserveCapacity(element.count)
                }
                for index in 0..<element.count {
                    var values = [Double](repeating: 0, count: element.properties.count)
                    for (slot, property) in element.properties.enumerated() {
                        if let listTypes = property.list {
                            let count = try reader.read(listTypes.count, context: "vertex \(index)")
                            for _ in 0..<Int(count) {
                                _ = try reader.read(listTypes.item, context: "vertex \(index)")
                            }
                        } else {
                            values[slot] = try reader.read(property.type, context: "vertex \(index)")
                        }
                    }
                    positions.append(SIMD3(Float(values[x]), Float(values[y]), Float(values[z])))
                    if normalIndices.count == 3 {
                        vertexNormals!.append(SIMD3(Float(values[normalIndices[0]]), Float(values[normalIndices[1]]), Float(values[normalIndices[2]])))
                    }
                }

            case "face":
                guard let indexProperty = element.properties.firstIndex(where: { ($0.name == "vertex_indices" || $0.name == "vertex_index") && $0.list != nil }) else {
                    throw PLYError.invalidHeader("Missing vertex_indices face property")
                }
                faces.reserveCapacity(element.count)
                for index in 0..<element.count {
                    for (slot, property) in element.properties.enumerated() {
                        if let listTypes = property.list {
                            let count = Int(try reader.read(listTypes.count, context: "face \(index)"))
                            var items: [Int] = []
                            items.reserveCapacity(count)
                            for _ in 0..<count {
                                items.append(Int(try reader.read(listTypes.item, context: "face \(index)")))
                            }
                            if slot == indexProperty {
                                guard count >= 3 else {
                                    throw PLYError.parseError("Bad face \(index): \(count) vertices")
                                }
                                faces.append(items)
                            }
                        } else {
                            _ = try reader.read(property.type, context: "face \(index)")
                        }
                    }
                }

            default:
                try reader.skip(element)
            }
        }

        let topology = HalfEdgeTopology(vertexCount: positions.count, faces: faces.map { HalfEdgeTopology.FaceDefinition(outer: $0) })
        let cornerNormals = vertexNormals.map { normals in topology.halfEdges.map { normals[$0.origin.raw] } }
        return Mesh(topology: topology, positions: positions, normals: cornerNormals)
    }

    /// Read a Mesh from a PLY ASCII string.
    public static func read(from string: String) throws -> Mesh {
        try read(from: Data(string.utf8))
    }

    /// Write a Mesh to PLY.
    ///
    /// Per-corner normals are averaged to per-vertex normals. Faces are written as
    /// `uchar`-counted `int` index lists.
    public static func write(_ mesh: Mesh, format: Format = .ascii) -> Data {
        var vertexNormals: [SIMD3<Float>]?
        if let normals = mesh.normals {
            var sums = [SIMD3<Float>](repeating: .zero, count: mesh.positions.count)
            for halfEdge in mesh.topology.halfEdges {
                sums[halfEdge.origin.raw] += normals[halfEdge.id.raw]
            }
            vertexNormals = sums.map { simd_length($0) > 0 ? simd_normalize($0) : .zero }
        }
        let faces = mesh.topology.faces.filter { $0.edge != nil }.map { mesh.topology.vertexLoop(for: $0.id) }

        let formatName = switch format {
        case .ascii: "ascii"
        case .binaryLittleEndian: "binary_little_endian"
        case .binaryBigEndian: "binary_big_endian"
        }
        var header = "ply\nformat \(formatName) 1.0\n"
        header += "element vertex \(mesh.positions.count)\n"
        header += "property float x\nproperty float y\nproperty float z\n"
        if vertexNormals != nil {
            header += "property float nx\nproperty float ny\nproperty float nz\n"
        }
        header += "element face \(faces.count)\n"
        header += "property list uchar int vertex_indices\n"
        header += "end_header\n"

        if format == .ascii {
            var output = header
            for index in mesh.positions.indices {
                let position = mesh.positions[index]
                output += "\(position.x) \(position.y) \(position.z)"
                if let normal = vertexNormals?[index] {
                    output += " \(normal.x) \(normal.y) \(normal.z)"
                }
                output += "\n"
            }
            for face in faces {
                output += "\(face.count)" + face.map { " \($0.raw)" }.joined() + "\n"
            }
            return Data(output.utf8)
        }

        let bigEndian = format == .binaryBigEndian
        var output = Data(header.utf8)
        func append(_ value: Float) {
            let bits = bigEndian ? value.bitPattern.bigEndian : value.bitPattern.littleEndian
            withUnsafeBytes(of: bits) { output.append(contentsOf: $0) }
        }
        func append(_ value: Int32) {
            let ordered = bigEndian ? value.bigEndian : value.littleEndian
            withUnsafeBytes(of: ordered) { output.append(contentsOf: $0) }
        }
        for index in mesh.positions.indices {
            let position = mesh.positions[index]
            append(position.x)
            append(position.y)
            append(position.z)
            if let normal = vertexNormals?[index] {
                append(normal.x)
                append(normal.y)
                append(normal.z)
            }
        }
        for face in faces {
            output.append(UInt8(clamping: face.count))
            for vertex in face {
                append(Int32(vertex.raw))
            }
        }
        return output
    }
}

// MARK: - Header

private enum ScalarType {
    case int8, uint8, int16, uint16, int32, uint32, float32, float64

    init?(_ name: Substring) {
        switch name {
        case "char", "int8": self = .int8
        case "uchar", "uint8": self = .uint8
        case "short", "int16": self = .int16
        case "ushort", "uint16": self = .uint16
        case "int", "int32": self = .int32
        case "uint", "uint32": self = .uint32
        case "float", "float32": self = .float32
        case "double", "float64": self = .float64
        default: return nil
        }
    }

    var size: Int {
        switch self {
        case .int8, .uint8: 1
        case .int16, .uint16: 2
        case .int32, .uint32, .float32: 4
        case .float64: 8
        }
    }
}

private struct Property {
    var name: String
    var type: ScalarType
    var list: (count: ScalarType, item: ScalarType)?
}

private struct Element {
    var name: String
    var count: Int
    var properties: [Property] = []
}

private struct Header {
    var format: PLY.Format
    var elements: [Element]
}

/// Parse the ASCII header; returns it and the byte offset where the body starts.
private func parseHeader(_ bytes: [UInt8]) throws -> (Header, Int) {
    let marker = Array("end_header".utf8)
    guard let markerStart = (0...max(0, bytes.count - marker.count)).first(where: { bytes[$0..<($0 + marker.count)].elementsEqual(marker) }) else {
        throw PLYError.invalidHeader("Missing end_header")
    }
    var bodyStart = markerStart + marker.count
    while bodyStart < bytes.count, bytes[bodyStart] == UInt8(ascii: "\r") || bytes[bodyStart] == UInt8(ascii: " ") {
        bodyStart += 1
    }
    if bodyStart < bytes.count, bytes[bodyStart] == UInt8(ascii: "\n") {
        bodyStart += 1
    }
    let text = String(decoding: bytes[0..<markerStart], as: UTF8.self)
    let lines = text.split(whereSeparator: \.isNewline).map { $0.split(whereSeparator: \.isWhitespace) }
    guard lines.first == ["ply"] else {
        throw PLYError.invalidHeader("Missing 'ply' magic")
    }

    var format: PLY.Format?
    var elements: [Element] = []
    for parts in lines.dropFirst() where !parts.isEmpty {
        switch parts[0] {
        case "format":
            guard parts.count >= 2 else {
                throw PLYError.invalidHeader("Bad format line")
            }
            switch parts[1] {
            case "ascii": format = .ascii
            case "binary_little_endian": format = .binaryLittleEndian
            case "binary_big_endian": format = .binaryBigEndian
            default: throw PLYError.unsupportedFormat(String(parts[1]))
            }

        case "element":
            guard parts.count >= 3, let count = Int(parts[2]) else {
                throw PLYError.invalidHeader("Bad element: \(parts.joined(separator: " "))")
            }
            elements.append(Element(name: String(parts[1]), count: count))

        case "property":
            guard !elements.isEmpty else {
                throw PLYError.invalidHeader("Property before element")
            }
            if parts.count >= 5, parts[1] == "list", let count = ScalarType(parts[2]), let item = ScalarType(parts[3]) {
                elements[elements.count - 1].properties.append(Property(name: String(parts[4]), type: item, list: (count, item)))
            } else if parts.count >= 3, let type = ScalarType(parts[1]) {
                elements[elements.count - 1].properties.append(Property(name: String(parts[2]), type: type))
            } else {
                throw PLYError.invalidHeader("Bad property: \(parts.joined(separator: " "))")
            }

        default:
            continue // comment, obj_info
        }
    }
    guard let format else {
        throw PLYError.invalidHeader("Missing format line")
    }
    return (Header(format: format, elements: elements), bodyStart)
}

// MARK: - Body readers

private protocol ValueReader {
    mutating func read(_ type: ScalarType, context: @autoclosure () -> String) throws -> Double
}

extension ValueReader {
    fileprivate mutating func skip(_ element: Element) throws {
        for index in 0..<element.count {
            for property in element.properties {
                if let list = property.list {
                    let count = Int(try read(list.count, context: "\(element.name) \(index)"))
                    for _ in 0..<count {
                        _ = try read(list.item, context: "\(element.name) \(index)")
                    }
                } else {
                    _ = try read(property.type, context: "\(element.name) \(index)")
                }
            }
        }
    }
}

/// ASCII bodies are whitespace-separated tokens; line breaks carry no meaning beyond separation.
private struct ASCIIReader: ValueReader {
    var tokens: [Substring]
    var position = 0

    init(bytes: ArraySlice<UInt8>) {
        tokens = String(decoding: bytes, as: UTF8.self).split(whereSeparator: \.isWhitespace)
    }

    mutating func read(_: ScalarType, context: @autoclosure () -> String) throws -> Double {
        guard position < tokens.count else {
            throw PLYError.parseError("Unexpected end of file at \(context())")
        }
        defer { position += 1 }
        guard let value = Double(tokens[position]) else {
            throw PLYError.parseError("Could not parse '\(tokens[position])' at \(context())")
        }
        return value
    }
}

private struct BinaryReader: ValueReader {
    var bytes: [UInt8]
    var offset: Int
    var bigEndian: Bool

    mutating func read(_ type: ScalarType, context: @autoclosure () -> String) throws -> Double {
        guard offset + type.size <= bytes.count else {
            throw PLYError.parseError("Unexpected end of file at \(context())")
        }
        defer { offset += type.size }
        switch type {
        case .int8: return Double(Int8(bitPattern: bytes[offset]))
        case .uint8: return Double(bytes[offset])
        case .int16: return Double(Int16(bitPattern: ordered(UInt16.self)))
        case .uint16: return Double(ordered(UInt16.self))
        case .int32: return Double(Int32(bitPattern: ordered(UInt32.self)))
        case .uint32: return Double(ordered(UInt32.self))
        case .float32: return Double(Float(bitPattern: ordered(UInt32.self)))
        case .float64: return Float64(bitPattern: ordered(UInt64.self))
        }
    }

    /// Assemble an unsigned integer from the file's byte order.
    private func ordered<T: FixedWidthInteger & UnsignedInteger>(_: T.Type) -> T {
        var value: T = 0
        let size = MemoryLayout<T>.size
        for index in 0..<size {
            let byte = T(bytes[offset + (bigEndian ? size - 1 - index : index)])
            value |= byte << (8 * index)
        }
        return value
    }
}
