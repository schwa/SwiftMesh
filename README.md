# SwiftMesh

A Swift package for mesh data structures and operations.

## Architecture

Three layers:

**`HalfEdgeTopology`**
: Pure combinatorial half-edge structure. Vertex IDs, half-edges, faces, wiring (next/prev/twin). No positions or geometry. Adjacency queries, validation, boundary detection, edge deletion.

**`Mesh`**
: Wraps `HalfEdgeTopology` with SoA vertex attributes. Positions per-vertex, normals/UVs/colors per-corner (indexed by HalfEdgeID). Per-face material tags. N-gon faces. Includes Platonic solid primitives (tetrahedron, cube, octahedron, icosahedron, dodecahedron).

**`MetalMesh`**
: GPU-ready export from `Mesh`. Triangulates faces, splits vertices per-corner, interleaves attributes into Metal buffers. Submeshes grouped by material tag.

## Consumers

- **Interaction3D** — 3D mesh rendering in SwiftUI Canvas (replaces inlined PolygonMesh)
- **MetalSprocketsAddOns** — Metal mesh pipeline (replaces old Mesh/TrivialMesh)
- **MetalSprocketsExample** — demo app consuming MetalMesh
- **MetalSprocketsSceneGraph** — scene graph mesh nodes
- **GeometryLite2D** — has redundant HalfEdgeMesh/PolygonMesh copies to remove

## Dependencies

- [GeometryLite3D](https://github.com/schwa/GeometryLite3D) — `Packed3` type for Metal buffer packing
- [MetalSupport](https://github.com/schwa/MetalSupport) — `VertexDescriptor` and Metal helpers
- [SwiftEarcut](https://github.com/schwa/SwiftEarcut) — polygon triangulation (for future n-gon support)
- MikkTSpace — tangent generation (vendored C source)
