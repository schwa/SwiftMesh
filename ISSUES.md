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
status: closed
priority: high
kind: task
created: 2026-04-14T22:38:23Z
updated: 2026-04-14T23:53:30Z
closed: 2026-04-14T23:53:30Z

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

## 6: Separate MetalMesh into its own target
status: closed
priority: high
kind: task
created: 2026-04-15T00:51:12Z
updated: 2026-04-15T01:08:11Z
closed: 2026-04-15T01:08:11Z

MetalMesh should be in a separate target (e.g. SwiftMeshMetal) so the core SwiftMesh target has no Metal dependency.

- `2026-04-15T01:08:11Z`: Premature — no consumer needs Metal-free SwiftMesh yet. Split when needed.

---

## 7: ModelIO import (OBJ, PLY, USD)
status: new
priority: medium
kind: feature
created: 2026-04-15T00:51:16Z
updated: 2026-04-15T01:22:56Z

Bidirectional ModelIO conversion. MDLMesh → Mesh (import positions, normals, UVs, submeshes, reconstruct topology) and Mesh → MDLMesh (export for SceneKit/RealityKit/USD). Should live in SwiftMeshIO.

---

## 8: MetalMesh → Mesh conversion
status: new
priority: medium
kind: feature
created: 2026-04-15T00:51:21Z

Convert MetalMesh back to Mesh. Will produce a triangle-only mesh with duplicated vertices (no topology recovery). Useful for importing GPU meshes back into the editing pipeline.

---

## 9: Binary PLY support
status: new
priority: low
kind: feature
created: 2026-04-15T00:51:26Z

Add binary PLY read/write to SwiftMeshIO. Needed for large meshes — ASCII PLY is too slow/large.

---

## 10: Subdivision surfaces (Catmull-Clark, Loop)
status: new
priority: medium
kind: feature
created: 2026-04-15T00:51:30Z

Subdivision surface algorithms. Catmull-Clark for quad meshes, Loop for triangle meshes. Operate on Mesh, return a new refined Mesh.

---

## 11: Boolean / CSG operations
status: new
priority: medium
kind: feature
created: 2026-04-15T00:51:34Z

Union, intersection, difference on Mesh. Requires robust intersection detection and mesh splitting.

---

## 12: Mesh editing operations (split, collapse, extrude)
status: new
priority: medium
kind: feature
created: 2026-04-15T00:51:42Z

Edge split, edge collapse, face extrude, vertex welding/deduplication. Core editing primitives for a mesh editor.

---

## 13: Additional UV projection methods
status: new
priority: low
kind: feature
created: 2026-04-15T00:51:47Z

Planar, cylindrical, and box UV projection. Currently only spherical projection is supported.

---

## 14: Mesh transform methods (scale, translate, rotate)
status: new
priority: high
kind: feature
created: 2026-04-15T00:51:52Z

Add scaled(), translated(), rotated(), transformed() methods on Mesh. Return new Mesh with transformed positions (and normals/tangents adjusted).

---

## 15: Mesh merge / combine
status: new
priority: medium
kind: feature
created: 2026-04-15T00:52:03Z

Combine multiple Meshes into one, merging topologies and attribute arrays. Each source mesh becomes a submesh.

---

## 16: Port remaining shape primitives
status: new
priority: low
kind: task
created: 2026-04-15T00:52:07Z

Port capsule, hemisphere, icoSphere, cubeSphere, circle from old TrivialMesh+Shapes to Mesh primitives.

---

## 17: Mesh simplification / decimation
status: new
priority: low
kind: feature
created: 2026-04-15T00:52:14Z

Reduce mesh polygon count while preserving shape. Quadric error metrics or similar.

---

## 18: Support separate-buffer (SoA) vertex layout in MetalMesh
status: new
priority: medium
kind: feature
created: 2026-04-15T01:09:58Z

Currently MetalMesh always interleaves attributes into one buffer. Add option for separate MTLBuffers per attribute (positions, normals, UVs, etc.) — avoids per-vertex byte packing and enables near-zero-cost conversion from Mesh's SoA arrays.

---

## 19: 2D support — extensions or separate module?
status: new
priority: low
kind: task
created: 2026-04-15T01:11:40Z

Decide how to handle 2D mesh operations (signed area, convexity, segment-based construction from CGPoint). Options: conditional extensions on Mesh, or a separate module depending on GeometryLite2D.

---

## 20: Improve test coverage for MetalMesh attribute interleaving
status: new
priority: medium
kind: task
created: 2026-04-15T01:19:52Z

MetalMesh is at 73.4% coverage. The per-corner attribute paths (normals, UVs, tangents, colors) aren't exercised — tests only export position-only meshes. Add tests that export meshes with withFlatNormals/withSphericalUVs/withTangents and verify vertex buffer contents.

---

## 21: Improve test coverage for HalfEdgeTopology edge cases
status: new
priority: medium
kind: task
created: 2026-04-15T01:19:58Z

HalfEdgeTopology is at 82.8% coverage. Uncovered paths include deleteEdge branches (boundary edges, single-face deletion) and boundaryLoops. Add targeted tests for these.

---

## 22: MetalMesh unshares all vertices, making edge deduplication impossible
status: closed
priority: medium
kind: bug
created: 2026-04-15T01:37:20Z
updated: 2026-04-15T01:41:32Z
closed: 2026-04-15T01:41:32Z

MetalMesh splits every half-edge corner into a unique vertex in the output buffer. This means two triangles sharing an edge get 6 distinct vertices instead of 4, and the index buffer never references the same vertex index for shared edges. Downstream consumers (like edge extraction for wireframe rendering) can't deduplicate edges by comparing index values. Either MetalMesh should preserve shared vertices where attributes match, or it should expose a mapping from output indices back to original VertexIDs.

---

## 23: Generate UVs for tetrahedron primitive
status: new
priority: low
kind: feature
created: 2026-04-15T02:57:27Z


---

## 24: Generate UVs for cube primitive
status: new
priority: low
kind: feature
created: 2026-04-15T02:57:32Z


---

## 25: Generate UVs for octahedron primitive
status: new
priority: low
kind: feature
created: 2026-04-15T02:57:33Z


---

## 26: Generate UVs for icosahedron primitive
status: new
priority: low
kind: feature
created: 2026-04-15T02:57:33Z


---

## 27: Generate UVs for dodecahedron primitive
status: new
priority: low
kind: feature
created: 2026-04-15T02:57:33Z


---

## 28: Generate UVs for triangle() primitive
status: new
priority: low
kind: feature
created: 2026-04-15T02:57:33Z


---

## 29: Generate UVs for quad() primitive
status: new
priority: low
kind: feature
created: 2026-04-15T02:57:33Z


---

## 30: Generate UVs for box() primitive
status: new
priority: low
kind: feature
created: 2026-04-15T02:57:33Z


---

## 31: Generate UVs for torus() primitive
status: new
priority: low
kind: feature
created: 2026-04-15T02:57:33Z


---

## 32: Generate UVs for cylinder() primitive
status: new
priority: low
kind: feature
created: 2026-04-15T02:57:34Z


---

