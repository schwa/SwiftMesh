import Foundation
import simd
import SwiftMesh

// MARK: - PLY Errors

public enum PLYError: Error, CustomStringConvertible {
    case invalidHeader(String)
    case unsupportedFormat(String)
    case parseError(String)

    public var description: String {
        switch self {
        case .invalidHeader(let msg): "PLY invalid header: \(msg)"
        case .unsupportedFormat(let msg): "PLY unsupported format: \(msg)"
        case .parseError(let msg): "PLY parse error: \(msg)"
        }
    }
}

// MARK: - PLY Reader

public enum PLY {
    /// Read a Mesh from PLY ASCII data.
    ///
    /// Supports vertex positions (x, y, z) and polygon face lists.
    /// Optional vertex normals (nx, ny, nz) are read if present.
    public static func read(from data: Data) throws -> Mesh {
        guard let string = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .utf8) else {
            throw PLYError.parseError("Could not decode data as text")
        }
        return try read(from: string)
    }

    /// Read a Mesh from a PLY ASCII string.
    public static func read(from string: String) throws -> Mesh {
        var lines = string.split(separator: "\n", omittingEmptySubsequences: false).makeIterator()

        // Parse header
        guard let magic = lines.next(), magic.trimmingCharacters(in: .whitespaces) == "ply" else {
            throw PLYError.invalidHeader("Missing 'ply' magic")
        }

        guard let formatLine = lines.next(), formatLine.trimmingCharacters(in: .whitespaces).hasPrefix("format ascii") else {
            throw PLYError.unsupportedFormat("Only ASCII PLY is supported")
        }

        var vertexCount = 0
        var faceCount = 0
        var vertexProperties: [String] = []
        var inVertexElement = false

        while let line = lines.next() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "end_header" {
                break
            }
            if trimmed.hasPrefix("comment") {
                continue
            }
            if trimmed.hasPrefix("element vertex") {
                let parts = trimmed.split(separator: " ")
                guard parts.count >= 3, let count = Int(parts[2]) else {
                    throw PLYError.invalidHeader("Bad vertex element: \(trimmed)")
                }
                vertexCount = count
                inVertexElement = true
                continue
            }
            if trimmed.hasPrefix("element face") {
                let parts = trimmed.split(separator: " ")
                guard parts.count >= 3, let count = Int(parts[2]) else {
                    throw PLYError.invalidHeader("Bad face element: \(trimmed)")
                }
                faceCount = count
                inVertexElement = false
                continue
            }
            if trimmed.hasPrefix("element") {
                inVertexElement = false
                continue
            }
            if trimmed.hasPrefix("property"), inVertexElement {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 3, !trimmed.contains("list") {
                    vertexProperties.append(String(parts.last!))
                }
            }
        }

        // Find property indices
        let xIdx = vertexProperties.firstIndex(of: "x")
        let yIdx = vertexProperties.firstIndex(of: "y")
        let zIdx = vertexProperties.firstIndex(of: "z")
        let nxIdx = vertexProperties.firstIndex(of: "nx")
        let nyIdx = vertexProperties.firstIndex(of: "ny")
        let nzIdx = vertexProperties.firstIndex(of: "nz")

        guard let xIdx, let yIdx, let zIdx else {
            throw PLYError.invalidHeader("Missing x/y/z vertex properties")
        }

        let hasNormals = nxIdx != nil && nyIdx != nil && nzIdx != nil

        // Parse vertices
        var positions: [SIMD3<Float>] = []
        var vertexNormals: [SIMD3<Float>]?
        positions.reserveCapacity(vertexCount)
        if hasNormals {
            vertexNormals = []
            vertexNormals!.reserveCapacity(vertexCount)
        }

        for lineNum in 0..<vertexCount {
            guard let line = lines.next() else {
                throw PLYError.parseError("Unexpected end of file at vertex \(lineNum)")
            }
            let parts = line.split(separator: " ")
            guard parts.count >= vertexProperties.count else {
                throw PLYError.parseError("Not enough values on vertex line \(lineNum)")
            }
            guard let x = Float(parts[xIdx]), let y = Float(parts[yIdx]), let z = Float(parts[zIdx]) else {
                throw PLYError.parseError("Could not parse vertex position at line \(lineNum)")
            }
            positions.append(SIMD3(x, y, z))

            if hasNormals {
                let nx = Float(parts[nxIdx!]) ?? 0
                let ny = Float(parts[nyIdx!]) ?? 0
                let nz = Float(parts[nzIdx!]) ?? 0
                vertexNormals!.append(SIMD3(nx, ny, nz))
            }
        }

        // Parse faces
        var faces: [[Int]] = []
        faces.reserveCapacity(faceCount)

        for lineNum in 0..<faceCount {
            guard let line = lines.next() else {
                throw PLYError.parseError("Unexpected end of file at face \(lineNum)")
            }
            let parts = line.split(separator: " ")
            guard let count = Int(parts.first ?? ""), count >= 3, parts.count >= count + 1 else {
                throw PLYError.parseError("Bad face at line \(lineNum)")
            }
            let indices = (1...count).compactMap { Int(parts[$0]) }
            guard indices.count == count else {
                throw PLYError.parseError("Could not parse face indices at line \(lineNum)")
            }
            faces.append(indices)
        }

        // Build mesh
        let faceDefs = faces.map { HalfEdgeTopology.FaceDefinition(outer: $0) }
        let topology = HalfEdgeTopology(vertexCount: positions.count, faces: faceDefs)

        // Convert per-vertex normals to per-corner normals if present
        var cornerNormals: [SIMD3<Float>]?
        if let vertexNormals {
            cornerNormals = [SIMD3<Float>](repeating: .zero, count: topology.halfEdges.count)
            for he in topology.halfEdges {
                cornerNormals![he.id.raw] = vertexNormals[he.origin.raw]
            }
        }

        return Mesh(topology: topology, positions: positions, normals: cornerNormals)
    }

    /// Write a Mesh to PLY ASCII format.
    public static func write(_ mesh: Mesh) -> Data {
        var output = ""

        let hasNormals = mesh.normals != nil

        // Header
        output += "ply\n"
        output += "format ascii 1.0\n"
        output += "element vertex \(mesh.positions.count)\n"
        output += "property float x\n"
        output += "property float y\n"
        output += "property float z\n"
        if hasNormals {
            output += "property float nx\n"
            output += "property float ny\n"
            output += "property float nz\n"
        }
        output += "element face \(mesh.topology.faces.count)\n"
        output += "property list uchar int vertex_indices\n"
        output += "end_header\n"

        // Vertices
        // For normals, average the per-corner normals back to per-vertex
        var vertexNormals: [SIMD3<Float>]?
        if let normals = mesh.normals {
            var accum = [SIMD3<Float>](repeating: .zero, count: mesh.positions.count)
            var counts = [Int](repeating: 0, count: mesh.positions.count)
            for he in mesh.topology.halfEdges {
                accum[he.origin.raw] += normals[he.id.raw]
                counts[he.origin.raw] += 1
            }
            vertexNormals = accum.enumerated().map { idx, sum in
                counts[idx] > 0 ? simd_normalize(sum) : .zero
            }
        }

        for idx in 0..<mesh.positions.count {
            let pos = mesh.positions[idx]
            output += "\(pos.x) \(pos.y) \(pos.z)"
            if let vertexNormals {
                let n = vertexNormals[idx]
                output += " \(n.x) \(n.y) \(n.z)"
            }
            output += "\n"
        }

        // Faces
        for face in mesh.topology.faces {
            let verts = mesh.topology.vertexLoop(for: face.id)
            output += "\(verts.count)"
            for vid in verts {
                output += " \(vid.raw)"
            }
            output += "\n"
        }

        return Data(output.utf8)
    }
}
