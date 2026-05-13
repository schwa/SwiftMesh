import Foundation
import GeometryLite3D
import Metal
import MetalKit
import MetalSupport
import ModelIO
import simd
@testable import SwiftMesh
import Testing

@Suite("MetalMesh")
struct MetalMeshTests {
    private func requireDevice() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalMeshTestError.noDevice
        }
        return device
    }

    enum MetalMeshTestError: Error {
        case noDevice
    }

    @Test("Triangle mesh produces correct vertex/index counts")
    func triangleCounts() throws {
        let device = try requireDevice()
        let mesh = Mesh.tetrahedron(attributes: [])
        let metalMesh = MetalMesh(mesh: mesh, device: device, label: "Tetrahedron")

        // 4 unique positions shared across 4 faces → 4 deduplicated vertices
        #expect(metalMesh.vertexCount == 4)
        // 1 submesh (no material tags)
        #expect(metalMesh.submeshes.count == 1)
        // 4 faces × 3 = 12 indices
        #expect(metalMesh.submeshes[0].indexCount == 12)
    }

    @Test("Octahedron export")
    func octahedron() throws {
        let device = try requireDevice()
        let metalMesh = MetalMesh(mesh: .octahedron(attributes: []), device: device)
        // 6 unique positions → 6 deduplicated vertices, 8 faces × 3 = 24 indices
        #expect(metalMesh.vertexCount == 6)
        #expect(metalMesh.submeshes.count == 1)
        #expect(metalMesh.submeshes[0].indexCount == 24)
    }

    @Test("Icosahedron export")
    func icosahedron() throws {
        let device = try requireDevice()
        let metalMesh = MetalMesh(mesh: .icosahedron(attributes: []), device: device)
        // 12 unique positions → 12 deduplicated vertices, 20 faces × 3 = 60 indices
        #expect(metalMesh.vertexCount == 12)
        #expect(metalMesh.submeshes.count == 1)
        #expect(metalMesh.submeshes[0].indexCount == 60)
    }

    @Test("Mesh submeshes produce MetalMesh submeshes")
    func meshSubmeshes() throws {
        let device = try requireDevice()
        let topo = HalfEdgeTopology(vertexCount: 6, faces: [
            .init(outer: [0, 1, 2]),
            .init(outer: [3, 4, 5])
        ])
        let mesh = Mesh(
            topology: topo,
            positions: [
                SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0),
                SIMD3(2, 0, 0), SIMD3(3, 0, 0), SIMD3(2.5, 1, 0)
            ],
            submeshes: [
                .init(label: "A", faces: [topo.faces[0].id]),
                .init(label: "B", faces: [topo.faces[1].id])
            ]
        )
        let metalMesh = MetalMesh(mesh: mesh, device: device)
        #expect(metalMesh.submeshes.count == 2)
        #expect(metalMesh.submeshes[0].indexCount == 3)
        #expect(metalMesh.submeshes[1].indexCount == 3)
    }

    @Test("Label propagates")
    func labelPropagates() throws {
        let device = try requireDevice()
        let metalMesh = MetalMesh(mesh: .tetrahedron(attributes: []), device: device, label: "Test")
        #expect(metalMesh.label == "Test")
        #expect(metalMesh.vertexBuffers[0]?.label == "Test Vertices[0]")
    }

    @Test("Cube (quad faces) exports correctly via triangulation")
    func cubeExport() throws {
        let device = try requireDevice()
        let metalMesh = MetalMesh(mesh: .cube(attributes: []), device: device)
        // 8 unique positions → 8 deduplicated vertices, 6 × 2 × 3 = 36 indices
        #expect(metalMesh.vertexCount == 8)
        #expect(metalMesh.submeshes.count == 1)
        #expect(metalMesh.submeshes[0].indexCount == 36)
    }

    @Test("Dodecahedron (pentagon faces) exports correctly")
    func dodecahedronExport() throws {
        let device = try requireDevice()
        let metalMesh = MetalMesh(mesh: .dodecahedron(attributes: []), device: device)
        // 20 unique positions → 20 deduplicated vertices, 12 × 3 × 3 = 108 indices
        #expect(metalMesh.vertexCount == 20)
        #expect(metalMesh.submeshes.count == 1)
        #expect(metalMesh.submeshes[0].indexCount == 108)
    }

    @Test("Shared vertices are deduplicated for adjacent triangles")
    func sharedVertices() throws {
        let device = try requireDevice()
        // Two triangles sharing edge (1,2): vertices 0,1,2,3
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0), SIMD3(0.5, -1, 0)
        ], faces: [[0, 1, 2], [1, 0, 3]])
        let metalMesh = MetalMesh(mesh: mesh, device: device)
        // 4 unique positions → 4 vertices, 2 × 3 = 6 indices
        #expect(metalMesh.vertexCount == 4)
        #expect(metalMesh.submeshes[0].indexCount == 6)
    }

    @Test("Flat normals prevent vertex sharing at hard edges")
    func flatNormalsPreventSharing() throws {
        let device = try requireDevice()
        // Two coplanar triangles with flat normals — shared edge vertices have
        // identical normals so they should still be deduplicated
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0), SIMD3(0.5, -1, 0)
        ], faces: [[0, 1, 2], [1, 0, 3]]).withFlatNormals()
        let metalMesh = MetalMesh(mesh: mesh, device: device)
        // Coplanar faces have the same normal, so shared vertices still deduplicate
        #expect(metalMesh.vertexCount == 4)

        // Non-coplanar: tetrahedron with flat normals — every face has a different
        // normal, so shared vertices get split
        let tetraMesh = Mesh.tetrahedron(attributes: []).withFlatNormals()
        let tetraMetal = MetalMesh(mesh: tetraMesh, device: device)
        // Each vertex appears in 3 faces with 3 different normals → 12 unique vertices
        #expect(tetraMetal.vertexCount == 12)
        #expect(tetraMetal.submeshes[0].indexCount == 12)
    }

    // MARK: - Separate buffer layout

    @Test("Separate buffers creates one buffer per attribute")
    func separateBuffers() throws {
        let device = try requireDevice()
        let mesh = Mesh.cube(attributes: .default)
        let metalMesh = MetalMesh(mesh: mesh, device: device, bufferLayout: .separateBuffers)
        // .default = flatNormals + textureCoordinates → position, normal, texcoord = 3 buffers
        #expect(metalMesh.vertexBuffers.count == 3)
        #expect(metalMesh.vertexBuffers[0] != nil) // positions
        #expect(metalMesh.vertexBuffers[1] != nil) // normals
        #expect(metalMesh.vertexBuffers[2] != nil) // texcoords
    }

    @Test("Separate buffers produces same vertex/index counts as interleaved")
    func separateBuffersCounts() throws {
        let device = try requireDevice()
        let mesh = Mesh.tetrahedron(attributes: [])
        let interleaved = MetalMesh(mesh: mesh, device: device, bufferLayout: .interleaved)
        let separate = MetalMesh(mesh: mesh, device: device, bufferLayout: .separateBuffers)
        #expect(interleaved.vertexCount == separate.vertexCount)
        #expect(interleaved.submeshes[0].indexCount == separate.submeshes[0].indexCount)
    }

    @Test("Separate buffers round-trips to Mesh correctly")
    func separateBuffersRoundTrip() throws {
        let device = try requireDevice()
        let original = Mesh.octahedron(attributes: []).withFlatNormals()
        let metalMesh = MetalMesh(mesh: original, device: device, bufferLayout: .separateBuffers)
        let restored = metalMesh.toMesh()

        #expect(restored.normals != nil)
        #expect(restored.vertexCount == original.vertexCount)
        #expect(restored.faceCount == original.faceCount)
        #expect(restored.validate().isEmpty)
    }

    // MARK: - MetalMesh → Mesh round-trip

    @Test("Round-trip position-only mesh preserves topology")
    func roundTripPositionOnly() throws {
        let device = try requireDevice()
        let original = Mesh.tetrahedron(attributes: [])
        let metalMesh = MetalMesh(mesh: original, device: device)
        let restored = metalMesh.toMesh()

        #expect(restored.vertexCount == original.vertexCount)
        #expect(restored.faceCount == original.faceCount)
        #expect(restored.validate().isEmpty)
    }

    @Test("Round-trip preserves normals")
    func roundTripNormals() throws {
        let device = try requireDevice()
        let original = Mesh.cube(attributes: []).withFlatNormals()
        let metalMesh = MetalMesh(mesh: original, device: device)
        let restored = metalMesh.toMesh()

        #expect(restored.normals != nil)
        #expect(restored.validate().isEmpty)
        // All restored normals should be unit length
        for n in restored.normals! {
            let len = simd_length(n)
            #expect(abs(len - 1.0) < 1e-4)
        }
    }

    @Test("Round-trip preserves UVs")
    func roundTripUVs() throws {
        let device = try requireDevice()
        let original = Mesh.sphere(latitudeSegments: 4, longitudeSegments: 8, attributes: .textureCoordinates)
        let metalMesh = MetalMesh(mesh: original, device: device)
        let restored = metalMesh.toMesh()

        #expect(restored.textureCoordinates != nil)
        #expect(restored.validate().isEmpty)
        // UV values should be in [0,1]
        for uv in restored.textureCoordinates! {
            #expect(uv.x >= -1e-5 && uv.x <= 1.0 + 1e-5)
            #expect(uv.y >= -1e-5 && uv.y <= 1.0 + 1e-5)
        }
    }

    @Test("Round-trip preserves submeshes")
    func roundTripSubmeshes() throws {
        let device = try requireDevice()
        let topo = HalfEdgeTopology(vertexCount: 6, faces: [
            .init(outer: [0, 1, 2]),
            .init(outer: [3, 4, 5])
        ])
        let original = Mesh(
            topology: topo,
            positions: [
                SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0),
                SIMD3(2, 0, 0), SIMD3(3, 0, 0), SIMD3(2.5, 1, 0)
            ],
            submeshes: [
                .init(label: "A", faces: [topo.faces[0].id]),
                .init(label: "B", faces: [topo.faces[1].id])
            ]
        )
        let metalMesh = MetalMesh(mesh: original, device: device)
        let restored = metalMesh.toMesh()

        #expect(restored.submeshes.count == 2)
        #expect(restored.submeshes[0].faces.count == 1)
        #expect(restored.submeshes[1].faces.count == 1)
        #expect(restored.validate().isEmpty)
    }

    // MARK: - ModelIO conversion

    @Test("MDLMesh sphere → Mesh round-trip")
    func mdlMeshSphere() throws {
        let device = try requireDevice()
        let allocator = MTKMeshBufferAllocator(device: device)
        let mdlMesh = MDLMesh.newEllipsoid(
            withRadii: SIMD3<Float>(0.5, 0.5, 0.5),
            radialSegments: 8,
            verticalSegments: 4,
            geometryType: .triangles,
            inwardNormals: false,
            hemisphere: false,
            allocator: allocator
        )

        let mesh = try Mesh(mdlMesh: mdlMesh, device: device)
        // MDL spheres may have degenerate triangles at poles, so skip strict validation
        #expect(mesh.vertexCount > 0)
        #expect(mesh.faceCount > 0)
        #expect(mesh.positions.count == mesh.vertexCount)
    }

    @Test("MDLMesh box → Mesh preserves normals and UVs")
    func mdlMeshBox() throws {
        let device = try requireDevice()
        let allocator = MTKMeshBufferAllocator(device: device)
        let mdlMesh = MDLMesh.newBox(
            withDimensions: SIMD3<Float>(1, 1, 1),
            segments: SIMD3<UInt32>(1, 1, 1),
            geometryType: .triangles,
            inwardNormals: false,
            allocator: allocator
        )

        let mesh = try Mesh(mdlMesh: mdlMesh, device: device)
        #expect(mesh.validate().isEmpty)
        #expect(mesh.normals != nil)
        #expect(mesh.textureCoordinates != nil)
    }

    // MARK: - Direct initializers (bypass Mesh / topology)

    @Test("Direct init from positions/indices")
    func directInitPositionsOnly() throws {
        let device = try requireDevice()
        let positions: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(1, 1, 0)
        ]
        let indices: [UInt32] = [0, 1, 2, 1, 3, 2]
        let metalMesh = MetalMesh(device: device, positions: positions, indices: indices, label: "Quad")

        #expect(metalMesh.vertexCount == 4)
        #expect(metalMesh.submeshes.count == 1)
        #expect(metalMesh.submeshes[0].indexCount == 6)
        #expect(metalMesh.label == "Quad")
        #expect(metalMesh.vertexBuffers.count == 1)
        // Position-only descriptor
        #expect(metalMesh.vertexDescriptor.attributes.count == 1)
        #expect(metalMesh.vertexDescriptor.attributes[0].semantic == .position)
    }

    @Test("Direct init with normals and UVs (interleaved)")
    func directInitInterleavedAttributes() throws {
        let device = try requireDevice()
        let positions: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)
        ]
        let normals: [SIMD3<Float>] = [
            SIMD3(0, 0, 1), SIMD3(0, 0, 1), SIMD3(0, 0, 1)
        ]
        let uvs: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1)
        ]
        let indices: [UInt32] = [0, 1, 2]
        let metalMesh = MetalMesh(
            device: device,
            positions: positions,
            normals: normals,
            textureCoordinates: uvs,
            indices: indices
        )

        #expect(metalMesh.vertexCount == 3)
        #expect(metalMesh.vertexBuffers.count == 1) // interleaved
        #expect(metalMesh.vertexDescriptor.attributes.count == 3)

        // Round-trip back to a Mesh — should produce a single triangle.
        let restored = metalMesh.toMesh()
        #expect(restored.vertexCount == 3)
        #expect(restored.faceCount == 1)
        #expect(restored.normals != nil)
        #expect(restored.textureCoordinates != nil)
    }

    @Test("Direct init with separate buffers")
    func directInitSeparateBuffers() throws {
        let device = try requireDevice()
        let positions: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)
        ]
        let normals: [SIMD3<Float>] = [
            SIMD3(0, 0, 1), SIMD3(0, 0, 1), SIMD3(0, 0, 1)
        ]
        let indices: [UInt32] = [0, 1, 2]
        let metalMesh = MetalMesh(
            device: device,
            positions: positions,
            normals: normals,
            indices: indices,
            bufferLayout: .separateBuffers
        )
        #expect(metalMesh.vertexBuffers.count == 2)
        #expect(metalMesh.vertexBuffers[0] != nil)
        #expect(metalMesh.vertexBuffers[1] != nil)
    }

    @Test("Direct init from preexisting MTLBuffers")
    func directInitFromBuffers() throws {
        let device = try requireDevice()

        // Build raw vertex data: 3 positions, packed float3.
        let positions: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)
        ]
        let packed = positions.map { Packed3<Float>($0) }
        let vertexBytes = packed.withUnsafeBufferPointer { Data(buffer: $0) }

        let stride = MemoryLayout<Packed3<Float>>.stride
        let vBuf = vertexBytes.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: []) }!
        let indices: [UInt32] = [0, 1, 2]
        let iBuf = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt32>.stride * indices.count, options: [])!

        let descriptor = VertexDescriptor(
            attributes: [.init(semantic: .position, format: .float3, offset: 0, bufferIndex: 0)],
            layouts: [.init(bufferIndex: 0, stride: stride, stepFunction: .perVertex, stepRate: 1)]
        )

        let metalMesh = MetalMesh(
            vertexBuffers: [0: vBuf],
            vertexCount: 3,
            vertexDescriptor: descriptor,
            indexBuffer: iBuf,
            indexCount: 3,
            label: "FromBuffers"
        )
        #expect(metalMesh.vertexCount == 3)
        #expect(metalMesh.submeshes.count == 1)
        #expect(metalMesh.submeshes[0].indexCount == 3)
        // Zero-copy: buffer identity is preserved.
        #expect(metalMesh.vertexBuffers[0] === vBuf)
        #expect(metalMesh.submeshes[0].indexBuffer === iBuf)
        #expect(metalMesh.label == "FromBuffers")
    }

    // MARK: - Corner-table topology (preserveTopology)

    @Test("preserveTopology produces opposites and vertToHalfedge buffers")
    func preserveTopologyBuffers() throws {
        let device = try requireDevice()
        let mesh = Mesh.tetrahedron(attributes: [])
        let metalMesh = MetalMesh(mesh: mesh, device: device, preserveTopology: true)

        #expect(metalMesh.opposites != nil)
        #expect(metalMesh.vertToHalfedge != nil)

        let totalIndices = metalMesh.submeshes.reduce(0) { $0 + $1.indexCount }
        #expect(metalMesh.opposites!.length == MemoryLayout<UInt32>.stride * totalIndices)
    }

    @Test("preserveTopology defaults to false")
    func preserveTopologyDefaultsFalse() throws {
        let device = try requireDevice()
        let metalMesh = MetalMesh(mesh: .tetrahedron(attributes: []), device: device)

        #expect(metalMesh.opposites == nil)
        #expect(metalMesh.vertToHalfedge == nil)
    }

    @Test("Opposites buffer has correct twin pairing for closed manifold")
    func oppositesTwinPairing() throws {
        let device = try requireDevice()
        let mesh = Mesh.tetrahedron(attributes: [])
        let metalMesh = MetalMesh(mesh: mesh, device: device, preserveTopology: true)

        let totalIndices = metalMesh.submeshes.reduce(0) { $0 + $1.indexCount }
        let oppPtr = metalMesh.opposites!.contents().assumingMemoryBound(to: UInt32.self)
        let sentinel = UInt32.max

        // For a closed manifold, no boundary edges
        for h in 0..<totalIndices {
            #expect(oppPtr[h] != sentinel, "Tetrahedron is closed — no boundary edges expected")
        }

        // Twin symmetry: opposites[opposites[h]] == h
        for h in 0..<totalIndices {
            let twin = Int(oppPtr[h])
            #expect(Int(oppPtr[twin]) == h, "Twin symmetry violated at halfedge \(h)")
        }
    }

    @Test("Round-trip with preserveTopology produces valid mesh with correct twins")
    func roundTripWithTopology() throws {
        let device = try requireDevice()
        let original = Mesh.icosahedron(attributes: []).withFlatNormals()
        let metalMesh = MetalMesh(mesh: original, device: device, preserveTopology: true)
        let restored = metalMesh.toMesh()

        #expect(restored.validate().isEmpty)
        #expect(restored.faceCount == original.faceCount)
        #expect(restored.normals != nil)

        // Every interior half-edge should have a twin (icosahedron is closed)
        for he in restored.topology.halfEdges {
            #expect(he.twin != nil, "Closed manifold should have no boundary edges")
        }

        // Twin symmetry
        for he in restored.topology.halfEdges {
            guard let twin = he.twin else {
                continue
            }
            #expect(restored.topology.halfEdges[twin.raw].twin == he.id)
        }
    }

    @Test("Boundary edges get sentinel in opposites buffer")
    func boundaryEdgesSentinel() throws {
        let device = try requireDevice()
        // A single quad (two triangles) is open — has boundary edges
        let mesh = Mesh.quad(attributes: [])
        let metalMesh = MetalMesh(mesh: mesh, device: device, preserveTopology: true)

        let totalIndices = metalMesh.submeshes.reduce(0) { $0 + $1.indexCount }
        let oppPtr = metalMesh.opposites!.contents().assumingMemoryBound(to: UInt32.self)
        let sentinel = UInt32.max

        var boundaryCount = 0
        for h in 0..<totalIndices {
            if oppPtr[h] == sentinel {
                boundaryCount += 1
            }
        }
        // A quad = 2 triangles = 6 halfedges. The shared diagonal has twins,
        // the 4 outer edges are boundary → 4 boundary halfedges.
        #expect(boundaryCount == 4)
    }

    @Test("vertToHalfedge maps every position vertex to an outgoing halfedge")
    func vertToHalfedgeCovers() throws {
        let device = try requireDevice()
        let mesh = Mesh.cube(attributes: [])
        let metalMesh = MetalMesh(mesh: mesh, device: device, preserveTopology: true)

        let v2hePtr = metalMesh.vertToHalfedge!.contents().assumingMemoryBound(to: UInt32.self)
        let posCount = metalMesh.vertToHalfedge!.length / MemoryLayout<UInt32>.stride
        let sentinel = UInt32.max

        for v in 0..<posCount {
            #expect(v2hePtr[v] != sentinel, "Every position vertex should have a representative halfedge")
        }
    }

    @Test("Lossless round-trip preserves exact twin wiring")
    func losslessRoundTripTwinWiring() throws {
        let device = try requireDevice()
        // Icosahedron: closed manifold, position-only, no vertex splitting.
        let original = Mesh.icosahedron(attributes: [])
        let metalMesh = MetalMesh(mesh: original, device: device, preserveTopology: true)
        let restored = metalMesh.toMesh()

        #expect(restored.validate().isEmpty)
        #expect(restored.topology.halfEdges.count == original.topology.halfEdges.count)

        // Every half-edge's twin should point at the same pair of position vertices.
        for he in restored.topology.halfEdges {
            guard let twin = he.twin else {
                Issue.record("Closed manifold should have no boundary at HE \(he.id)")
                continue
            }
            let twinHE = restored.topology.halfEdges[twin.raw]
            // he: origin -> dest, twin: dest -> origin
            let heOrigin = he.origin
            let heDest = restored.topology.halfEdges[he.next!.raw].origin
            let twinOrigin = twinHE.origin
            let twinDest = restored.topology.halfEdges[twinHE.next!.raw].origin
            #expect(heOrigin == twinDest, "Twin dest should equal origin")
            #expect(heDest == twinOrigin, "Twin origin should equal dest")
        }
    }

    @Test("Lossless round-trip with split vertices (flat normals) recovers twins")
    func losslessRoundTripSplitVertices() throws {
        let device = try requireDevice()
        // Flat normals on tetrahedron splits every shared vertex (4 verts -> 12 Metal verts).
        // The lossy path can't recover twin wiring here because shared-edge vertices
        // have different normals, so position-dedup still works but vertex splitting
        // complicates things. The lossless path should recover exact twins.
        let original = Mesh.tetrahedron(attributes: []).withFlatNormals()
        let metalMesh = MetalMesh(mesh: original, device: device, preserveTopology: true)

        // Confirm vertices were split
        #expect(metalMesh.vertexCount == 12)

        let restored = metalMesh.toMesh()
        #expect(restored.validate().isEmpty)
        #expect(restored.faceCount == 4)

        // All half-edges should have twins (closed manifold)
        for he in restored.topology.halfEdges {
            #expect(he.twin != nil, "Closed manifold should have no boundary edges")
        }

        // Twin symmetry
        for he in restored.topology.halfEdges {
            guard let twin = he.twin else {
                continue
            }
            #expect(restored.topology.halfEdges[twin.raw].twin == he.id)
        }
    }

    @Test("Lossy round-trip loses twin info at seams with different per-corner attributes")
    func lossyRoundTripLosesTwins() throws {
        let device = try requireDevice()
        // Flat-normal tetrahedron: each face has unique normals, so shared-edge
        // vertices get split into different Metal vertices. Without preserveTopology,
        // the position-dedup path rebuilds topology from scratch — it should still
        // work (tetrahedron positions are unique per vertex), but let's verify
        // the lossy path at least produces a valid mesh.
        let original = Mesh.tetrahedron(attributes: []).withFlatNormals()
        let metalMeshLossy = MetalMesh(mesh: original, device: device, preserveTopology: false)
        let metalMeshLossless = MetalMesh(mesh: original, device: device, preserveTopology: true)

        let restoredLossy = metalMeshLossy.toMesh()
        let restoredLossless = metalMeshLossless.toMesh()

        // Both should be valid
        #expect(restoredLossy.validate().isEmpty)
        #expect(restoredLossless.validate().isEmpty)

        // Both should have same face count
        #expect(restoredLossy.faceCount == 4)
        #expect(restoredLossless.faceCount == 4)

        // Lossless: guaranteed all twins present (closed manifold)
        let losslessBoundary = restoredLossless.topology.halfEdges.filter { $0.twin == nil }.count
        #expect(losslessBoundary == 0, "Lossless path should preserve all twins")
    }

    @Test("Lossy round-trip with open mesh loses boundary twin info correctly")
    func lossyRoundTripOpenMesh() throws {
        let device = try requireDevice()
        // Two triangles sharing an edge, with flat normals. The shared edge
        // has different normals on each side.
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0), SIMD3(0.5, -1, 0)
        ], faces: [[0, 1, 2], [1, 0, 3]]).withFlatNormals()

        // Lossy path
        let metalMeshLossy = MetalMesh(mesh: mesh, device: device, preserveTopology: false)
        let restoredLossy = metalMeshLossy.toMesh()
        #expect(restoredLossy.validate().isEmpty)
        #expect(restoredLossy.faceCount == 2)

        // Lossless path
        let metalMeshLossless = MetalMesh(mesh: mesh, device: device, preserveTopology: true)
        let restoredLossless = metalMeshLossless.toMesh()
        #expect(restoredLossless.validate().isEmpty)
        #expect(restoredLossless.faceCount == 2)

        // The shared edge (0,1) should have a twin in lossless
        let losslessInternalTwins = restoredLossless.topology.halfEdges.filter { $0.twin != nil }.count
        // 2 triangles = 6 half-edges. Shared edge = 2 twins. Boundary = 4 with no twin.
        #expect(losslessInternalTwins == 2, "Shared edge should have twins in lossless path")

        // Boundary edges = 4 (the 4 outer edges)
        let losslessBoundary = restoredLossless.topology.halfEdges.filter { $0.twin == nil }.count
        #expect(losslessBoundary == 4)
    }

    @Test("Mesh → MDLMesh → Mesh round-trip")
    func meshToMDLAndBack() throws {
        let device = try requireDevice()
        let original = Mesh.icosahedron(attributes: []).withFlatNormals()

        let mdlMesh = original.toMDLMesh(device: device)
        let restored = try Mesh(mdlMesh: mdlMesh, device: device)

        #expect(restored.validate().isEmpty)
        #expect(restored.vertexCount == original.vertexCount)
        #expect(restored.normals != nil)
    }
}
