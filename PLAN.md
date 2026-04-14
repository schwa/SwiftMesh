# SwiftMesh Consolidation Plan

## Target Architecture

### `HalfEdgeTopology`
- Pure combinatorial structure: vertex IDs, half-edges, faces, wiring (next/prev/twin)
- No positions, no geometry, no `Point` generic parameter
- Adjacency queries, validation, edge deletion, boundary detection all stay here
- The 2D segment-based init becomes an external factory that produces topology + positions

### `Mesh`
- `HalfEdgeTopology` + vertex attributes (positions, normals, UVs, tangents, colors)
- Attribute storage TBD — per-vertex maps, parallel arrays, or generic
- N-gon faces from the topology
- Shape primitives (Platonic solids, sphere, cylinder, etc.) live here
- `PolygonMesh` dissolves into this

### `GPUMesh` (or `MetalMesh` / `RenderMesh` — name TBD)
- Triangulated, interleaved Metal buffers ready for rendering
- Produced from `Mesh` via export/conversion
- Triangulation at export time (fan for convex, earcut for concave)
- Vertex splitting for hard edges / per-face attributes
- Interleaved buffer layout with vertex descriptor
- Submesh support
- Replaces `TrivialMesh`, the current `Mesh` (MTLBuffer wrapper), and `MeshWithEdges`
- Edge list extraction is trivial from the source `Mesh`'s topology

## Steps

1. **Rename `HalfEdgeMesh` → `HalfEdgeTopology`**, strip out `Point` generic and all position storage. Topology-only.
2. **Define vertex attribute storage** — decide how `Mesh` pairs topology with positions and other attributes.
3. **Build `Mesh`** — topology + attributes, shape primitives, convenience API.
4. **Triangulation** — fan + earcut path from n-gon faces to triangle indices.
5. **Build `GPUMesh`** — triangulated Metal buffer export from `Mesh`. Replaces `TrivialMesh` + old `Mesh` + `MeshWithEdges`.
6. **Remove dead types** — `PolygonMesh`, `TrivialMesh`, old `Mesh`, `MeshWithEdges`.

## Open Questions

- **Vertex attribute storage**: parallel arrays keyed by VertexID? Generic attribute bags? Per-face vs per-vertex vs per-corner attributes (UVs and normals are often per-corner, not per-vertex)?
- **Per-corner attributes**: half-edge ID is a natural key for per-corner data (each half-edge = one corner of one face). Store attributes on half-edges?
- **GPU export type naming**: `MetalMesh`? `GPUMesh`? `RenderMesh`? Or just a function that returns buffers?
- **2D support**: keep 2D factories/queries as extensions on `Mesh` where positions are `CGPoint`? Or separate?
