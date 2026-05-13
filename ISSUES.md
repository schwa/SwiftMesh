# ISSUES.md

---

## 1: Rename HalfEdgeMesh to HalfEdgeTopology, strip Point generic and position storage

+++
status: closed
priority: high
kind: task
created: 2026-04-14T22:38:12Z
updated: 2026-04-14T23:00:15Z
closed: 2026-04-14T23:00:15Z
+++

Remove Point generic parameter. Remove Vertex.p position storage. Move polygon(for:), boundaryLoops(), collectLoop() to return IDs only. Move 2D CGPoint extensions (signedArea, isConvex, isHole, segment-based init) out. Pure topology only.

---

## 2: Build Mesh type — topology + SoA vertex attributes

+++
status: closed
priority: high
kind: task
created: 2026-04-14T22:38:19Z
updated: 2026-04-14T23:37:01Z
closed: 2026-04-14T23:37:01Z
+++

Mesh wraps HalfEdgeTopology. SoA attribute storage: positions indexed by VertexID.raw, per-corner attributes (UVs, normals) indexed by HalfEdgeID.raw. Per-face material tag. Optional attribute arrays. Shape primitives (Platonic solids, etc.) move here.

---

## 3: Triangulation — fan + earcut for n-gon faces

+++
status: closed
priority: high
kind: task
created: 2026-04-14T22:38:23Z
updated: 2026-04-14T23:53:30Z
closed: 2026-04-14T23:53:30Z
+++

Triangulate n-gon faces for GPU export. Fan triangulation for convex faces, SwiftEarcut for concave. Operates on Mesh, produces triangle index lists.

---

## 4: Build MetalMesh — GPU export from Mesh

+++
status: closed
priority: high
kind: task
created: 2026-04-14T22:38:31Z
updated: 2026-04-14T23:39:40Z
closed: 2026-04-14T23:39:40Z
+++

Convert Mesh to Metal buffers. Triangulate faces, split vertices for hard edges/per-corner attributes, interleave into vertex buffer, generate per-submesh index arrays grouped by face material tag. Vertex descriptor. Replaces TrivialMesh, old Mesh, MeshWithEdges. Separate target with Metal dependency.

---

## 5: Remove dead types — PolygonMesh, TrivialMesh, old Mesh, MeshWithEdges

+++
status: closed
priority: medium
kind: task
created: 2026-04-14T22:38:36Z
updated: 2026-04-14T23:42:07Z
closed: 2026-04-14T23:42:07Z
+++

Once MetalMesh is working, remove the legacy types and their associated files. Update tests and README.

---

## 6: Separate MetalMesh into its own target

+++
status: closed
priority: high
kind: task
created: 2026-04-15T00:51:12Z
updated: 2026-04-15T01:08:11Z
closed: 2026-04-15T01:08:11Z
+++

MetalMesh should be in a separate target (e.g. SwiftMeshMetal) so the core SwiftMesh target has no Metal dependency.

- `2026-04-15T01:08:11Z`: Premature — no consumer needs Metal-free SwiftMesh yet. Split when needed.

---

## 7: ModelIO import (OBJ, PLY, USD)

+++
status: closed
priority: medium
kind: feature
created: 2026-04-15T00:51:16Z
updated: 2026-04-15T05:04:43Z
closed: 2026-04-15T05:04:43Z
+++

Bidirectional ModelIO conversion. MDLMesh → Mesh (import positions, normals, UVs, submeshes, reconstruct topology) and Mesh → MDLMesh (export for SceneKit/RealityKit/USD). Should live in SwiftMeshIO.

- `2026-04-15T05:04:43Z`: Implemented bidirectional ModelIO conversion: MDLMesh → MTKMesh → MetalMesh → Mesh, and Mesh → MDLMesh

---

## 8: MetalMesh → Mesh conversion

+++
status: closed
priority: medium
kind: feature
created: 2026-04-15T00:51:21Z
updated: 2026-04-15T04:54:54Z
closed: 2026-04-15T04:54:54Z
+++

Convert MetalMesh back to Mesh. Will produce a triangle-only mesh with duplicated vertices (no topology recovery). Useful for importing GPU meshes back into the editing pipeline.

- `2026-04-15T04:54:54Z`: Implemented MetalMesh.toMesh() with position dedup, per-corner attribute preservation, and submesh support

---

## 9: Binary PLY support

+++
status: open
priority: low
kind: feature
labels: effort:m
created: 2026-04-15T00:51:26Z
updated: 2026-04-15T17:02:58Z
+++

Add binary PLY read/write to SwiftMeshIO. Needed for large meshes — ASCII PLY is too slow/large.

---

## 10: Subdivision surfaces (Catmull-Clark, Loop)

+++
status: closed
priority: medium
kind: feature
created: 2026-04-15T00:51:30Z
updated: 2026-04-15T05:22:59Z
closed: 2026-04-15T05:22:59Z
+++

Subdivision surface algorithms. Catmull-Clark for quad meshes, Loop for triangle meshes. Operate on Mesh, return a new refined Mesh.

- `2026-04-15T05:22:59Z`: Implemented

---

## 11: Boolean / CSG operations

+++
status: closed
priority: medium
kind: feature
created: 2026-04-15T00:51:34Z
updated: 2026-04-15T05:14:55Z
closed: 2026-04-15T05:14:55Z
+++

Union, intersection, difference on Mesh. Requires robust intersection detection and mesh splitting.

- `2026-04-15T05:14:55Z`: Implemented

---

## 12: Mesh editing operations (split, collapse, extrude)

+++
status: closed
priority: medium
kind: feature
created: 2026-04-15T00:51:42Z
updated: 2026-04-15T05:29:20Z
closed: 2026-04-15T05:29:20Z
+++

Edge split, edge collapse, face extrude, vertex welding/deduplication. Core editing primitives for a mesh editor.

- `2026-04-15T05:29:20Z`: Superseded by individual issues #40-#44

---

## 13: Additional UV projection methods

+++
status: closed
priority: low
kind: feature
created: 2026-04-15T00:51:47Z
updated: 2026-04-15T05:20:20Z
closed: 2026-04-15T05:20:20Z
+++

Planar, cylindrical, and box UV projection. Currently only spherical projection is supported.

- `2026-04-15T05:20:20Z`: Implemented planar, cylindrical, and box UV projection

---

## 14: Mesh transform methods (scale, translate, rotate)

+++
status: closed
priority: high
kind: feature
created: 2026-04-15T00:51:52Z
updated: 2026-04-15T06:52:08Z
closed: 2026-04-15T06:52:08Z
+++

Add scaled(), translated(), rotated(), transformed() methods on Mesh. Return new Mesh with transformed positions (and normals/tangents adjusted).

---

## 15: Mesh merge / combine

+++
status: closed
priority: medium
kind: feature
labels: effort:m
created: 2026-04-15T00:52:03Z
updated: 2026-05-13T18:41:30Z
closed: 2026-05-13T18:41:30Z
+++

Combine multiple Meshes into one, merging topologies and attribute arrays. Each source mesh becomes a submesh.

---

## 16: Port remaining shape primitives

+++
status: closed
priority: low
kind: task
created: 2026-04-15T00:52:07Z
updated: 2026-04-15T04:12:19Z
closed: 2026-04-15T04:12:19Z
+++

Port capsule, hemisphere, icoSphere, cubeSphere, circle from old TrivialMesh+Shapes to Mesh primitives.

- `2026-04-15T04:12:19Z`: Superseded by individual issues #35-#39

---

## 17: Mesh simplification / decimation

+++
status: closed
priority: low
kind: feature
created: 2026-04-15T00:52:14Z
updated: 2026-04-15T07:05:32Z
closed: 2026-04-15T07:05:32Z
+++

Reduce mesh polygon count while preserving shape. Quadric error metrics or similar.

---

## 18: Support separate-buffer (SoA) vertex layout in MetalMesh

+++
status: closed
priority: medium
kind: feature
created: 2026-04-15T01:09:58Z
updated: 2026-04-15T05:01:06Z
closed: 2026-04-15T05:01:06Z
+++

Currently MetalMesh always interleaves attributes into one buffer. Add option for separate MTLBuffers per attribute (positions, normals, UVs, etc.) — avoids per-vertex byte packing and enables near-zero-cost conversion from Mesh's SoA arrays.

- `2026-04-15T05:01:06Z`: Implemented BufferLayout enum (interleaved vs separateBuffers)

---

## 19: 2D support — extensions or separate module?

+++
status: closed
priority: low
kind: task
labels: effort:s
created: 2026-04-15T01:11:40Z
updated: 2026-05-13T18:44:30Z
closed: 2026-05-13T18:44:30Z
+++

Decide how to handle 2D mesh operations (signed area, convexity, segment-based construction from CGPoint). Options: conditional extensions on Mesh, or a separate module depending on GeometryLite2D.

