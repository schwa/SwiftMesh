# SwiftMesh

Mesh data structures and operations for Swift. Half-edge topology, n-gon faces, SoA attributes, Metal export.

## Quick start

```swift
import SwiftMesh

// Build a mesh
let mesh = Mesh.cube

// Generate normals and UVs
let prepared = mesh
    .withSmoothNormals()
    .withSphericalUVs()

// Export to Metal
let metalMesh = MetalMesh(mesh: prepared, device: device)
encoder.draw(metalMesh)
```

## What's in the box

**`HalfEdgeTopology`** — half-edge wiring with no geometry attached. Adjacency queries, validation, boundary detection, edge deletion.

**`Mesh`** — topology paired with vertex positions and optional per-corner attributes (normals, UVs, tangents, colors). Faces can be any size. Submeshes group faces for multi-material rendering.

**`MetalMesh`** — GPU-ready export. Triangulates n-gon faces, splits vertices per-corner, packs attributes into Metal buffers.

**`SwiftMeshIO`** — PLY file import/export (ASCII).

## Shape primitives

```swift
Mesh.tetrahedron    // 4 faces
Mesh.cube           // 6 quad faces
Mesh.octahedron     // 8 faces
Mesh.icosahedron    // 20 faces
Mesh.dodecahedron   // 12 pentagon faces

Mesh.sphere()       // UV sphere with configurable segments
Mesh.torus()        // configurable major/minor segments and radii
Mesh.cylinder()     // optional caps
Mesh.cone()         // optional base cap
Mesh.box()          // unit box with quad faces
Mesh.quad()         // single quad
Mesh.triangle()     // single triangle
```

## Attribute pipeline

All methods return a new Mesh:

```swift
mesh.withFlatNormals()      // per-face normals
mesh.withSmoothNormals()    // averaged vertex normals
mesh.withSphericalUVs()     // spherical projection
mesh.withTangents()         // MikkTSpace (needs normals + UVs)
```

## Requirements

- macOS 26+ / iOS 26+
- Swift 6.2+

## Dependencies

- [GeometryLite3D](https://github.com/schwa/GeometryLite3D)
- [MetalSupport](https://github.com/schwa/MetalSupport)
- [SwiftEarcut](https://github.com/schwa/SwiftEarcut)
- MikkTSpace (vendored)
