# ISSUES.md

---

## 1: Rename HalfEdgeMesh to HalfEdgeTopology, strip Point generic and position storage
status: closed
priority: high
kind: task
created: 2026-04-14T22:38:12Z
updated: 2026-04-14T23:00:15Z
closed: 2026-04-14T23:00:15Z

Remove Point generic parameter. Remove Vertex.p position storage. Move polygon(for:), boundaryLoops(), collectLoop() to return IDs only. Move 2D CGPoint extensions (signedArea, isConvex, isHole, segment-based init) out. Pure topology only.

---

## 2: Build Mesh type — topology + SoA vertex attributes
status: closed
priority: high
kind: task
created: 2026-04-14T22:38:19Z
updated: 2026-04-14T23:37:01Z
closed: 2026-04-14T23:37:01Z

Mesh wraps HalfEdgeTopology. SoA attribute storage: positions indexed by VertexID.raw, per-corner attributes (UVs, normals) indexed by HalfEdgeID.raw. Per-face material tag. Optional attribute arrays. Shape primitives (Platonic solids, etc.) move here.

---

## 3: Triangulation — fan + earcut for n-gon faces
status: new
priority: high
kind: task
created: 2026-04-14T22:38:23Z

Triangulate n-gon faces for GPU export. Fan triangulation for convex faces, SwiftEarcut for concave. Operates on Mesh, produces triangle index lists.

---

## 4: Build MetalMesh — GPU export from Mesh
status: closed
priority: high
kind: task
created: 2026-04-14T22:38:31Z
updated: 2026-04-14T23:39:40Z
closed: 2026-04-14T23:39:40Z

Convert Mesh to Metal buffers. Triangulate faces, split vertices for hard edges/per-corner attributes, interleave into vertex buffer, generate per-submesh index arrays grouped by face material tag. Vertex descriptor. Replaces TrivialMesh, old Mesh, MeshWithEdges. Separate target with Metal dependency.

---

## 5: Remove dead types — PolygonMesh, TrivialMesh, old Mesh, MeshWithEdges
status: closed
priority: medium
kind: task
created: 2026-04-14T22:38:36Z
updated: 2026-04-14T23:42:07Z
closed: 2026-04-14T23:42:07Z

Once MetalMesh is working, remove the legacy types and their associated files. Update tests and README.

---