- `2026-05-13T18:44:30Z`: Resolved: standalone `Mesh2D<ID>` type in the `SwiftMesh` module (depends on GeometryLite2D's `Geometry` product). See `Sources/SwiftMesh/Mesh2D.swift`.

---

## 20: Improve test coverage for MetalMesh attribute interleaving

+++
status: closed
priority: medium
kind: task
labels: effort:s
created: 2026-04-15T01:19:52Z
updated: 2026-05-13T18:46:22Z
closed: 2026-05-13T18:46:22Z
+++

MetalMesh is at 73.4% coverage. The per-corner attribute paths (normals, UVs, tangents, colors) aren't exercised — tests only export position-only meshes. Add tests that export meshes with withFlatNormals/withSphericalUVs/withTangents and verify vertex buffer contents.

---

## 21: Improve test coverage for HalfEdgeTopology edge cases

+++
status: closed
priority: medium
kind: task
labels: effort:s
created: 2026-04-15T01:19:58Z
updated: 2026-05-13T18:46:22Z
closed: 2026-05-13T18:46:22Z
+++

HalfEdgeTopology is at 82.8% coverage. Uncovered paths include deleteEdge branches (boundary edges, single-face deletion) and boundaryLoops. Add targeted tests for these.

---

## 22: MetalMesh unshares all vertices, making edge deduplication impossible

+++
status: closed
priority: medium
kind: bug
created: 2026-04-15T01:37:20Z
updated: 2026-04-15T01:41:32Z
closed: 2026-04-15T01:41:32Z
+++

MetalMesh splits every half-edge corner into a unique vertex in the output buffer. This means two triangles sharing an edge get 6 distinct vertices instead of 4, and the index buffer never references the same vertex index for shared edges. Downstream consumers (like edge extraction for wireframe rendering) can't deduplicate edges by comparing index values. Either MetalMesh should preserve shared vertices where attributes match, or it should expose a mapping from output indices back to original VertexIDs.

---

## 23: Generate UVs for tetrahedron primitive

+++
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:27Z
updated: 2026-04-15T03:46:58Z
closed: 2026-04-15T03:46:58Z
+++

---

## 24: Generate UVs for cube primitive

+++
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:32Z
updated: 2026-04-15T03:11:58Z
closed: 2026-04-15T03:11:58Z
+++

---

## 25: Generate UVs for octahedron primitive

+++
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:33Z
updated: 2026-04-15T03:46:58Z
closed: 2026-04-15T03:46:58Z
+++

---

## 26: Generate UVs for icosahedron primitive

+++
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:33Z
updated: 2026-04-15T03:46:58Z
closed: 2026-04-15T03:46:58Z
+++

---

## 27: Generate UVs for dodecahedron primitive

+++
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:33Z
updated: 2026-04-15T03:46:58Z
closed: 2026-04-15T03:46:58Z
+++

---

## 28: Generate UVs for triangle() primitive

+++
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:33Z
updated: 2026-04-15T03:39:51Z
closed: 2026-04-15T03:39:51Z
+++

---

## 29: Generate UVs for quad() primitive

+++
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:33Z
updated: 2026-04-15T03:39:51Z
closed: 2026-04-15T03:39:51Z
+++

---

## 30: Generate UVs for box() primitive

+++
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:33Z
updated: 2026-04-15T03:39:51Z
closed: 2026-04-15T03:39:51Z
+++

---

## 31: Generate UVs for torus() primitive

+++
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:33Z
updated: 2026-04-15T03:46:58Z
closed: 2026-04-15T03:46:58Z
+++

---

## 32: Generate UVs for cylinder() primitive

+++
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:34Z
updated: 2026-04-15T03:39:51Z
closed: 2026-04-15T03:39:51Z
+++

---

## 33: Generate UVs for cone() primitive

+++
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:34Z
updated: 2026-04-15T03:39:51Z
closed: 2026-04-15T03:39:51Z
+++

---

## 34: Add teapot primitive

+++
status: closed
priority: low
kind: feature
created: 2026-04-15T04:11:12Z
updated: 2026-04-15T05:12:44Z
closed: 2026-04-15T05:12:44Z
+++

- `2026-04-15T05:12:44Z`: Implemented — loads bundled OBJ via ModelIO pipeline

---

## 35: Add capsule primitive

+++
status: closed
priority: low
kind: feature
created: 2026-04-15T04:12:03Z
updated: 2026-04-15T04:16:36Z
closed: 2026-04-15T04:16:36Z
+++

- `2026-04-15T04:16:36Z`: Implemented hemisphere() and capsule() primitives with extents, UV support, and full test coverage

---

## 36: Add hemisphere primitive

+++
status: closed
priority: low
kind: feature
created: 2026-04-15T04:12:03Z
updated: 2026-04-15T04:16:36Z
closed: 2026-04-15T04:16:36Z
+++

- `2026-04-15T04:16:36Z`: Implemented hemisphere() and capsule() primitives with extents, UV support, and full test coverage

---

## 37: Add icoSphere primitive

+++
status: closed
priority: low
kind: feature
created: 2026-04-15T04:12:03Z
updated: 2026-04-15T04:22:43Z
closed: 2026-04-15T04:22:43Z
+++

- `2026-04-15T04:22:43Z`: Implemented

---

## 38: Add cubeSphere primitive

+++
status: closed
priority: low
kind: feature
created: 2026-04-15T04:12:03Z
updated: 2026-04-15T04:22:43Z
closed: 2026-04-15T04:22:43Z
+++

- `2026-04-15T04:22:43Z`: Implemented

---

## 39: Add circle primitive

+++
status: closed
priority: low
kind: feature
created: 2026-04-15T04:12:03Z
updated: 2026-04-15T04:22:43Z
closed: 2026-04-15T04:22:43Z
+++

- `2026-04-15T04:22:43Z`: Implemented

---

## 40: Edge collapse operation on HalfEdgeTopology

+++
status: closed
priority: medium
kind: feature
created: 2026-04-15T05:24:28Z
updated: 2026-04-15T06:58:51Z
closed: 2026-04-15T06:58:51Z
+++

Merge two vertices connected by an edge into one, removing adjacent faces and rewiring topology. Prerequisite for mesh decimation (#17).

---

## 41: Edge flip operation on HalfEdgeTopology

+++
status: open
priority: low
kind: feature
labels: effort:s
created: 2026-04-15T05:24:28Z
updated: 2026-04-15T17:02:59Z
+++

Swap the diagonal of two adjacent triangles. Useful for mesh quality improvement and Delaunay-like refinement.

---

## 42: Edge split operation on HalfEdgeTopology

+++
status: open
priority: medium
kind: feature
labels: effort:m
created: 2026-04-15T05:25:32Z
updated: 2026-04-15T17:02:59Z
+++

Insert a vertex at an edge midpoint, splitting the two adjacent faces into four. Core editing primitive.

---

## 43: Face extrude operation

+++
status: open
priority: medium
kind: feature
labels: effort:m
created: 2026-04-15T05:25:33Z
updated: 2026-04-15T17:02:59Z
+++

Push a face outward along its normal, creating side wall quads connecting the original boundary to the extruded face.

---

## 44: Vertex weld / deduplication

+++
status: closed
priority: low
kind: feature
created: 2026-04-15T05:25:33Z
updated: 2026-04-15T17:02:41Z
closed: 2026-04-15T17:02:41Z
+++

Merge vertices that are within a tolerance distance of each other, rewiring topology. Useful for cleaning up imported meshes.

- `2026-04-15T17:02:41Z`: Duplicate of #64 (Mesh.welded(tolerance:)), which is already implemented.

---

## 45: Use Interaction3D for gestures in demo

+++
status: closed
priority: low
kind: enhancement
created: 2026-04-15T05:30:18Z
updated: 2026-04-15T05:35:02Z
closed: 2026-04-15T05:35:02Z
+++

Replace manual DragGesture in demo with Interaction3D package (github.com/schwa/Interaction3D) for orbit/pan/zoom camera controls.

- `2026-04-15T05:35:02Z`: Implemented — replaced manual DragGesture with Interaction3D's interactiveCamera modifier

---

## 46: Teapot is squished — fitToExtents scales non-uniformly

+++
status: closed
priority: medium
kind: bug
created: 2026-04-15T05:51:38Z
updated: 2026-04-15T05:53:12Z
closed: 2026-04-15T05:53:12Z
+++

fitToExtents scales each axis independently to match the target extents, which distorts non-cubic meshes like the teapot. Should use uniform scaling (fit within extents while preserving aspect ratio) for bundled meshes, or offer both modes.

- `2026-04-15T05:53:12Z`: Fixed — teapot now uses fitToDiameter for uniform scaling

---

## 47: Coplanar face merging after CSG operations

+++
status: closed
priority: medium
kind: enhancement
created: 2026-04-15T05:55:25Z
updated: 2026-04-15T06:43:20Z
closed: 2026-04-15T06:43:20Z
+++

CSG boolean operations produce excessive triangulation on flat surfaces — e.g. a flat square face becomes a mosaic of many triangles. Add a post-processing pass that merges coplanar adjacent faces back into larger polygons.

- `2026-04-15T06:43:20Z`: Implemented mergingCoplanarFaces() — deletes shared edges between adjacent coplanar faces

---

## 48: Mesh from extruded text

+++
status: open
priority: low
kind: feature
labels: effort:l
created: 2026-04-15T05:55:51Z
updated: 2026-04-15T17:03:10Z
+++

Generate meshes from text strings by converting font glyphs to paths, triangulating the 2D outline, and extruding to 3D. Should support font, size, and extrusion depth parameters.

- `2026-04-15T17:03:10Z`: Related: #49 (extruded Path) — text extrusion could build on Path extrusion.

---

## 49: Mesh from extruded SwiftUI.Path

+++
status: open
priority: medium
kind: feature
labels: effort:l
created: 2026-04-15T05:56:16Z
updated: 2026-04-15T17:03:10Z
+++

Generate meshes by triangulating a SwiftUI Path and extruding to 3D. Should handle holes, produce front/back caps and side walls. Could be the foundation for text extrusion (#48) as well.

- `2026-04-15T17:03:10Z`: Related: #48 (extruded text) — could serve as foundation for text extrusion.

---

## 50: Edge fillet (rounding)

+++
status: open
priority: low
kind: feature
labels: effort:xl
created: 2026-04-15T05:57:13Z
updated: 2026-04-15T17:03:10Z
+++

Round selected edges by replacing them with a smooth arc of faces. Requires edge split and vertex insertion along the edge neighborhood.

- `2026-04-15T17:03:10Z`: Related: #51 (edge chamfer).

---

## 51: Edge chamfer (beveling)

+++
status: open
priority: low
kind: feature
labels: effort:l
created: 2026-04-15T05:57:13Z
updated: 2026-04-15T17:03:10Z
+++

Bevel selected edges by cutting them at an angle, replacing each edge with a flat face. Simpler than fillet — no curvature, just a single angled cut.

- `2026-04-15T17:03:10Z`: Related: #50 (edge fillet).

---

## 52: Consolidate demo into single gallery with section groupings

+++
status: closed
priority: medium
kind: enhancement
created: 2026-04-15T05:57:53Z
updated: 2026-04-15T05:59:56Z
closed: 2026-04-15T05:59:56Z
+++

Replace the four separate tabs (Platonic Solids, Surfaces, CSG, Subdivision) with a single scrollable gallery using section headers to group the meshes. Reduces code duplication across gallery views.

- `2026-04-15T05:59:56Z`: Consolidated into single scrollable gallery with section headers

---

## 53: Inspector tab in demo showing mesh details

+++
status: closed
priority: medium
kind: feature
created: 2026-04-15T06:11:30Z
updated: 2026-04-15T06:12:44Z
closed: 2026-04-15T06:12:44Z
+++

New tab with a single mesh (cylinder) and a .inspector() sidebar showing vertex count, face count, edge count, and which attributes are present.

- `2026-04-15T06:12:44Z`: Implemented

---

## 54: Add Select Loop to demo inspector

+++
status: new
priority: low
kind: feature
labels: needs-info
created: 2026-04-15T06:39:36Z
updated: 2026-04-15T17:02:59Z
+++

---

## 55: Stray edges after coplanar face merging

+++
status: closed
priority: high
kind: bug
created: 2026-04-15T06:45:39Z
updated: 2026-04-15T06:47:02Z
closed: 2026-04-15T06:47:02Z
+++

mergingCoplanarFaces() produces degenerate polygons with self-intersecting boundaries. After deleteEdge merges two faces, collinear vertices from the former shared edge remain in the boundary loop, creating crossed/stray edges visible in wireframe. Need to remove collinear vertices from merged face boundaries.

- `2026-04-15T06:47:02Z`: Fixed — remove collinear vertices from merged face boundaries

---

## 56: CSG over-splits faces that don't intersect the other solid

+++
status: open
priority: high
kind: bug
labels: effort:l
created: 2026-04-15T06:58:03Z
updated: 2026-05-13T18:52:09Z
+++

BSP-based CSG splits cube faces even when the sphere is entirely interior and doesn't intersect those faces. This creates unnecessary triangulation on flat surfaces that coplanar merging can only partially clean up, since the BSP split introduces true boundary edges where none should exist.

---

## 57: Generic Mesh over Float/Double scalar type

+++
status: open
priority: medium
kind: feature
labels: effort:xl
created: 2026-04-15T07:09:54Z
updated: 2026-04-15T17:03:09Z
+++

Make Mesh generic over scalar type (Float vs Double). Positions, normals, UVs etc would use the generic scalar. Enables double-precision meshes for CSG and other operations that accumulate floating point error.

- `2026-04-15T17:03:09Z`: Related: #58 (CSG in Double), #59 (Float/Double conversion). #58 and #59 depend on this.

---

## 58: CSG operations in Double precision

+++
status: open
priority: medium
kind: enhancement
labels: effort:l
created: 2026-04-15T07:09:54Z
updated: 2026-04-15T17:03:09Z
+++

Run CSG BSP internals in Double precision to reduce vertex drift from plane splitting. Convert back to Float (or keep as Double if Mesh supports it) at the end. Depends on generic Mesh or a separate DoubleMesh type.

- `2026-04-15T17:03:09Z`: Depends on #57 (generic Mesh over scalar type). Related: #59.

---

## 59: Float/Double mesh conversion

+++
status: open
priority: medium
kind: feature
labels: effort:m
created: 2026-04-15T07:09:54Z
updated: 2026-04-15T17:03:09Z
+++

Add conversion between Float and Double precision meshes. MetalMesh only works with Float, so need a way to downconvert Double meshes for GPU use.

- `2026-04-15T17:03:09Z`: Depends on #57 (generic Mesh over scalar type). Related: #58.

---

## 60: Decimation damages CSG difference mesh (sphere − cube)

+++
status: open
priority: high
kind: bug
labels: effort:l
created: 2026-04-15T07:40:25Z
updated: 2026-04-15T17:02:59Z
+++

Decimating the 'Difference: Sphere − Cube' gallery mesh produces a gaping hole. The decimation algorithm likely collapses edges on the CSG boundary where the carved-out region meets the sphere surface, breaking the manifold.

---

## 61: Add isManifold method

+++
status: closed
priority: medium
kind: feature
created: 2026-04-15T07:40:38Z
updated: 2026-04-15T15:42:37Z
closed: 2026-04-15T15:42:37Z
+++

Add a method to check whether a mesh is a closed 2-manifold (every edge has exactly one twin, no boundary edges, consistent orientation).

- `2026-04-15T15:42:37Z`: Already implemented on HalfEdgeTopology and exposed as Mesh.isManifold.

---

## 62: cubeSphere has unwelded seam vertices, not manifold

+++
status: closed
priority: medium
kind: bug
created: 2026-04-15T07:46:38Z
updated: 2026-04-15T07:53:40Z
closed: 2026-04-15T07:53:40Z
+++

cubeSphere generates 6 independent grids projected onto a sphere but doesn't weld shared vertices at cube face edges/corners. This leaves 192 boundary half-edges with no twins. The mesh should be a closed manifold.

- `2026-04-15T07:53:40Z`: Fixed by welding seam vertices during cubeSphere construction.

---

## 63: teapot mesh is not manifold

+++
status: closed
priority: low
kind: bug
created: 2026-04-15T07:47:21Z
updated: 2026-04-15T07:48:30Z
closed: 2026-04-15T07:48:30Z
+++

Mesh.teapot() has boundary edges from the OBJ import — likely unwelded seam vertices, similar to cubeSphere (#62).

- `2026-04-15T07:48:30Z`: Not a bug — the Utah teapot is intentionally composed of separate patches with open boundaries.

---

## 64: Add Mesh.welded(tolerance:) to merge near-duplicate vertices and rebuild topology

+++
status: closed
priority: medium
kind: feature
created: 2026-04-15T07:48:19Z
updated: 2026-04-15T07:53:40Z
closed: 2026-04-15T07:53:40Z
+++

TriangleSoup.welded(tolerance:) merges positions but doesn't rebuild half-edge topology. Need a Mesh-level weld that merges near-duplicate positions, remaps face indices, and rebuilds HalfEdgeTopology so twin edges form at seams. This would fix cubeSphere (#62).

- `2026-04-15T07:53:40Z`: Implemented Mesh.welded(tolerance:) and used it to fix cubeSphere.

---

## 65: CSG results should be manifold

+++
status: open
priority: high
kind: bug
labels: effort:xl
created: 2026-04-15T07:54:19Z
updated: 2026-05-13T18:52:09Z
+++

CSG union/intersection/difference of two manifold closed meshes should produce a manifold result. Currently the BSP-based algorithm produces meshes with boundary edges and standalone faces due to the TriangleSoup round-trip losing topology. Affected: all CSG operations between closed solids (e.g. cube∪cube, sphere∩cube, sphere−cube).

---

## 66: Add split-by-plane operation

+++
status: open
priority: medium
kind: feature
labels: effort:l
created: 2026-04-15T07:54:33Z
updated: 2026-04-15T17:02:59Z
+++

Split a mesh along an arbitrary plane, producing two separate meshes (one for each side). Faces straddling the plane should be clipped and capped.

- `2026-04-15T14:21:46Z`: Add option to heal (cap) the cut faces after splitting.

---

## 67: Add mesh diagnostic API (is/has-style queries)

+++
status: open
priority: medium
kind: feature
labels: effort:m
created: 2026-04-15T14:12:08Z
updated: 2026-04-15T17:02:59Z
+++

Add a comprehensive set of diagnostic properties and methods for detecting mesh issues and attributes. We already have `isManifold`.

## Connectivity & Integrity
- `hasOrphanedVertices` — vertices with no outgoing halfedge
- `hasDanglingEdges` — edges where one or both halfedges have no face
- `hasNonConsistentTwins` — verify h.twin.twin == h for every halfedge
- `hasNonConsistentNextPrev` — verify h.next.prev == h and h.prev.next == h

## Boundary & Genus
- `boundaryLoopCount` — number of distinct boundary loops (0 = watertight)
- `eulerCharacteristic` — V - E + F
- `hasConsistentGenus` — flags if genus does not match expected surface type

## Face Valence & Winding
- `hasZeroAreaFaces` — degenerate faces with collinear/coincident vertices
- `hasInconsistentFaceWinding` — shared halfedges not oriented opposite
- `hasNonPlanarFaces` — for quad/ngon meshes

## Vertex Valence
- `hasZeroValenceVertices` — alias for orphaned vertices
- `hasHighValenceVertices(threshold:)` — unusually high valence (poles, bad merges)
- `valenceHistogram()` — frequency map of valences

## Edge & Face Counting Consistency

- `2026-04-15T14:12:08Z`: `hasNonMatchingFaceEdgeCounts` — halfedge loop count vs stored face degree
- `2026-04-15T14:12:08Z`: `hasDuplicateFaces` — two faces sharing all the same vertices
- `2026-04-15T14:12:08Z`: `hasDuplicateEdges` — more than one edge connecting the same two vertices
- `2026-04-15T15:43:45Z`: Split out the harder items: #75 (Euler characteristic / genus) and #76 (inconsistent face winding). The remaining items in this issue are straightforward computed properties.

---

## 68: Change validate() to return [ValidationIssue] instead of String?

+++
status: closed
priority: medium
kind: feature
created: 2026-04-15T14:12:38Z
updated: 2026-04-15T14:17:18Z
closed: 2026-04-15T14:17:18Z
+++

Currently `validate()` returns `String?` with the first error found. Change to return `[ValidationIssue]` so all issues are reported at once. ValidationIssue should be a structured type with severity, location (edge/face/vertex ID), and description.

- `2026-04-15T14:17:18Z`: Implemented. validate() now returns [ValidationIssue] with severity, location, and message for every issue found.

---

## 69: Refactor demo app to NavigationSplitView

+++
status: closed
priority: medium
kind: feature
created: 2026-04-15T14:13:27Z
updated: 2026-04-15T14:20:11Z
closed: 2026-04-15T14:20:11Z
+++

Replace the current TabView with Gallery/Inspector tabs and the full-screen overlay with a single NavigationSplitView layout. Sidebar shows the mesh list, detail shows the interactive mesh view with the toolbar buttons (weld, triangulate, subdivide, decimate, standalone highlight) and the inspector info (manifold status, face count, etc.).

- `2026-04-15T14:20:11Z`: Refactored to NavigationSplitView with sidebar mesh list, detail interactive view, and inspector panel with topology info and operations.

---

## 70: Add Metal debug shaders for topology visualization

+++
status: open
priority: low
kind: feature
labels: effort:m
created: 2026-04-15T14:14:11Z
updated: 2026-04-15T17:02:59Z
+++

Integrate debug shaders from MetalSprocketsAddons to visualize mesh topology in the demo app. Include: normal visualization (lines or color-mapped), wireframe overlay, face winding display, boundary edge highlighting, vertex valence heatmap.

---

## 71: Support extrusion modes: solid, walls only, thin walls

+++
status: new
priority: medium
kind: feature
labels: needs-info
created: 2026-04-15T14:20:40Z
updated: 2026-04-15T17:02:59Z
+++

---

## 72: Heal holes

+++
status: new
priority: medium
kind: feature
labels: needs-info
created: 2026-04-15T14:20:52Z
updated: 2026-04-15T17:02:59Z
+++

---

## 73: Unify per-corner attribute handling into a reusable remapping layer

+++
status: open
priority: medium
kind: enhancement
labels: architecture, refactor, effort:l
created: 2026-04-15T15:38:03Z
updated: 2026-04-15T17:02:59Z
+++

Every file that touches per-corner attributes (normals, textureCoordinates, tangents, bitangents, colors) manually zips/copies/remaps 5–6 optional arrays in lockstep. This boilerplate is duplicated across welding, triangulation, MetalMesh conversion, PLY export, subdivision, and coplanar merge. Adding a new attribute (e.g. bone weights) requires touching 8+ files.

Proposal: introduce a single abstraction (e.g. CornerAttributes or AttributeTable) that owns the optional per-corner arrays and exposes operations like remap(by:), subset(indices:), append(from:), and average(indices:). All current consumers would delegate to this layer instead of hand-rolling the same if-let/zip/copy loops.

Affected files: Mesh.swift (welded), Triangulation.swift (triangulated), MetalMesh.swift (init, toMesh), MeshAttributes.swift (withTangents), MeshOptimization.swift (mergingCoplanarFaces), PLY.swift (write), Subdivision.swift (attributes stripped).

Dependency category: In-process (pure data, no I/O).

Test impact: A single boundary test on the attribute-remapping API would replace scattered attribute-plumbing assertions across MeshTests, MeshAttributesTests, TriangulationTests, MetalMeshTests, and PLYTests.

---

## 74: Simplify CSG conversion pipeline

+++
status: open
priority: low
kind: enhancement
labels: architecture, refactor, effort:l
created: 2026-04-15T15:38:15Z
updated: 2026-04-15T17:02:59Z
+++

The CSG pipeline performs 5+ data conversions in sequence: Mesh → TriangleSoup → CSGPolygon → BSPNode → [CSGPolygon] → TriangleSoup → welded TriangleSoup → Mesh → welded Mesh → mergingCoplanarFaces. Each step loses information (all per-corner attributes are stripped) and introduces tolerance-dependent behavior spread across welding (1e-5), coplanar merge (1e-4 angle, 1e-4 distance), BSP splitting (1e-5 epsilon), and the Mesh.union/intersection/difference weldTolerance parameter (1e-2).

Opportunities:
- CSGPolygon and TriangleSoup both represent flat indexed polygons — the TriangleSoup→CSGPolygon→TriangleSoup round-trip could be eliminated by operating directly on TriangleSoup or a shared polygon representation.
- The welding step happens twice (once inside toMesh, once could happen via the caller). Consolidate.
- Tolerance values are scattered as magic numbers across CSG.swift, TriangleSoup.swift, and MeshOptimization.swift. Centralize into a CSGOptions struct or similar.
- Consider preserving per-corner attributes through the pipeline where possible (at minimum normals could be re-derived rather than stripped).

Affected files: CSG.swift, TriangleSoup.swift, MeshOptimization.swift, Mesh.swift (welded).

Dependency category: In-process (pure computation).

Test impact: Existing CSGTests already test at the boundary (union/intersection/difference → validate topology). Internal simplification wouldn't require new tests but would make the pipeline easier to debug and extend.

---

## 75: Implement Euler characteristic and genus computation

+++
status: open
priority: low
kind: feature
labels: topology, diagnostics, effort:m
created: 2026-04-15T15:43:32Z
updated: 2026-04-15T17:02:59Z
+++

Split from #67. Compute eulerCharacteristic (V - E + F) and hasConsistentGenus. Non-trivial because:
- Disconnected meshes: need to compute per-component, not globally
- Non-orientable surfaces: genus formula differs (χ = 2 - 2g for orientable, χ = 2 - g for non-orientable)
- Meshes with boundary: χ = 2 - 2g - b where b = number of boundary loops
- Need to decide what 'expected surface type' means for hasConsistentGenus — user-supplied, or inferred?

Depends on boundaryLoopCount from #67.

---

## 76: Detect inconsistent face winding

+++
status: open
priority: low
kind: feature
labels: topology, diagnostics, effort:m
created: 2026-04-15T15:43:40Z
updated: 2026-04-15T17:02:59Z
+++

Split from #67. hasInconsistentFaceWinding — verify that for every pair of adjacent faces sharing an edge, the shared half-edges run in opposite directions. Non-trivial because:
- Boundary edges have no twin, so they're neither consistent nor inconsistent — need clear semantics
- Non-orientable surfaces (Möbius strip, Klein bottle) are inherently inconsistent — should this be an error or an informational property?
- After CSG or coplanar merge, winding can be locally flipped — need to decide if this checks globally or returns per-face/per-edge results
- For large meshes, a BFS/DFS orientation-propagation approach is needed rather than pairwise checking

---

## 77: Add convex hull from points

+++
status: closed
priority: medium
kind: feature
labels: effort:l
created: 2026-04-15T16:08:54Z
updated: 2026-04-15T17:09:27Z
closed: 2026-04-15T17:09:27Z
+++

Compute the convex hull of a set of 3D points, returning a Mesh. Standard incremental or quickhull algorithm.

- `2026-04-15T17:03:10Z`: Related: #78 (convex hull with radii) depends on this.
- `2026-04-15T17:09:27Z`: Implemented in commit 'Add convex hull mesh generation with incremental algorithm and tests'.

---

## 78: Add convex hull from points with radii

+++
status: open
priority: low
kind: feature
labels: effort:l
created: 2026-04-15T16:08:59Z
updated: 2026-04-15T17:03:10Z
+++

Compute the convex hull of a set of 3D spheres (point + radius), returning a Mesh. This is the Minkowski sum of the convex hull of the centers with a sphere — effectively rounding the edges and vertices of the hull. Depends on #77 (convex hull from points).

- `2026-04-15T17:03:10Z`: Depends on #77 (convex hull from points).

---

## 79: Add marching cubes

+++
status: closed
priority: medium
kind: feature
labels: effort:l
created: 2026-04-15T16:09:04Z
updated: 2026-04-15T17:09:27Z
closed: 2026-04-15T17:09:27Z
+++

Implement marching cubes to generate a Mesh (or TriangleSoup) from a scalar field / signed distance function. Takes a grid resolution and a sampling closure (SIMD3<Float>) -> Float, produces an isosurface mesh at the zero crossing.

- `2026-04-15T17:09:27Z`: Implemented in commit 'Add marching cubes isosurface generation'.

---

## 80: Add drag and drop of any ModelIO-supported mesh format

+++
status: closed
priority: medium
kind: feature
created: 2026-04-15T16:09:14Z
updated: 2026-04-15T16:18:33Z
closed: 2026-04-15T16:18:33Z
+++

In the demo app, support drag-and-drop import of any file format ModelIO can read (OBJ, PLY, STL, USD, etc.). Convert the dropped file to a Mesh via MDLMesh and display it.

- `2026-04-15T16:18:33Z`: Added .dropDestination(for: URL.self) on ContentView. Dropped files are loaded via MDLAsset → MDLMesh → Mesh and appear in an Imported sidebar section.

---

## 81: Add export of ASCII PLY

+++
status: closed
priority: low
kind: feature
created: 2026-04-15T16:09:19Z
updated: 2026-04-15T16:18:33Z
closed: 2026-04-15T16:18:33Z
+++

PLY.write() already exists in SwiftMeshIO but isn't exposed in the demo app. Add a file export action (e.g. via .fileExporter or NSSavePanel) that writes the current mesh to ASCII PLY.

- `2026-04-15T16:18:33Z`: Added Export PLY toolbar button using .fileExporter with a PLYDocument (FileDocument wrapping PLY.write).

---

## 82: Decimation leaves tombstoned faces, fails validation

+++
status: new
priority: high
kind: bug
labels: decimation, topology
created: 2026-04-15T17:48:08Z
+++

After decimation, the mesh contains hundreds of tombstoned faces (face.edge == nil) that are never compacted out. These cause validation errors ('Has no boundary edge') and isManifold returns false even for meshes that should remain manifold.

Reproduced with:
- IcoSphere (subdivisions: 3) decimated to 50% → 2880 errors
- IcoSphere (subdivisions: 3) decimated to 25% → 4320 errors

The decimation algorithm (QEM edge collapse) tombstones faces and vertices but never rebuilds the topology arrays to remove them. Need a compaction pass after decimation that:
1. Removes tombstoned faces (edge == nil)
2. Removes tombstoned vertices (edge == nil) 
3. Removes tombstoned half-edges (next == nil)
4. Remaps all indices
5. Remaps per-corner attributes if present

---

## 83: Visually validate all mesh primitives in demo app

+++
status: new
priority: medium
kind: task
labels: qa, demo
created: 2026-04-15T18:06:36Z
+++

Go through every mesh in the demo gallery and verify they render correctly in both wireframe and Metal (Blinn-Phong) modes. Check for:
- Correct shape and proportions
- No inside-out faces or flipped normals
- Proper UV mapping (use Tex Coords / Checkerboard debug modes)
- Capped vs uncapped variants look right
- CSG results are clean
- Subdivision results are smooth
- Decimated meshes degrade gracefully

---

## 84: border() with .textureCoordinates attribute doesn't generate UVs

+++
status: closed
priority: medium
kind: bug
created: 2026-04-15T22:53:05Z
updated: 2026-04-15T23:01:06Z
closed: 2026-04-15T23:01:06Z
+++

Mesh.border(attributes: .default) or .border(attributes: [.flatNormals, .textureCoordinates]) doesn't generate texture coordinates on the border geometry. The new border faces are created without UV assignment, so downstream consumers that require texcoords (e.g. FlatShader) fail with 'Vertex attribute 2 is not defined'. Workaround: call .withPlanarUVs() after .border(). Same issue exists with .wireframe().

- `2026-04-15T23:01:06Z`: Fixed: both border() and wireframe() now generate box-projected UVs (withBoxUVs()) when attributes contain .textureCoordinates, before calling applyAttributes().

---

## 85: Performance umbrella

+++
status: new
priority: medium
kind: task
labels: performance, umbrella
created: 2026-04-16T03:22:42Z
+++

Umbrella issue tracking performance work across SwiftMesh.

Child issues will be filed for specific hotspots and investigations (CSG, decimation, topology build, I/O, Metal upload, allocations, benchmarking harness, etc.).

Use this issue to coordinate priorities and link related sub-issues.

---

## 86: Swift Array is slow in hot paths — explore Spans and swift-collections

+++
status: new
priority: medium
kind: enhancement
labels: performance
depends: SwiftMesh#85
created: 2026-04-16T03:22:53Z
+++

Swift's `Array` shows up as a bottleneck in mesh hot paths (CSG, decimation, topology build, attribute interleaving). Bounds checks, COW traffic, and lack of contiguous typed access hurt throughput.

Investigate replacing `Array` in hot paths with:

- `Span` / `RawSpan` / `MutableSpan` (Swift 6.x) for borrowed, bounds-check-elidable contiguous access
- `swift-collections` types where appropriate:
  - `Deque` for BFS/DFS work queues (CSG BSP traversal, topology walks)
  - `OrderedSet` / `OrderedDictionary` for stable-ordered vertex/edge dedup
  - `HashTreeCollections` (`TreeDictionary`, `TreeSet`) where structural sharing helps
- `ContiguousArray` as a low-effort first step where we don't need bridging

Tasks:
- [ ] Identify the top Array-heavy hot paths via profiling (Instruments: Time Profiler + Allocations)
- [ ] Prototype Span-based APIs for the worst offenders
- [ ] Add swift-collections as a dependency if not already present
- [ ] Benchmark before/after on representative meshes
- [ ] Document guidelines for when to use Array vs Span vs ContiguousArray vs swift-collections

Depends on a benchmarking harness (to be filed separately under the performance umbrella).

---

## 87: Decimation: O(V·E) full half-edge scans per collapse

+++
status: new
priority: high
kind: enhancement
labels: performance, decimation
depends: SwiftMesh#85
created: 2026-04-16T03:24:19Z
+++

`Mesh.decimate` repeatedly does full sweeps over `topology.halfEdges` and `topology.vertices` for every edge collapse:

In `Decimation.swift`:
- Heap re-insertion after each collapse:
  ```swift
  for neighborHE in topology.halfEdges where neighborHE.next != nil && neighborHE.origin == survivor { ... }
  ```
  This is O(E) per collapse → O(V·E) total just for heap maintenance.

In `HalfEdgeTopology.collapseEdge`:
- `for i in halfEdges.indices where halfEdges[i].origin == vertexB` — O(E)
- `vertices[vertexA.raw].edge = halfEdges.first { $0.origin == vertexA && $0.next != nil }?.id` — O(E)
- Final loop: `for i in vertices.indices where vertices[i].edge != nil { ... halfEdges.first { ... } }` — O(V·E) **per collapse**

Together this dominates decimation runtime on any non-trivial mesh.

Fix:
- Maintain a vertex → outgoing half-edges adjacency list (or just walk the existing twin/next ring)
- Use `vertexRing(of:)` style traversal to enumerate edges around the survivor instead of scanning all half-edges
- The `vertices[i].edge` repair pass is only needed for vertices that lost their referenced edge — track those explicitly during the collapse rather than scanning all vertices

Expected impact: orders of magnitude on meshes >10k faces.

---

## 88: MetalMesh: variable-length [UInt8] dedup key is slow per-vertex

+++
status: new
priority: high
kind: enhancement
labels: performance, metal
depends: SwiftMesh#85
created: 2026-04-16T03:24:31Z
+++

In `MetalMesh.init`, vertex deduplication uses a `[[UInt8]: UInt32]` dictionary keyed by the concatenated bytes of every attribute:

```swift
var vertexDedup: [[UInt8]: UInt32] = [:]
...
var compositeKey: [UInt8] = []
for bi in bufferIndices {
    var bytes = [UInt8](repeating: 0, count: biStride)
    bytes.withUnsafeMutableBytes { ... }
    perBuffer[bi] = bytes
    compositeKey.append(contentsOf: bytes)
}
if let existingIndex = vertexDedup[compositeKey] { ... }
```

Per triangle corner this allocates:
- One `[UInt8]` per buffer (`bytes`)
- One `[UInt8]` composite key
- Hashes a variable-length byte array on every lookup

Also `bufferData[bi]!.append(contentsOf: perBuffer[bi]!)` repeatedly grows per-buffer storage.

Fix options:
- Dedup by `(vertexID, halfEdgeID)` pair instead of bytes — same vertex+corner always produces the same attributes
- Pre-size all `bufferData` arrays based on max possible vertex count (sum of corners across submeshes)
- Use `UnsafeMutableRawBufferPointer` writes directly into pre-sized buffers, no intermediate `[UInt8]`
- If byte-level dedup is still required, use a `UInt64` hash (SipHash / xxHash) of the bytes as the dictionary key, with a fallback equality check

Expected impact: large — this runs once per Metal upload but dominates conversion time for meshes with many corners.

---

## 89: CSG: allPolygons and clipPolygons allocate excessively

+++
status: new
priority: medium
kind: enhancement
labels: performance, csg
depends: SwiftMesh#85
created: 2026-04-16T03:24:43Z
+++

Several CSG hot paths allocate intermediate arrays unnecessarily:

**`CSGNode.allPolygons()`** recurses with `result.append(contentsOf: front.allPolygons())`, allocating a new array at every node. Replace with an `inout` accumulator:
```swift
func collectPolygons(into result: inout [CSGPolygon]) {
    result.append(contentsOf: polygons)
    front?.collectPolygons(into: &result)
    back?.collectPolygons(into: &result)
}
```

**`CSGNode.clipPolygons`** ends with `return frontList + backList` — allocates a fresh array and copies both. Use `frontList.append(contentsOf: backList); return frontList`.

**`splitPolygon`** allocates `var types: [PointClassification] = []` per call. CSG polygons are almost always triangles or quads — use a small fixed-capacity buffer (e.g. `ContiguousArray` reserved up front, or stack-style with tuple of 3-4 entries).

**`CSGPolygon` plane** is recomputed via `CSGPlane(a, b, c)` for every triangle in `toPolygons`, including a `simd_length` + division. For triangle inputs we can compute plane with a single cross product without normalizing if we store both `normal` and `w` raw, then normalize lazily — or just inline the plane construction.

Expected impact: significant on CSG of meshes with thousands of polygons.

---

## 90: CSG: cache AABB on CSGPolygon instead of recomputing per clip

+++
status: new
priority: medium
kind: enhancement
labels: performance, csg
depends: SwiftMesh#85
created: 2026-04-16T03:24:49Z
+++

In `CSGNode.clipPolygons`, every polygon's AABB is rebuilt on every recursion level:

```swift
for polygon in list {
    let polyBounds = AABB(polygon: polygon)  // O(verts) per recursion
    if !bounds.isEmpty, !polyBounds.overlaps(bounds) { ... }
    ...
}
```

A polygon's AABB never changes once built. Cache it on `CSGPolygon`:

```swift
struct CSGPolygon {
    var vertices: [SIMD3<Float>]
    var plane: CSGPlane
    var bounds: AABB  // computed once at init
}
```

Update polygon-producing paths (`splitPolygon`, `toPolygons`, `flipped`) to set bounds at construction. Adds 24 bytes per polygon for substantial recompute savings during deep BSP traversals.

---

## 91: ConvexHull.addPoint rebuilds edgeToFace dictionary every insertion

+++
status: new
priority: medium
kind: enhancement
labels: performance, convex-hull
depends: SwiftMesh#85
created: 2026-04-16T03:24:57Z
+++

`ConvexHull.addPoint` rebuilds the entire `edgeToFace` dictionary on every point insertion:

```swift
var edgeToFace: [Int64: Int] = [:]
for (fIdx, face) in faces.enumerated() {
    let (a, b, c) = face
    edgeToFace[edgeKey(a, b)] = fIdx
    edgeToFace[edgeKey(b, c)] = fIdx
    edgeToFace[edgeKey(c, a)] = fIdx
}
```

For N points this is O(N·F) ≈ O(N²) — the classic gift-wrap-style trap. Standard QuickHull maintains face adjacency incrementally:
- Each face stores its 3 neighbor face indices
- When a face is removed, update neighbor pointers on adjacent faces
- Horizon detection becomes a simple BFS from any visible face

Also `var newFaces: [(Int, Int, Int)] = []` rebuilds the face list each insertion — could mark removed faces and compact periodically, or use indices/free-list.

Expected impact: turns O(N²) hull build into closer to O(N log N) for well-distributed inputs.

---

## 92: HalfEdgeTopology: replace ad-hoc full-array scans with incremental adjacency

+++
status: new
priority: medium
kind: enhancement
labels: performance, topology
depends: SwiftMesh#85
created: 2026-04-16T03:25:08Z
+++

`HalfEdgeTopology` has 10+ instances of `for he in halfEdges where ...` scanning the full half-edge array:

- `collapseEdge`: 3 separate full scans (origin repointing, vertex edge repair, neighbor cleanup)
- Boundary detection: `for he in halfEdges where he.twin == nil`
- Validation routines (acceptable — only run during `validate()`)

These scans turn what should be O(degree) local operations into O(E). For mutating operations (collapse, split, flip) they cause overall complexity to balloon.

Approach:
- Use existing `outgoingHalfEdges(from:)` / vertex ring traversal where possible — these walk `twin.next` and are O(degree)
- For boundary queries, maintain a small set of boundary half-edges (or compute lazily and cache)
- Add a `halfEdges(originatingFrom: VertexID)` helper that uses the ring walk

This issue is a prerequisite for proper performance of #87 (decimation) and any future remesh/edit-mode operations.

---

## 93: Add benchmarking harness for SwiftMesh hot paths

+++
status: new
priority: high
kind: task
labels: performance, infrastructure
depends: SwiftMesh#85
created: 2026-04-16T03:25:18Z
+++

We need a baseline benchmark harness so performance work has measurable targets. Most other performance issues are blocked on this.

Coverage targets:
- CSG operations (union/intersection/difference) on a small, medium, large mesh
- Decimation at several target ratios
- HalfEdgeTopology build from large face soup
- MetalMesh build (interleaved + separate buffers)
- Subdivision (one and two iterations)
- ConvexHull on 100 / 10k / 100k random points
- PLY/OBJ load + save round-trip

Options:
- Apple's `swift-collections-benchmark` package (good for scaling curves)
- `package-benchmark` (Ordo-One) — supports CI gating, allocation counts, instruction counts via jemalloc/perf
- A simple in-repo `Sources/Benchmarks` executable target using `ContinuousClock` for quick iteration

Recommend `package-benchmark` for CI integration but a lightweight custom target may be enough to start.

Once landed: capture baseline numbers, then attach before/after to each performance PR.

---

## 94: Add benchmarks for SwiftMesh hot paths

+++
status: new
priority: medium
kind: task
labels: performance, benchmarks
depends: SwiftMesh#93
created: 2026-04-16T03:27:43Z
+++

Once the benchmarking harness (#93) is in place, add benchmarks covering the major hot paths so performance work has measurable before/after numbers.

Suggested coverage:
- CSG (union, intersection, difference) at small/medium/large mesh sizes
- Decimation at several target ratios
- HalfEdgeTopology build from large face soup
- MetalMesh build (interleaved + separate buffers)
- Subdivision (1, 2, 3 iterations)
- ConvexHull on 100 / 10k / 100k random points
- PLY/OBJ load + save round-trip
- Marching Cubes
- Mesh primitives generation

Also consider:
- A standard fixture corpus (small/medium/large meshes) used across benchmarks
- Allocation count + peak memory tracking
- CI regression gating

---

## 95: MetalMesh: initializers that bypass Mesh / topology

+++
status: closed
priority: medium
kind: feature
created: 2026-04-27T20:01:05Z
updated: 2026-04-27T20:08:48Z
closed: 2026-04-27T20:08:48Z
+++

Today the only way to build a `MetalMesh` is by constructing a full `Mesh` first
and going through `MetalMesh(mesh:device:)`. That path builds a half-edge
topology, dedupes vertices, triangulates faces, etc.

For consumers that already have GPU-ready vertex+index data — e.g. ARKit
mesh anchors loaded from disk, procedural geometry, third-party loaders — the
topology pipeline is wasted work and forces an awkward round-trip through
`Mesh`. It also doesn't fit zero-copy paths where you already have an
`MTLBuffer` produced by `device.makeBuffer(bytes:length:)`.

## Proposed API

Two new `MetalMesh` initializers, both `O(1)` w.r.t. mesh complexity (no
topology, no dedup, no triangulation).

### 1. From attribute arrays

Convenience for the "I have a few `[SIMD3<Float>]` arrays and an index list"
case. Still allocates buffers via `device.makeBuffer`, but skips topology.

```swift
extension MetalMesh {
    public init(
        device: MTLDevice,
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>]? = nil,
        textureCoordinates: [SIMD2<Float>]? = nil,
        indices: [UInt32],
        label: String? = nil,
        bufferLayout: BufferLayout = .interleaved
    )
}
```

Behavior:
- Builds the same `VertexDescriptor` shape `MetalMesh(mesh:device:)` would
  for the same set of attributes (so downstream code that already keys off
  the descriptor keeps working).
- One submesh covering all indices.

### 2. From preexisting buffers (zero-copy)

For loaders that have already produced `MTLBuffer`s and a matching
descriptor (e.g. memory-mapped raw blobs):

```swift
extension MetalMesh {
    public init(
        vertexBuffers: [Int: MTLBuffer],
        vertexCount: Int,
        vertexDescriptor: VertexDescriptor,
        indexBuffer: MTLBuffer,
        indexCount: Int,
        label: String? = nil
    )
}
```

Behavior:
- Stores the buffers and descriptor as-is; no copies, no validation beyond
  cheap shape checks.
- One submesh.

## Non-goals

- No file I/O. Both initializers take in-memory data only. Loading from disk
  / decoding formats stays in the caller.
- No topology recovery. Callers that want a `Mesh` (for editing, dedup,
  wireframe edge extraction) keep going through the existing `Mesh` path.

## Motivation

Real example: a snapshot loader for ARKit mesh anchors reads
`vertices.raw` / `normals.raw` / `faces.raw` from disk into `MTLBuffer`s.
Currently it can't produce a `MetalMesh` without first decoding into
`[SIMD3<Float>]` arrays and constructing a `Mesh` — both of which throw
away the GPU-ready data we already have.

- `2026-04-27T20:08:48Z`: Implemented in this commit.

---

## 96: Add Mesh.merging(_:) / Mesh.merged(meshes:) for combining meshes into one with N submeshes

+++
status: closed
priority: medium
kind: feature
created: 2026-05-13T00:58:35Z
updated: 2026-05-13T01:07:03Z
closed: 2026-05-13T01:07:03Z
+++

It's common to load several MDLMeshes from a single asset (e.g. a USDZ exported from RoomPlan), all sharing the same vertex layout and each having one submesh, and want to merge them into a single Mesh whose submeshes correspond to the source meshes.

There's currently no built-in way to do this — callers have to:

1. Concatenate positions arrays with offsets.
2. Build new HalfEdgeTopology.FaceDefinitions with vertex indices offset to match.
3. Reconstruct corner attributes (normals/UVs/tangents/etc) in the new half-edge order produced by HalfEdgeTopology.init(vertexCount:faces:) — half-edges get re-numbered, so this isn't a simple concatenation.
4. Build the new submeshes referencing the appropriate FaceID ranges.

Step 3 is the part that benefits most from being inside the library — the new init's edge ordering is an internal detail.

Proposed API (one or both):

    public extension Mesh {
        /// Merge another mesh into this one. The other mesh's positions are
        /// appended; its faces become a single new submesh on the result.
        /// Corner attributes are preserved when present in both meshes;
        /// missing attributes on either side are dropped.
        func merging(_ other: Mesh, submeshLabel: String? = nil) -> Mesh

        /// Merge multiple meshes into one with one submesh per source mesh.
        static func merged(_ meshes: [Mesh], submeshLabels: [String?]? = nil) -> Mesh
    }

Constraints / open questions:

- Attribute reconciliation: if mesh A has normals and mesh B doesn't, the merged mesh should probably either drop normals or fill missing ones with a default. Document the chosen behavior; my preference is to drop attributes not present in *all* inputs.
- Per-vertex vs per-corner attributes: today everything except positions is per-corner; that simplifies merging — just emit corner attributes in the new half-edge order.
- Submesh label preservation: if input meshes already have multiple submeshes, the merger should preserve them (offset-shifting their FaceID ranges) rather than collapsing each into one.

Use case: Mac-side viewer in RoomCaptureTestbed loads room.usdz with several MDLMeshes (walls/floor/objects), all single-submesh, identical vertex descriptors. Wants to render them as a single Mesh with one submesh per source for material/styling purposes.

- `2026-05-13T01:06:01Z`: Implemented without label parameters — callers can pre-set `mesh.submeshes` before merging to get labeled submeshes. Final signatures:

```swift
static func merged(_ meshes: [Mesh]) -> Mesh
func merging(_ other: Mesh) -> Mesh
```

Both preserve source submeshes with offset face IDs.

---

## 97: Add a way to extract all MDLMeshes from an MDLAsset as [Mesh]

+++
status: new
priority: low
kind: feature
created: 2026-05-13T01:51:18Z
updated: 2026-05-13T18:51:23Z
+++

Mesh.init(mdlMesh:device:) handles a single MDLMesh, but assets in the wild (USDZ exported from RoomPlan, glTF, etc.) typically contain multiple top-level MDLMeshes — one per object. Today every caller has to walk MDLAsset themselves: iterate asset.object(at:), recurse into children, accumulate MDLMeshes, then loop and call Mesh.init(mdlMesh:device:).

We deliberately don't want a Mesh.init(mdlAsset:) because it would have to make an opinionated choice (merge? pick first? error on multi-mesh assets?). Better: hand back one Mesh per source MDLMesh and let the caller decide.

Proposed API (free function or static on a sequence-shaped container):

    public extension Array where Element == Mesh {
        /// Convert every MDLMesh in an MDLAsset (recursively) into a Mesh.
        /// One Mesh per source MDLMesh. Order matches a depth-first walk of
        /// the asset's object graph.
        init(mdlAsset: MDLAsset, device: MTLDevice) throws
    }

Or as a static on Mesh:

    public extension Mesh {
        static func extractAll(from mdlAsset: MDLAsset, device: MTLDevice) throws -> [Mesh]
    }

Either way the caller can then choose what to do — render separately, run Mesh.merged(_:) with per-source labels, or anything else.

Use case: RoomCaptureTestbed loads a RoomPlan-exported USDZ that contains 79 MDLMesh top-level objects. Today the Mac viewer manually walks asset.object(at:)/.children to gather them; with this API the loader becomes a one-liner and Mesh.merged(...) handles the rest.

---

## 98: Add planar chart partitioning + UV atlas baking via bin packing

+++
status: closed
priority: medium
kind: feature
created: 2026-05-13T18:24:06Z
updated: 2026-05-13T18:40:49Z
closed: 2026-05-13T18:40:49Z
+++

Use case: generate a non-overlapping UV atlas for a `Mesh` so a downstream
renderer can splat per-fragment data (camera/coverage visibility, AO, lightmap,
etc.) into a single 2D texture.

Two layered features (implemented):

## 1. Planar chart partitioning

Region-grow over half-edge twins, merging adjacent faces whose normals (and
plane offsets) are similar. Disconnected coplanar pieces stay in separate
charts.

```swift
public extension Mesh {
    /// A connected, coplanar group of faces.
    struct PlanarChart: Sendable, Equatable {
        public var faces: [HalfEdgeTopology.FaceID]
        /// Average plane normal (area-weighted, unit length).
        public var normal: SIMD3<Float>
        /// In-plane unit vectors forming the chart's local basis.
        public var tangent: SIMD3<Float>
        public var bitangent: SIMD3<Float>
        /// World-space origin used when projecting positions into chart-local UV.
        public var planeOrigin: SIMD3<Float>
        /// Width/height (in world units) of the chart's 2D bounding rect.
        public var worldExtent: SIMD2<Float>
        /// Minimum corner (in plane-local UV) — subtract when projecting.
        public var planeMin: SIMD2<Float>
    }

    func planarCharts(
        normalAngleTolerance: Float = 5 * .pi / 180,
        planeOffsetTolerance: Float = 0.01,
        faces: [HalfEdgeTopology.FaceID]? = nil
    ) -> [PlanarChart]
}
```

## 2. UV atlas baking

Project each chart into its plane basis, bin-pack the 2D bboxes (MaxRects via
`BinPacking`), and write per-corner UVs in [0, 1]² to a new mesh.

```swift
public extension Mesh {
    /// Generate a planar UV atlas. Returns a new mesh with `textureCoordinates`
    /// populated plus the chart layout (so callers can render into the atlas).
    func bakingPlanarAtlas(
        texelsPerMeter: Float = 256,
        atlasSize: SIMD2<Int> = [2048, 2048],
        padding: Int = 2,
        normalAngleTolerance: Float = 5 * .pi / 180,
        planeOffsetTolerance: Float = 0.01
    ) throws -> (mesh: Mesh, atlas: AtlasLayout)
}

public struct AtlasLayout: Sendable {
    public struct ChartPlacement: Sendable {
        public var faces: [HalfEdgeTopology.FaceID]
        /// Chart rectangle in atlas pixels.
        public var atlasRect: BinPacking.Rect<Int>
        public var planeOrigin: SIMD3<Float>
        public var planeU: SIMD3<Float>
        public var planeV: SIMD3<Float>
        public var worldExtent: SIMD2<Float>
        public var planeMin: SIMD2<Float>
        /// True if the chart was rotated 90° during packing.
        public var rotated: Bool
    }
    public var atlasSize: SIMD2<Int>
    public var charts: [ChartPlacement]
}

public enum AtlasBakingError: Error, Sendable {
    case insufficientAtlasSpace(placed: Int, total: Int)
}
```

## Deviations from the original sketch

- `atlasRect` uses `BinPacking.Rect<Int>` (SIMD-native) instead of `CGRect` to
  avoid a Foundation dependency.
- `ChartPlacement` adds `worldExtent`, `planeMin`, and `rotated` so callers can
  map a 3D position back into atlas pixels (needed for the visibility-pass use
  case).
- `bakingPlanarAtlas` throws `AtlasBakingError.insufficientAtlasSpace` instead
  of an unspecified error.

## Bin-packing dependency

Resolved via #99: `SwiftBinPacking` was absorbed into this repo as the
`BinPacking` target.

---

## 99: Merge SwiftBinPacking repo into SwiftMesh

+++
status: closed
priority: medium
kind: task
created: 2026-05-13T18:27:10Z
updated: 2026-05-13T18:28:41Z
closed: 2026-05-13T18:28:41Z
+++

Merge in `~/Projects/Current/SwiftBinPacking` into this repo.

---

## 100: Improve documentation across the repo

+++
status: open
priority: medium
kind: enhancement
created: 2026-05-13T18:40:28Z
updated: 2026-05-13T19:01:19Z
+++

Improve documentation across the whole repo:

- Audit public API for missing or thin doc comments.
- Ensure each target (`SwiftMesh`, `SwiftMeshIO`, `BinPacking`) has a clear top-level overview.
- Add usage examples for common workflows (mesh construction, CSG, decimation, planar charts + atlas baking, IO).
- Consider a DocC catalog with articles and tutorials.
- Update README to reflect current feature set.

---

## 101: Consider dropping SwiftMeshIO / PLY support

+++
status: new
priority: low
kind: task
created: 2026-05-13T19:05:18Z
+++

`SwiftMeshIO` is currently just ASCII PLY read/write (`Sources/SwiftMeshIO/PLY.swift`, ~230 lines).

- **Read:** ModelIO can already load PLY (and supports binary PLY, which our reader doesn't).
- **Write:** ModelIO can't export PLY, so our writer is the only way out \u2014 but only if anyone is actually writing PLY.

Action: check if anything in our projects writes PLY via SwiftMeshIO. If not, drop the target and the dependency; if yes, consider keeping just the writer (or switching reads to ModelIO and slimming the module).

---

## 102: Beef up tests for planarCharts + bakingPlanarAtlas

+++
status: closed
priority: low
kind: enhancement
created: 2026-05-13T20:28:30Z
updated: 2026-05-13T20:36:35Z
closed: 2026-05-13T20:36:35Z
+++

Current coverage in PlanarChartsTests.swift is light (8 @Test cases). The partitioner + atlas baker handle a lot of edge cases that aren't directly exercised. Adding more would help catch regressions and would have helped validate behavior on real RoomPlan-exported USDZ assets where 99% of charts are 2-triangle quads.

Suggested additions:

Partitioning (planarCharts):
- N coplanar connected quads merge into one chart (parameterized N = 2, 4, 10, 100)
- Triangulated polygon fan stays as one chart
- Strip of quads with small accumulating tilt (each pair within tolerance) eventually splits when total tilt exceeds tolerance — verify the split point is correct
- planeOffsetTolerance: two parallel coplanar quads with z offset slightly > tolerance stay separate
- Disconnected coplanar triangle pairs (no shared edges) stay separate even with same normal
- Faces filter: passing an explicit faces: [FaceID] restricts the partitioner to just that subset

Atlas baking:
- Rotated chart packing: a tall narrow chart rotates 90° and its UVs map correctly (sample mid-chart, verify it lands in the right pixel)
- Padding > 0 doesn't bleed: adjacent charts in atlas have at least N pixels between their rects
- Atlas size exactly fits: edge case where total chart area == atlasSize area
- Atlas size 1 px smaller than fits: insufficientAtlasSpace thrown with correct placed/total
- Per-corner UV roundtrip: for every halfedge, the chart-local (u, v) inverse-mapping returns the original world position (within float epsilon)
- UV continuity: shared edges in a chart have matching UVs at both endpoints
- texelsPerMeter scaling: doubling texelsPerMeter scales all chart pixel sizes by 2

Integration:
- Real RoomPlan USDZ smoke test (committed fixture, e.g. a tiny 2-wall scene): assert chart count, total face count, and a few invariants like 'every face appears in exactly one chart'

Also worth: snapshot/golden-image tests for the atlas layout on a few canonical scenes (cube, two-wall L-shape, simple room) to catch unexpected packing regressions.

---

## 103: Add Mesh → RealityKit MeshResource conversion helper

+++
status: new
priority: medium
kind: feature
created: 2026-05-13T20:31:03Z
+++

Need a way to turn a SwiftMesh Mesh into a RealityKit MeshResource so callers can drop our procedurally-built or imported meshes into a RealityView.

Recommendation: put this in **SwiftMeshIO**, not the core SwiftMesh target. RealityKit / RealityFoundation is a platform-only framework and pulls in a lot of weight; keeping core SwiftMesh free of it preserves it as a pure-data library.

Proposed API:

    import RealityKit

    public extension MeshResource {
        /// Convert a SwiftMesh  into a .
        ///
        /// Each  becomes a , preserving its
        /// label as the Part's id/name. The per-corner attributes
        /// (normals, textureCoordinates, tangents) are duplicated to per-vertex,
        /// splitting vertices on attribute discontinuities.
        ///
        /// - Parameters:
        ///   - mesh: The SwiftMesh mesh to convert.
        ///   - generateTangentsIfMissing: When true, derive tangents via MikkTSpace
        ///     if the source mesh has UVs but no tangents.
        /// - Returns: A new MeshResource ready to use with ModelEntity.
        static func generate(from mesh: Mesh,
                             generateTangentsIfMissing: Bool = true) throws -> MeshResource
    }

Implementation notes:

1. SwiftMesh stores normals/UVs/tangents/bitangents/colors *per half-edge corner*.
   MeshResource.Contents wants *per-vertex* arrays. Where two corners on the
   same vertex have differing attributes (sharp edges, UV seams), the corner
   vertex must be duplicated so each corner gets its own per-vertex slot.

2. SwiftMesh's HalfEdgeTopology stores arbitrary polygons; triangulate to
   triangles for MeshResource (which expects triangles in the triangleIndices).
   Triangulation should fan-triangulate convex faces; if the mesh has concave
   faces we already have SwiftEarcut available.

3. Submeshes → Parts. Each Mesh.Submesh becomes one MeshResource.Part with
   triangleIndices restricted to that submesh's faces. Use the submesh label
   as the part id (fallback to a UUID or face-index range if nil).

4. Validate: a Mesh containing only positions should still convert (Parts will
   have no normals; RealityKit can compute or default-shade them).

Use case (RoomCaptureTestbed): we merge a 79-mesh RoomPlan USDZ into one
SwiftMesh.Mesh with 79 labeled submeshes (per SwiftMesh #96). We bake a planar
UV atlas (#98). Now we want to drop the textured mesh into a RealityView,
overlay a baked visibility texture, and inspect it interactively on macOS.
Today that requires going through ModelIO/MTKMesh or hand-rolling MeshResource
construction — having this helper in SwiftMeshIO would short-circuit all that.

---

## 104: Investigate faster bin-packing alternatives to MaxRects for large chart counts

+++
status: new
priority: low
kind: enhancement
created: 2026-05-13T20:45:31Z
updated: 2026-05-13T20:45:57Z
+++

Real-world RoomPlan exports produce 700+ charts (1 chart per RoomPlan surface quad + 6 charts per box object). MaxRects packing takes ~1.2 s for 745 charts on a 4096x4096 atlas in release mode — most of the total bake time.

MaxRects is roughly O(N x M) where M is the free-rect list (grows toward hundreds for large N). For interactive viewers this is borderline; for batch tooling it is fine.

Worth investigating as additions to the BinPacking target:

1. **Skyline / bottom-left packer.** Smaller constant than MaxRects on large N. Density typically comparable.

2. **Guillotine packer.** O(N log N) with good pruning. Density similar to MaxRects, materially faster.

3. **Shelf packer.** O(N log N), much faster, but density usually 50-60% vs 75-85% for MaxRects. Useful when packing density is less important than throughput.

4. **FFD-based strip packer.** Extremely fast O(N log N), 70-80% density.

Approach:

- Add Guillotine and/or Skyline as additional concrete packers alongside MaxRects.
- Each can be its own struct; no need for a packer protocol — callers choose by type.
- bakingPlanarAtlas could grow an overload (or per-packer variant) so atlas baking can opt into a faster algorithm when density is less critical.
- Lean on issue #93 (benchmarks) to compare time and density on representative inputs (uniform-size, mixed-size, very-many-small-rects, a-few-huge-plus-many-tiny).

Use case (RoomCaptureTestbed): interactive Mac viewer that bakes an atlas on bundle open. 1.2 s is OK with caching, but a 0.2-0.3 s alternative would let us skip the cache entirely. Currently see 745 charts on a 4096x4096 atlas getting 78% coverage with MaxRects + bestShortSideFit.

---
