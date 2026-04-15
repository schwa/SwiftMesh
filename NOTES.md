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

## Performance Notes

**Mesh → MetalMesh** conversion is O(total triangles) with constant work per corner (attribute lookup, byte interleaving, buffer copy). For small meshes (Platonic solids, simple shapes) it's negligible. For large meshes (100K+ triangles), the per-corner dictionary lookups and byte-level interleaving will be the bottleneck — not yet optimized.

**Triangulation** adds overhead for n-gon faces: each non-triangle face requires a 3D→2D projection and earcut pass. Triangle faces pass through with no extra work.

## Consumers

- **Interaction3D** — 3D mesh rendering in SwiftUI Canvas (replaces inlined PolygonMesh)
- **MetalSprocketsAddOns** — Metal mesh pipeline (replaces old Mesh/TrivialMesh)
- **MetalSprocketsExample** — demo app consuming MetalMesh
- **MetalSprocketsSceneGraph** — scene graph mesh nodes
- **GeometryLite2D** — has redundant HalfEdgeMesh/PolygonMesh copies to remove

## Design decisions

- Faces are n-gon. Triangulation only happens at MetalMesh export.
- HalfEdgeTopology stores no geometry. Pure wiring.
- Mesh is a thin wrapper: topology + SoA attribute arrays.
- Per-corner attributes use HalfEdgeID as key (each half-edge = one vertex in one face).
- MetalMesh layout doesn't matter — write-once export, interleave however the vertex descriptor dictates.
- Submeshes on Mesh are face groups (list of FaceIDs). MetalMesh maps 1:1.


## Dependencies

- [GeometryLite3D](https://github.com/schwa/GeometryLite3D) — `Packed3` type for Metal buffer packing
- [MetalSupport](https://github.com/schwa/MetalSupport) — `VertexDescriptor` and Metal helpers
- [SwiftEarcut](https://github.com/schwa/SwiftEarcut) — polygon triangulation (for future n-gon support)
- MikkTSpace — tangent generation (vendored C source)
