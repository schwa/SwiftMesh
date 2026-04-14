# SwiftMesh Consolidation Plan

## Target Architecture

Three layers:

### 1. `HalfEdgeTopology`
- Pure combinatorial structure: vertex IDs, half-edges, faces, wiring (next/prev/twin)
- No positions, no geometry, no generic point parameter
- Adjacency queries, validation, edge deletion, boundary detection
- N-gon faces
- Renamed from `HalfEdgeMesh`

### 2. `Mesh`
- Thin wrapper around `HalfEdgeTopology` + vertex attributes
- Positions keyed by VertexID
- Other attributes (normals, UVs, colors) keyed by VertexID or HalfEdgeID (per-corner)
- N-gon faces — no triangulation at this level
- Shape primitives (Platonic solids, sphere, cylinder, etc.) live here
- Replaces `PolygonMesh`

### 3. `MetalMesh`
- Triangulated, interleaved Metal buffers ready for rendering
- Produced from `Mesh` via export/conversion
- Triangulation at export time: fan for convex, earcut for concave
- Vertex splitting for hard edges / per-face attributes
- Interleaved buffer layout with vertex descriptor
- Submesh support
- Replaces `TrivialMesh`, the current `Mesh` (MTLBuffer wrapper), and `MeshWithEdges`
- Edge list extraction is trivial from the source `Mesh`'s topology
- Should live in its own target (separate Metal dependency)

## Key Decisions

- **Faces are n-gon.** Triangulation only happens at MetalMesh export.
- **HalfEdgeTopology stores no geometry.** It's pure wiring.
- **Mesh is a wrapper around topology.** It pairs topology with attribute data.
- **Per-corner attributes use HalfEdgeID as key.** Each half-edge = one vertex in one face. Natural key for UVs, normals, etc.
- **Metal concerns are isolated.** MetalMesh is a separate target so the core types have no Metal dependency.

## Steps

1. **Rename `HalfEdgeMesh` → `HalfEdgeTopology`**, strip out `Point` generic and all position storage. Topology-only.
2. **Define vertex attribute storage** — decide how `Mesh` pairs topology with positions and other per-vertex/per-corner attributes.
3. **Build `Mesh`** — topology + attributes, shape primitives, convenience API.
4. **Triangulation** — fan + earcut path from n-gon faces to triangle indices.
5. **Build `MetalMesh`** — triangulated Metal buffer export from `Mesh`. Replaces `TrivialMesh` + old `Mesh` + `MeshWithEdges`.
6. **Remove dead types** — `PolygonMesh`, `TrivialMesh`, old `Mesh`, `MeshWithEdges`.

## Decided

- **Mesh attribute storage is SoA** (struct of arrays). Positions as `[SIMD3<Float>]` indexed by VertexID.raw, per-corner attributes as arrays indexed by HalfEdgeID.raw. Optional arrays for optional attributes. No fixed Vertex struct.
- **MetalMesh layout doesn't matter** — it's a write-once export. Interleave however the vertex descriptor dictates.

## Open Questions

- **MetalMesh naming**: `MetalMesh`? `GPUMesh`? `RenderMesh`?
- **2D support**: keep 2D factories/queries as extensions? Separate module?
