# SwiftMesh

A Swift package for mesh data structures and operations.

## Mesh Types

**`HalfEdgeMesh<ID, Point>`**
: Core topological mesh with full adjacency queries — neighbor faces, edge traversal, boundary detection, validation. Generic over point type (`CGPoint`, `SIMD3<Float>`, etc.). Supports n-gon faces. 2D-specific operations (signed area, convexity, segment-based construction) available via conditional extensions on `CGPoint`.

**`PolygonMesh`**
: High-level facade over `HalfEdgeMesh<Int, SIMD3<Float>>`. Simple vertices + faces API. Includes Platonic solid primitives (tetrahedron, cube, octahedron, dodecahedron, icosahedron). Topology is hidden but accessible for validation and edge/face queries.

**`TrivialMesh`**
: GPU-ready indexed triangle mesh with per-vertex attributes (normals, UVs, tangents, bitangents, colors). Vertices are duplicated per-face for hard edges. Shape factories for box, sphere, cylinder, cone, torus, capsule, plane, and more. Converts to `Mesh` via `toMesh(device:)`.

**`Mesh`**
: Metal GPU mesh wrapping `MTLBuffer` vertex/index data with submeshes and a codable vertex descriptor. The final rendering format.

**`MeshWithEdges`**
: Wraps a `Mesh` and extracts unique edges for wireframe rendering.

## Comparison

|                   | HalfEdgeMesh | PolygonMesh     | TrivialMesh              | Mesh      | MeshWithEdges |
| ----------------- | ------------ | --------------- | ------------------------ | --------- | ------------- |
| Indexed           | ✓            | ✓               | ✓                        | ✓         | ✓             |
| Face type         | N-gon        | N-gon           | Triangles                | Triangles | Triangles     |
| Dimension         | Generic      | 3D              | 3D                       | —         | —             |
| Adjacency queries | ✓            | via HE          | —                        | —         | —             |
| Normals           | —            | Per-face        | Per-vertex               | Raw       | Raw           |
| UVs               | —            | —               | ✓                        | Raw       | Raw           |
| Tangents          | —            | —               | ✓                        | Raw       | Raw           |
| Colors            | —            | —               | ✓                        | Raw       | Raw           |
| Submeshes         | —            | —               | —                        | ✓         | ✓             |
| MTLBuffer         | —            | —               | —                        | ✓         | ✓             |
| Edge list         | ✓            | ✓               | —                        | —         | ✓             |
| Mutable           | ✓            | —               | ✓                        | ✓         | —             |
| Insert vertex     | O(1)         | —               | O(1)                     | Rebuild   | —             |
| Insert face       | O(n)         | —               | O(1)                     | Rebuild   | —             |
| Insert edge       | O(n)         | —               | —                        | Rebuild   | —             |
| Shape primitives  | —            | Platonic solids | Box, sphere, cylinder, … | —         | —             |

## Dependencies

- [GeometryLite2D](https://github.com/schwa/GeometryLite2D) — 2D geometry primitives (`LineSegment`, `Polygon`, `Identified`, etc.)
- [GeometryLite3D](https://github.com/schwa/GeometryLite3D) — `Packed3` type
- [MetalSupport](https://github.com/schwa/MetalSupport) — Metal helpers
- [SwiftEarcut](https://github.com/schwa/SwiftEarcut) — polygon triangulation
- MikkTSpace — tangent generation (vendored C source)
