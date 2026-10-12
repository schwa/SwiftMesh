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
status: closed
priority: low
kind: feature
labels: effort:m
created: 2026-04-15T00:51:26Z
updated: 2026-10-11T22:44:56Z
closed: 2026-10-11T22:44:56Z
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
status: closed
priority: low
kind: feature
labels: effort:s
created: 2026-04-15T05:24:28Z
updated: 2026-10-11T22:42:13Z
closed: 2026-10-11T22:42:13Z
+++

Swap the diagonal of two adjacent triangles. Useful for mesh quality improvement and Delaunay-like refinement.

---

## 42: Edge split operation on HalfEdgeTopology

+++
status: closed
priority: medium
kind: feature
labels: effort:m
created: 2026-04-15T05:25:32Z
updated: 2026-10-11T22:12:37Z
closed: 2026-10-11T22:12:37Z
+++

Insert a vertex at an edge midpoint, splitting the two adjacent faces into four. Core editing primitive.

---

## 43: Face extrude operation

+++
status: closed
priority: medium
kind: feature
labels: effort:m
created: 2026-04-15T05:25:33Z
updated: 2026-10-11T22:13:34Z
closed: 2026-10-11T22:13:34Z
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
status: closed
priority: low
kind: feature
labels: effort:l
created: 2026-04-15T05:55:51Z
updated: 2026-10-11T22:49:17Z
closed: 2026-10-11T22:49:17Z
+++

Generate meshes from text strings by converting font glyphs to paths, triangulating the 2D outline, and extruding to 3D. Should support font, size, and extrusion depth parameters.

- `2026-04-15T17:03:10Z`: Related: #49 (extruded Path) — text extrusion could build on Path extrusion.
- `2026-10-11T22:17:54Z`: Mesh.extruded(_: Path/CGPath, depth:) landed in #49; text extrusion can build a CGPath from CTFont glyph outlines and call it.

---

## 49: Mesh from extruded SwiftUI.Path

+++
status: closed
priority: medium
kind: feature
labels: effort:l
created: 2026-04-15T05:56:16Z
updated: 2026-10-11T22:17:54Z
closed: 2026-10-11T22:17:54Z
+++

Generate meshes by triangulating a SwiftUI Path and extruding to 3D. Should handle holes, produce front/back caps and side walls. Could be the foundation for text extrusion (#48) as well.

- `2026-04-15T17:03:10Z`: Related: #48 (extruded text) — could serve as foundation for text extrusion.

---

## 50: Edge fillet (rounding)

+++
status: closed
priority: low
kind: feature
labels: effort:l
created: 2026-04-15T05:57:13Z
updated: 2026-10-12T00:37:58Z
closed: 2026-10-12T00:37:58Z
+++

Round selected edges by replacing them with a smooth arc of faces. Requires edge split and vertex insertion along the edge neighborhood.

- `2026-04-15T17:03:10Z`: Related: #51 (edge chamfer).
- `2026-10-12T00:13:39Z`: Decision: build fillet as a segmented chamfer on top of #51: add a segments parameter (e.g. chamfered(distance:segments:edges:)) that replaces each chamfer strip with N quads following a circular arc between the two offset lines. Vertex corners get a simple patch (fan or grid between the arcs) rather than a true spherical blend. Re-sized from xl to l.

---

## 51: Edge chamfer (beveling)

+++
status: closed
priority: low
kind: feature
labels: effort:l
created: 2026-04-15T05:57:13Z
updated: 2026-10-11T22:51:12Z
closed: 2026-10-11T22:51:12Z
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
status: closed
priority: low
kind: feature
labels: area:demo, effort:s
created: 2026-04-15T06:39:36Z
updated: 2026-10-12T00:32:46Z
closed: 2026-10-12T00:32:46Z
+++

With one edge selected in the demo inspector, "Select Loop" extends the selection to the edge loop through it (Blender-style): at each vertex with exactly 4 edges, continue to the opposite edge; stop at vertices of other valence (poles) and at boundaries. Closed loops stop when they return to the start.

Implementation: library helper HalfEdgeTopology.edgeLoop(from: HalfEdgeID) -> [HalfEdgeID] (unit-tested on cylinder, torus, and a pole-terminated case), plus a Select Loop button in the Selection section next to Select Face Edges. Edge ring and face loop are out of scope.

- `2026-10-11T23:03:05Z`: Related: #117 (selection-based edit buttons).

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
status: closed
priority: high
kind: bug
labels: effort:l
created: 2026-04-15T06:58:03Z
updated: 2026-10-11T21:54:20Z
closed: 2026-10-11T21:54:20Z
+++

BSP-based CSG splits cube faces even when the sphere is entirely interior and doesn't intersect those faces. This creates unnecessary triangulation on flat surfaces that coplanar merging can only partially clean up, since the BSP split introduces true boundary edges where none should exist.

---

## 57: Generic Mesh over Float/Double scalar type

+++
status: open
priority: medium
kind: feature
labels: effort:xl, deferred
created: 2026-04-15T07:09:54Z
updated: 2026-10-12T00:13:27Z
+++

Make Mesh generic over scalar type (Float vs Double). Positions, normals, UVs etc would use the generic scalar. Enables double-precision meshes for CSG and other operations that accumulate floating point error.

- `2026-04-15T17:03:09Z`: Related: #58 (CSG in Double), #59 (Float/Double conversion). #58 and #59 depend on this.
- `2026-10-12T00:13:27Z`: Decision: deferred — revisit later. (#59 stays blocked on this.)

---

## 58: CSG operations in Double precision

+++
status: closed
priority: medium
kind: enhancement
labels: effort:l
created: 2026-04-15T07:09:54Z
updated: 2026-10-11T22:06:03Z
closed: 2026-10-11T22:06:03Z
+++

Run CSG BSP internals in Double precision to reduce vertex drift from plane splitting. Convert back to Float (or keep as Double if Mesh supports it) at the end. Depends on generic Mesh or a separate DoubleMesh type.

- `2026-04-15T17:03:09Z`: Depends on #57 (generic Mesh over scalar type). Related: #59.
- `2026-10-11T22:06:02Z`: Implemented without #57: BSP internals (AABB, CSGPlane, CSGPolygon, splitting) use CSGScalar = Double; TriangleSoup/Mesh stay Float, converted at toPolygons/fromPolygons. Keeping results in Double end-to-end still needs #57.

---

## 59: Float/Double mesh conversion

+++
status: open
priority: medium
kind: feature
labels: effort:m, blocked
created: 2026-04-15T07:09:54Z
updated: 2026-10-11T22:13:41Z
+++

Add conversion between Float and Double precision meshes. MetalMesh only works with Float, so need a way to downconvert Double meshes for GPU use.

- `2026-04-15T17:03:09Z`: Depends on #57 (generic Mesh over scalar type). Related: #58.
- `2026-10-11T22:13:41Z`: Punting: blocked on #57 — there is no Double-precision Mesh type to convert between yet. #58 was done without it (CSG uses Double internally, Float at the API). Unblocker: split/land #57, or decide on a standalone DoubleMesh type instead.

---

## 60: Decimation damages CSG difference mesh (sphere − cube)

+++
status: closed
priority: high
kind: bug
labels: effort:l
created: 2026-04-15T07:40:25Z
updated: 2026-10-11T21:55:01Z
closed: 2026-10-11T21:55:01Z
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
labels: area:csg, umbrella
created: 2026-04-15T07:54:19Z
updated: 2026-10-12T01:22:20Z
+++

CSG union/intersection/difference of two manifold closed meshes should produce a manifold result. Currently the BSP-based algorithm produces meshes with boundary edges and standalone faces due to the TriangleSoup round-trip losing topology. Affected: all CSG operations between closed solids (e.g. cube∪cube, sphere∩cube, sphere−cube).

\- `2026-10-12T00:12:52Z`: Decision: on hold. Before choosing between post-process repair and a new boolean algorithm, find better references (papers / robust mesh-boolean approaches) to base the design on.
\- `2026-10-12T00:16:46Z`: Research notes (references verified via Crossref / project docs):

A. Manifold-by-construction, floating point: Julian Smith's dissertation 'Robust Boolean' (docs/RobustBoolean.pdf in the Manifold repo), implemented in the Manifold library (github.com/elalish/manifold, Apache-2.0). Each geometric decision is derived from earlier ones so the same question is never asked twice; symbolic perturbation breaks ties for coplanar/coincident faces. Guarantees manifold output for manifold input, no exact arithmetic. Production-proven (OpenSCAD, Blender adopted it).

B. Exact arrangements + winding numbers: Zhou, Grinspun, Zorin, Jacobson, 'Mesh arrangements for solid geometry', TOG 2016, doi:10.1145/2897824.2925901 (libigl). Cherchi, Livesu, Scateni, Attene, 'Fast and robust mesh arrangements using floating-point arithmetic', TOG 2020, doi:10.1145/3414685.3417818 (indirect predicates). Cherchi, Pellacini, Attene, Livesu, 'Interactive and Robust Mesh Booleans', TOG 2022, doi:10.1145/3550454.3555460. Handles self-intersecting/non-manifold input; needs exact or indirect predicates (Shewchuk 1997, doi:10.1007/pl00009321) and Jacobson et al. generalized winding numbers (TOG 2013, doi:10.1145/2461912.2461916).

C. Plane-based exact Booleans (closest to our BSP): Bernstein & Fussell, 'Fast, Exact, Linear Booleans', CGF 2009, doi:10.1111/j.1467-8659.2009.01504.x. Campen & Kobbelt, 'Exact and Robust (Self-)Intersections for Polygonal Meshes', CGF 2010, doi:10.1111/j.1467-8659.2009.01609.x. Nehring-Wirxel, Trettner, Kobbelt, 'Fast Exact Booleans for Iterated CSG using Octree-Embedded BSPs', CAD 2021, doi:10.1016/j.cad.2021.103015. Trettner, Nehring-Wirxel, Kobbelt, 'EMBER: Exact Mesh Booleans via Efficient & Robust Local Arrangements', TOG 2022, doi:10.1145/3528223.3530181. Represent geometry as plane equations with integer coordinates, so BSP splits are exact and outputs are watertight.

Also: Barki, Guennebaud, Foufou, 'Exact, robust, and efficient regularized Booleans on general 3D meshes', CAMWA 2015, doi:10.1016/j.camwa.2015.06.016.

- `2026-10-12T00:18:58Z`: Decision: approach A — port the Smith 'Robust Boolean' algorithm (as implemented in Manifold, Apache-2.0) to pure Swift, replacing the BSP CSG. No C++ dependency. Too large for one issue: split into subtasks before starting (e.g. robust predicates/symbolic perturbation, intersection + broad phase, edge/face retention and winding, polygon assembly + triangulation, degenerate removal, attribute mapping, Mesh API switch-over with the existing CSG tests as the acceptance suite).
- `2026-10-12T01:22:20Z`: Split into subtasks (in dependency order): #122, #123, #124, #125, #126, #127, #128, #129, #130. #65 is now the umbrella; it closes with the last subtask.

---

## 66: Add split-by-plane operation

+++
status: closed
priority: medium
kind: feature
labels: effort:l
created: 2026-04-15T07:54:33Z
updated: 2026-10-11T22:16:35Z
closed: 2026-10-11T22:16:35Z
+++

Split a mesh along an arbitrary plane, producing two separate meshes (one for each side). Faces straddling the plane should be clipped and capped.

- `2026-04-15T14:21:46Z`: Add option to heal (cap) the cut faces after splitting.

---

## 67: Add mesh diagnostic API (is/has-style queries)

+++
status: closed
priority: medium
kind: feature
labels: effort:m
created: 2026-04-15T14:12:08Z
updated: 2026-10-11T22:14:28Z
closed: 2026-10-11T22:14:28Z
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
- `2026-10-11T22:14:27Z`: Implemented all remaining items except hasNonMatchingFaceEdgeCounts: faces don't store a degree, so there's nothing to compare the loop count against. Euler/genus and winding stay in #75/#76.

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
status: closed
priority: low
kind: feature
labels: effort:m
created: 2026-04-15T14:14:11Z
updated: 2026-10-11T22:46:15Z
closed: 2026-10-11T22:46:15Z
+++

Integrate debug shaders from MetalSprocketsAddons to visualize mesh topology in the demo app. Include: normal visualization (lines or color-mapped), wireframe overlay, face winding display, boundary edge highlighting, vertex valence heatmap.

- `2026-10-11T22:46:15Z`: Normals, face normal, wireframe overlay, and winding (Front Facing) were already in the demo via the AddOns debug shaders. Added Valence Heatmap and Boundary Edges render modes: the AddOns shaders have no vertex-color mode, so the topology data is encoded into texture coordinates and drawn with Tex Coords mode (u, v, 0 as RGB). Builds; not visually verified by me — please check alongside the #83 demo pass.

---

## 71: Support extrusion modes: solid, walls only, thin walls

+++
status: closed
priority: medium
kind: feature
labels: area:extrude, effort:m
created: 2026-04-15T14:20:40Z
updated: 2026-10-12T00:23:45Z
closed: 2026-10-12T00:23:45Z
+++

Add an extrusion mode parameter to Mesh.extruded(_: Path/CGPath, depth:) and Mesh.extrudedText:

    enum ExtrusionMode { case solid, wallsOnly, thinWalls(thickness: Float) }

- solid (default, current behavior): front/back caps plus side walls, closed.
- wallsOnly: side walls only, no caps; an open band per outline (fences, room walls from a floor plan).
- thinWalls(thickness:): each outline becomes a closed wall of the given thickness: offset the loop inward by thickness (miter joins), extrude the band between original and offset, cap top and bottom of the band. Holes offset the same way (toward the material).

Known limitation, documented: the miter offset doesn't resolve self-intersections at sharp concave corners or when thickness exceeds local feature size.

Tests: solid unchanged; wallsOnly has 2 boundary loops per outline and no caps; thinWalls on a rectangle is a closed genus-1 solid with the expected inner dimensions.

- `2026-10-12T01:11:04Z`: Follow-up for the miter-offset limitation: #121.

---

## 72: Heal holes

+++
status: closed
priority: medium
kind: feature
labels: area:topology, effort:s
created: 2026-04-15T14:20:52Z
updated: 2026-10-12T00:22:06Z
closed: 2026-10-12T00:22:06Z
+++

Add Mesh.fillingHoles(maxEdges: Int? = nil) -> Mesh that closes boundary loops with new faces.

- Fill: one n-gon face per boundary loop, wound to twin the loop's boundary half-edges (so the result is consistently oriented). Callers triangulate later if needed; non-planar holes are handled by the triangulator's projection.
- Scope: fills every boundary loop by default; maxEdges skips loops with more edges (keeps intentional openings, e.g. a hemisphere rim, open).
- Per-corner attributes on the new face: regenerate or leave as for other topology changes (decide during implementation; document it).
- Out of scope: smooth/faired patches, holes with islands.

Tests: a cube with one face removed becomes closed and manifold again; maxEdges smaller than the hole leaves it open; a mesh with two holes fills both; the filled mesh has no inconsistent winding.

---

## 73: Unify per-corner attribute handling into a reusable remapping layer

+++
status: closed
priority: medium
kind: enhancement
labels: architecture, refactor, effort:l
created: 2026-04-15T15:38:03Z
updated: 2026-10-11T22:07:48Z
closed: 2026-10-11T22:07:48Z
+++

Every file that touches per-corner attributes (normals, textureCoordinates, tangents, bitangents, colors) manually zips/copies/remaps 5–6 optional arrays in lockstep. This boilerplate is duplicated across welding, triangulation, MetalMesh conversion, PLY export, subdivision, and coplanar merge. Adding a new attribute (e.g. bone weights) requires touching 8+ files.

Proposal: introduce a single abstraction (e.g. CornerAttributes or AttributeTable) that owns the optional per-corner arrays and exposes operations like remap(by:), subset(indices:), append(from:), and average(indices:). All current consumers would delegate to this layer instead of hand-rolling the same if-let/zip/copy loops.

Affected files: Mesh.swift (welded), Triangulation.swift (triangulated), MetalMesh.swift (init, toMesh), MeshAttributes.swift (withTangents), MeshOptimization.swift (mergingCoplanarFaces), PLY.swift (write), Subdivision.swift (attributes stripped).

Dependency category: In-process (pure data, no I/O).

Test impact: A single boundary test on the attribute-remapping API would replace scattered attribute-plumbing assertions across MeshTests, MeshAttributesTests, TriangulationTests, MetalMeshTests, and PLYTests.

- `2026-10-11T22:07:48Z`: Added internal CornerAttributes (gathered/concatenated/apply) plus HalfEdgeTopology.rebuildCornerOrder(for:), and moved welded, triangulated, merged, and decimation compact onto it. Not migrated: MetalMesh init/toMesh and PLY (per-semantic byte/format code, PLY is normals-only and in SwiftMeshIO), mergingCoplanarFaces and subdivision (they drop attributes; carrying them is new behavior, not plumbing). File follow-ups if those should carry attributes.

---

## 74: Simplify CSG conversion pipeline

+++
status: closed
priority: low
kind: enhancement
labels: architecture, refactor, effort:l
created: 2026-04-15T15:38:15Z
updated: 2026-10-11T22:41:05Z
closed: 2026-10-11T22:41:05Z
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

- `2026-10-11T22:41:05Z`: Done: one pipeline (Mesh.csg(_:_:options:)) behind union/intersection/difference; CSGOptions gathers weld and coplanar tolerances plus mergeCoplanar; options.attributes re-derives normals/UVs on the result. Welding already happens once on the mesh path. Not done: removing the TriangleSoup→CSGPolygon round-trip — triangulating to a soup is what makes non-convex n-gons valid BSP input, and the BSP epsilon stays internal. Noticed CSG output vertex/face order varies call to call (filed separately).

---

## 75: Implement Euler characteristic and genus computation

+++
status: closed
priority: low
kind: feature
labels: effort:m, area:topology, area:diagnostics
created: 2026-04-15T15:43:32Z
updated: 2026-10-11T22:47:29Z
closed: 2026-10-11T22:47:29Z
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
status: closed
priority: low
kind: feature
labels: effort:m, area:topology, area:diagnostics
created: 2026-04-15T15:43:40Z
updated: 2026-10-11T22:48:36Z
closed: 2026-10-11T22:48:36Z
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
status: closed
priority: low
kind: feature
labels: effort:l
created: 2026-04-15T16:08:59Z
updated: 2026-10-11T22:51:51Z
closed: 2026-10-11T22:51:51Z
+++

Compute the convex hull of a set of 3D spheres (point + radius), returning a Mesh. This is the Minkowski sum of the convex hull of the centers with a sphere — effectively rounding the edges and vertices of the hull. Depends on #77 (convex hull from points).

- `2026-04-15T17:03:10Z`: Depends on #77 (convex hull from points).
- `2026-10-11T22:51:51Z`: Implemented by sampling each sphere with icosphere vertices and hulling the samples, so it works for mixed radii (where the result is not the centers' hull plus one radius, as the description suggests). Approximate from the inside; subdivisions controls fidelity.

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
status: closed
priority: high
kind: bug
labels: area:decimation, area:topology, effort:m
created: 2026-04-15T17:48:08Z
updated: 2026-10-11T21:51:41Z
closed: 2026-10-11T21:51:41Z
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
status: closed
priority: medium
kind: task
labels: area:qa, area:demo, effort:m
created: 2026-04-15T18:06:36Z
updated: 2026-10-12T01:11:16Z
closed: 2026-10-12T01:11:16Z
+++

Go through every mesh in the demo gallery and verify they render correctly in both wireframe and Metal (Blinn-Phong) modes. Check for:
- Correct shape and proportions
- No inside-out faces or flipped normals
- Proper UV mapping (use Tex Coords / Checkerboard debug modes)
- Capped vs uncapped variants look right
- CSG results are clean
- Subdivision results are smooth
- Decimated meshes degrade gracefully

- `2026-10-11T22:19:56Z`: Automated part done: PrimitiveOrientationTests checks every primitive's corner normals against face winding and that convex solids face outward. It found tetrahedron, sphere, cylinder, capsule, conicalFrustum, rectangularFrustum fully inside-out (winding and normals); fixed via Mesh.reversingWinding(). Still needs a human pass in the demo: UV/checkerboard look, CSG cleanliness, subdivision smoothness, decimation degradation.
- `2026-10-12T01:11:16Z`: Closing per user: visual review called good for now. Automated coverage stays in PrimitiveOrientationTests.

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
status: closed
priority: medium
kind: task
labels: umbrella, area:performance, effort:xs
created: 2026-04-16T03:22:42Z
updated: 2026-10-12T00:13:49Z
closed: 2026-10-12T00:13:49Z
+++

Umbrella issue tracking performance work across SwiftMesh.

Child issues will be filed for specific hotspots and investigations (CSG, decimation, topology build, I/O, Metal upload, allocations, benchmarking harness, etc.).

Use this issue to coordinate priorities and link related sub-issues.

- `2026-10-12T00:13:49Z`: Closing: children #87-#94 are done; remaining performance work (#86, #104) stands on its own.

---

## 86: Swift Array is slow in hot paths — explore Spans and swift-collections

+++
status: closed
priority: medium
kind: enhancement
labels: area:performance, effort:l
depends: SwiftMesh#85
created: 2026-04-16T03:22:53Z
updated: 2026-10-12T00:31:16Z
closed: 2026-10-12T00:31:16Z
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

- `2026-10-11T22:08:30Z`: Punting: open-ended investigation and it proposes a new dependency (swift-collections), which needs your decision. Since filing, the algorithmic hot spots were fixed (#87 decimation scans, #88 MetalMesh dedup, #89/#90 CSG allocations) and the harness (#93) exists. Current medians (release): topology.build.icoSphere5 3.4 ms, decimate.icoSphere5.25% 40.9 ms, csg.difference.sphere-cube 20.4 ms. Unblocker: OK to add swift-collections? And/or pick one concrete target (e.g. 'decimate 2x faster') so this can be scoped into a fixable issue.
- `2026-10-12T00:11:57Z`: Decision: swift-collections is allowed as a dependency where it clearly helps (Deque, OrderedSet/OrderedDictionary, etc.), alongside stdlib Span/MutableSpan/ContiguousArray. Work is benchmark-driven using SwiftMeshBenchmarks: profile the slowest benchmarks, change one hot path at a time, keep changes only with a measured win (include before/after medians in the commit).
- `2026-10-12T00:31:16Z`: Done via profiling (sample) + SwiftMeshBenchmarks. Wins came from removing per-call Set/Dictionary hashing and redundant math, not from new collection types: swift-collections was allowed but no profiled hot spot needed Deque/OrderedSet, so no dependency was added. Medians before -> after are in the commit.

---

## 87: Decimation: O(V·E) full half-edge scans per collapse

+++
status: closed
priority: high
kind: enhancement
labels: area:performance, area:decimation, effort:l
depends: SwiftMesh#85
created: 2026-04-16T03:24:19Z
updated: 2026-10-11T21:58:46Z
closed: 2026-10-11T21:58:46Z
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
status: closed
priority: high
kind: enhancement
labels: area:performance, area:metal, effort:m
depends: SwiftMesh#85
created: 2026-04-16T03:24:31Z
updated: 2026-10-11T21:55:39Z
closed: 2026-10-11T21:55:39Z
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
status: closed
priority: medium
kind: enhancement
labels: area:performance, area:csg, effort:m
depends: SwiftMesh#85
created: 2026-04-16T03:24:43Z
updated: 2026-10-11T22:04:28Z
closed: 2026-10-11T22:04:28Z
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

- `2026-10-11T22:04:28Z`: Fixed allPolygons (inout accumulator), clipPolygons concat, and splitPolygon (types array only built for spanning polygons; split vertex arrays reserved). Did not change toPolygons plane construction: classification epsilon assumes unit normals, so lazy normalization would change semantics; normalization is not the hot spot after these changes.

---

## 90: CSG: cache AABB on CSGPolygon instead of recomputing per clip

+++
status: closed
priority: medium
kind: enhancement
labels: area:performance, area:csg, effort:s
depends: SwiftMesh#85
created: 2026-04-16T03:24:49Z
updated: 2026-10-11T22:03:30Z
closed: 2026-10-11T22:03:30Z
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
status: closed
priority: medium
kind: enhancement
labels: area:performance, area:convex-hull, effort:l
depends: SwiftMesh#85
created: 2026-04-16T03:24:57Z
updated: 2026-10-11T22:10:35Z
closed: 2026-10-11T22:10:35Z
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
status: closed
priority: medium
kind: enhancement
labels: area:performance, area:topology, effort:l
depends: SwiftMesh#85
created: 2026-04-16T03:25:08Z
updated: 2026-10-11T22:11:21Z
closed: 2026-10-11T22:11:21Z
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

- `2026-10-11T22:11:21Z`: collapseEdge scans were removed in #87 (outgoing table). deleteEdge now repairs endpoint edge refs from the local successor edges (O(1)), scanning only as a fallback. Remaining full scans are whole-mesh queries (validate, isManifold, boundaryLoops, undirectedEdges) where O(E) is inherent; no caching added.

---

## 93: Add benchmarking harness for SwiftMesh hot paths

+++
status: closed
priority: high
kind: task
labels: area:performance, area:infrastructure, effort:m
depends: SwiftMesh#85
created: 2026-04-16T03:25:18Z
updated: 2026-10-11T22:02:40Z
closed: 2026-10-11T22:02:40Z
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
status: closed
priority: medium
kind: task
labels: area:performance, area:benchmarks, effort:m
depends: SwiftMesh#93
created: 2026-04-16T03:27:43Z
updated: 2026-10-11T22:21:37Z
closed: 2026-10-11T22:21:37Z
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

- `2026-10-11T22:21:37Z`: Added 31 benchmarks: primitives, topology build, CSG union/intersection/difference × small/medium/large, decimation 50/25/10%, Loop and Catmull-Clark x1-3, convex hull 100/10k/100k, marching cubes 32/64, MetalMesh interleaved/separate, PLY round-trip. Not done: OBJ round-trip (no OBJ writer API), allocation/peak-memory tracking, CI gating, shared fixture corpus — the issue lists these under 'also consider'; file follow-ups if wanted.

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

\- `2026-05-13T01:06:01Z`: Implemented without label parameters — callers can pre-set `mesh.submeshes` before merging to get labeled submeshes. Final signatures:

```swift
static func merged(_ meshes: [Mesh]) -> Mesh
func merging(_ other: Mesh) -> Mesh
```

Both preserve source submeshes with offset face IDs.

---

## 97: Add a way to extract all MDLMeshes from an MDLAsset as [Mesh]

+++
status: closed
priority: low
kind: feature
labels: area:io, effort:s
created: 2026-05-13T01:51:18Z
updated: 2026-10-11T22:43:00Z
closed: 2026-10-11T22:43:00Z
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
status: closed
priority: medium
kind: documentation
labels: effort:l, area:docs
created: 2026-05-13T18:40:28Z
updated: 2026-10-11T22:22:18Z
closed: 2026-10-11T22:22:18Z
+++

Improve documentation across the whole repo:

- Audit public API for missing or thin doc comments.
- Ensure each target (`SwiftMesh`, `SwiftMeshIO`, `BinPacking`) has a clear top-level overview.
- Add usage examples for common workflows (mesh construction, CSG, decimation, planar charts + atlas baking, IO).
- Consider a DocC catalog with articles and tutorials.
- Update README to reflect current feature set.

- `2026-10-11T22:22:18Z`: README refreshed: fixed stale API (validate, marchingCubes, wireframe, MetalMesh perf note), documented new Editing/Diagnostics APIs, path extrusion, reversingWinding, Submesh index/primitive types, CSG precision and watertightness caveat, decimation behavior, benchmark coverage. Doc comment audit + DocC split into the follow-up issue.

---

## 101: Consider dropping SwiftMeshIO / PLY support

+++
status: closed
priority: low
kind: task
labels: area:io, effort:s
created: 2026-05-13T19:05:18Z
updated: 2026-10-12T00:12:09Z
closed: 2026-10-12T00:12:09Z
+++

`SwiftMeshIO` is currently just ASCII PLY read/write (`Sources/SwiftMeshIO/PLY.swift`, ~230 lines).

- **Read:** ModelIO can already load PLY (and supports binary PLY, which our reader doesn't).
- **Write:** ModelIO can't export PLY, so our writer is the only way out \u2014 but only if anyone is actually writing PLY.

Action: check if anything in our projects writes PLY via SwiftMeshIO. If not, drop the target and the dependency; if yes, consider keeping just the writer (or switching reads to ModelIO and slimming the module).

- `2026-10-12T00:12:08Z`: Decision: keep SwiftMeshIO as is. It now has ASCII + binary PLY read/write (#9) and RealityKit MeshResource export.

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
status: closed
priority: medium
kind: feature
created: 2026-05-13T20:31:03Z
updated: 2026-05-13T20:41:42Z
closed: 2026-05-13T20:41:42Z
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
status: closed
priority: low
kind: enhancement
labels: area:binpacking, effort:l
created: 2026-05-13T20:45:31Z
updated: 2026-10-12T00:36:04Z
closed: 2026-10-12T00:36:04Z
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

- `2026-10-12T00:12:25Z`: Decision: optimize, target < 200 ms for a ~745-chart RoomPlan-like case in a 4096x4096 atlas (release). First add that case to SwiftMeshBenchmarks (synthetic chart sizes matching RoomPlan: ~1 chart per surface quad + 6 per box). Then speed up MaxRects (cheaper free-rect pruning, spatial index over free rects) and/or add a skyline packer if MaxRects can't get there; report atlas fill rate alongside time.

---

## 105: Mesh.merged produces invalid half-edge twin pointers, breaking validation

+++
status: closed
priority: high
kind: bug
created: 2026-05-13T20:50:52Z
updated: 2026-05-13T20:56:43Z
closed: 2026-05-13T20:56:43Z
+++

When merging N SwiftMesh meshes into one via Mesh.merged(_:), the resulting mesh's HalfEdgeTopology has invalid twin links at submesh boundaries. validate() reports many 'Twin H168 points back to H197 instead of H67' errors.

In a correct half-edge mesh: if A.twin == B then B.twin == A. After merging, that bidirectional consistency is broken — likely because two faces from different source meshes that share a vertex are now seen as adjacent across an edge they never shared in their source meshes, getting incorrectly twinned together.

Repro: merge 79 small meshes (RoomPlan USDZ export — walls, doors, windows, objects). Mesh.merged returns a Mesh that draws fine, packs fine into a UV atlas, etc. but fails mesh.validate() with many twin-mismatch errors.

This blocks MeshResource.generate(from:) in SwiftMeshIO because it (correctly) validates before doing per-vertex deduplication and triangulation.

Fix idea: HalfEdgeTopology.init(vertexCount:faces:) uses an edge map keyed on (origin, dest) vertex pairs to find twins. When merging, two unrelated source meshes might have faces that share two vertex indices in the merged result (because the merge appends positions and offsets indices, but if two source meshes happen to place vertices at the same (offset+localIndex) coordinate the edge map collides). The fix is likely in the merge step to ensure source meshes that aren't topologically connected don't accidentally get edges twinned across the merge boundary.

Workaround for callers: call .triangulate() or .makingValid() (if such a thing exists) after merging, or re-run init(vertexCount:faces:) from face definitions to rebuild topology from scratch.

---

## 106: Detect and warn on non-manifold edges in HalfEdgeTopology

+++
status: closed
priority: low
kind: enhancement
labels: area:topology, effort:s
created: 2026-05-13T20:56:07Z
updated: 2026-10-11T22:39:38Z
closed: 2026-10-11T22:39:38Z
+++

After the fix for #SwiftMesh#105, HalfEdgeTopology.init(vertexCount:faces:) silently accepts non-manifold edges (\u22653 half-edges sharing an undirected edge). The first two half-edges along such an edge are paired as twins; any extras are left as boundary (twin = nil).

This is structurally consistent but hides genuinely broken input geometry. Callers that walk boundaries (e.g. boundaryLoops()) will see internal non-manifold edges as boundaries, which may be surprising.

Suggested: add a HalfEdgeTopology.validate() warning (severity .warning, not .error) of the form 'edge V_a-V_b has N>2 incident half-edges'. This lets callers detect non-manifold input without breaking validation for downstream consumers (e.g. MeshResource export in SwiftMeshIO) that just need consistent twin pointers.

Out of scope: actually supporting non-manifold edges as first-class topology (multi-twin lists, edge splitting). File a separate issue if that's needed.

---

## 107: Namespace the MikkTSpace target under SwiftMesh

+++
status: closed
priority: medium
kind: none
created: 2026-10-05T15:05:50Z
updated: 2026-10-05T19:37:30Z
closed: 2026-10-05T19:37:30Z
+++

Rename the MikkTSpace target (declared in Package.swift, sources in Sources/MikkTSpace) so it is namespaced by SwiftMesh, e.g. SwiftMeshMikkTSpace. Update the target name, its path/directory, and all dependency references so the package still builds.

---

## 108: MetalMesh.Submesh only supports UInt32 triangles

+++
status: closed
priority: high
kind: enhancement
labels: effort:m, area:metal
created: 2026-10-11T21:48:24Z
updated: 2026-10-11T21:56:46Z
closed: 2026-10-11T21:56:46Z
+++

MetalMesh.Submesh has an index buffer and count but no index type or primitive type. Every MetalMesh init writes UInt32 triangle indices, so renderers hardcode .uint32 and .triangle.

This blocks meshes with UInt16 indices, lines, points, or strips (common in glTF), and wastes memory for small meshes.

Want: add indexType (MTLIndexType) and primitiveType (MTLPrimitiveType) to MetalMesh.Submesh, defaulting to .uint32/.triangle, and let the direct init accept other values.

Found while fixing MetalSprocketsSceneGraph #22.

---

## 109: MetalMesh ignores MTKSubmesh index buffer offset

+++
status: closed
priority: medium
kind: bug
labels: area:metal, effort:s
created: 2026-10-11T21:56:53Z
updated: 2026-10-11T22:36:45Z
closed: 2026-10-11T22:36:45Z
+++

MetalMesh(mtkMesh:) uses sub.indexBuffer.buffer but drops sub.indexBuffer.offset. MTKMeshBufferAllocator can pack several submeshes into one buffer, so indices would be read from the wrong place. Add indexBufferOffset to MetalMesh.Submesh and honor it in readers. Found while fixing #108.

---

## 110: Audit public doc comments and add a DocC catalog

+++
status: closed
priority: low
kind: documentation
labels: area:docs, effort:l
created: 2026-10-11T22:22:18Z
updated: 2026-10-11T22:55:16Z
closed: 2026-10-11T22:55:16Z
+++

Follow-up from #100 (README refreshed there). Remaining: audit public API for missing or thin doc comments (SwiftMesh, SwiftMeshIO, BinPacking), add a top-level overview per target, and consider a DocC catalog with articles for mesh construction, CSG, decimation, atlas baking, and IO.

- `2026-10-11T22:55:16Z`: Added DocC catalogs with curated landing pages for SwiftMesh, SwiftMeshIO, and BinPacking, filled public doc comment gaps, and fixed existing parameter/link warnings. Verified with emitted symbol graphs + docc convert --analyze: 0 warnings per target. No swift-docc-plugin added (would be a new dependency); generate with Xcode or xcrun docc.

---

## 111: MetalMesh ignores MTKMesh vertex buffer offsets

+++
status: closed
priority: medium
kind: bug
labels: area:metal, effort:s
created: 2026-10-11T22:36:45Z
updated: 2026-10-11T22:57:29Z
closed: 2026-10-11T22:57:29Z
+++

MetalMesh(mtkMesh:) stores mtkBuffer.buffer per vertex buffer index but drops mtkBuffer.offset, and draw(_:) binds vertex buffers at offset 0. If MTKMeshBufferAllocator sub-allocates vertex data, attributes are read from the wrong place. Add per-buffer offsets (e.g. vertexBufferOffsets: [Int: Int]) and honor them in draw(_:), toMesh(), and toMDLMesh. Found while fixing #109.

---

## 112: Decimation can create non-manifold edges

+++
status: closed
priority: medium
kind: bug
labels: area:decimation, effort:s
created: 2026-10-11T22:37:27Z
updated: 2026-10-11T22:39:38Z
closed: 2026-10-11T22:39:38Z
+++

Mesh.decimate collapses edges without checking the link condition, so it can create edges with 3+ incident half-edges. Repro: icoSphere(subdivisions: 3).decimated(ratio: 0.25).validate() reports a non-manifold edge warning (surfaced by #106). Fix: skip collapses where the endpoints share neighbors other than the opposite vertices of the edge's adjacent faces.

---

## 113: CSG output order is nondeterministic

+++
status: closed
priority: low
kind: bug
labels: area:csg, effort:s
created: 2026-10-11T22:41:05Z
updated: 2026-10-11T22:59:09Z
closed: 2026-10-11T22:59:09Z
+++

Calling the same Mesh CSG operation twice can return meshes with the same geometry but different vertex/face order (Mesh == fails). Likely Dictionary/Set iteration in welding or coplanar merge. Makes exports and snapshot tests non-reproducible. Found while fixing #74.

---

## 114: Demo: add Editing gallery section

+++
status: closed
priority: medium
kind: feature
labels: area:demo, effort:m
created: 2026-10-11T23:02:40Z
updated: 2026-10-11T23:05:42Z
closed: 2026-10-11T23:05:42Z
+++

Add a gallery section showing the editing operations, each as before/after pairs where useful:\n- Edge split (Mesh.splitEdge, #42) on a cube and an icosphere\n- Edge flip (Mesh.flipEdge, #41) on a quad strip\n- Face extrude (Mesh.extrudingFace, #43): one face of a box, plus a negative distance\n- Chamfer (Mesh.chamfered, #51): all edges of a box, one edge of a box, icosahedron\n- Plane split (Mesh.split(planeNormal:point:capped:), #66): sphere capped and uncapped, torus cut showing an annulus cap

---

## 115: Demo: add Extrusion & construction gallery section

+++
status: closed
priority: medium
kind: feature
labels: area:demo, effort:s
created: 2026-10-11T23:02:40Z
updated: 2026-10-11T23:04:22Z
closed: 2026-10-11T23:04:22Z
+++

Add a gallery section for newer constructors:\n- Path extrusion (Mesh.extruded(Path), #49): star, rounded rect, shape with a hole\n- Text extrusion (Mesh.extrudedText, #48): a word with holes, e.g. "SwiftMesh"\n- Hull of spheres (Mesh.convexHull(ofSpheres:), #78): equal radii (capsule) and mixed radii

---

## 116: Demo: inspector diagnostics panel and repair actions

+++
status: closed
priority: medium
kind: feature
labels: area:demo, effort:m
created: 2026-10-11T23:02:41Z
updated: 2026-10-11T23:06:35Z
closed: 2026-10-11T23:06:35Z
+++

The inspector shows counts but none of the diagnostics API. Add a panel showing, for the current mesh: Euler characteristic, components with genus and orientability (surfaceComponents, #75), boundary loop count, inconsistent winding edge count (#76), non-manifold edge warnings and other validate() issues (#106), valence histogram (#67).\n\nAdd repair/operation buttons: Fix Winding (withConsistentWinding), Reverse Winding, Merge Coplanar Faces. Pairs with the Valence Heatmap / Boundary Edges render modes from #70.

---

## 117: Demo: selection-based edit buttons in inspector

+++
status: closed
priority: low
kind: feature
labels: area:demo, effort:m
created: 2026-10-11T23:02:41Z
updated: 2026-10-11T23:08:26Z
closed: 2026-10-11T23:08:26Z
+++

Edge and face selection already exist in the inspector but nothing acts on them. Add buttons: Split Edge and Flip Edge for a selected edge, Chamfer Selected Edges, Extrude Selected Face (with a distance field). Disable buttons when the selection doesn't fit (e.g. flip on a boundary edge returns false).

- `2026-10-11T23:03:05Z`: Related: #54 (Select Loop in the inspector) — both extend inspector selection tooling.

---

## 118: Demo: atlas baking and IO samples

+++
status: closed
priority: low
kind: feature
labels: area:demo, effort:s
created: 2026-10-11T23:02:41Z
updated: 2026-10-11T23:07:51Z
closed: 2026-10-11T23:07:51Z
+++

No gallery item shows planar atlas baking (bakingPlanarAtlas): add one that renders the baked UVs with the checkerboard/UV grid debug mode. For IO: add Export as PLY (ASCII/binary, #9) to the inspector, and when importing an asset with several objects use [Mesh](mdlAsset:) (#97) and show them merged with per-object submeshes.

---

## 119: Demo: add .help() tooltips to inspector fields and actions

+++
status: closed
priority: low
kind: enhancement
labels: area:demo, effort:s
created: 2026-10-11T23:14:02Z
updated: 2026-10-11T23:17:14Z
closed: 2026-10-11T23:17:14Z
+++

Every inspector control and readout should explain itself on hover via .help():\n- Info: vertices, faces, edges, half-edges, submeshes, manifold, standalone faces (what each means, e.g. half-edges = 2 per interior edge).\n- Diagnostics (#116): Euler characteristic, components/genus/orientability, boundary loops, bad winding edges, validation, valence histogram. Say what a good value is (e.g. 'genus 0 = sphere-like').\n- Attributes: what normals/UVs/tangents/bitangents/colors are and that they're per-corner.\n- Operations: what each button does and its side effects (Weld tolerance, Triangulate, Loop vs Catmull-Clark, Decimate ratio, Wireframe, Border inside/outside, Fix/Reverse Winding, Merge Coplanar), and Reset.\n- Selection edits (#117): Split, Flip (and why it may be disabled), Chamfer and its slider, Extrude and its slider, Select Connected/Face Edges.\n- Toggles: Highlight Standalone, Vertex Dots.

---

## 120: Demo: add .help() tooltips to gallery items, sections, and toolbar

+++
status: closed
priority: low
kind: enhancement
labels: area:demo, effort:s
created: 2026-10-11T23:14:02Z
updated: 2026-10-11T23:18:37Z
closed: 2026-10-11T23:18:37Z
+++

Add hover help outside the inspector:\n- Gallery items: a one-line explanation of what the item demonstrates and which API it uses (e.g. 'Mesh.chamfered(distance:edges:) on one box edge'). Consider adding a help string to MeshGalleryItem so each section supplies it.\n- Section headers: what the section covers.\n- Render mode picker: what each debug mode visualizes (Normals, Tex Coords, Checkerboard, UV Grid, Front Facing, Valence Heatmap, Boundary Edges, ...) and when to use it (e.g. UV Grid for the Atlas Baking items).\n- Toolbar: Export PLY (ASCII vs binary), Inspector toggle, Metal renderer and Animate toggles, import by drag and drop.

---

## 121: ExtrusionMode.thinWalls: robust polygon offset for sharp corners and thin features

+++
status: open
priority: low
kind: enhancement
labels: area:extrude, effort:l
created: 2026-10-12T01:11:02Z
updated: 2026-10-12T01:11:04Z
+++

thinWalls (#71) offsets each outline with per-vertex miter joins (PathExtrusion.offsetLeft). It is topologically valid but geometrically wrong in three cases:
1. Sharp convex tips: the miter point shoots far past the corner (capped at ~10x thickness via max(1 + dot, 0.1)) and can cross the opposite side.
2. Sharp concave notches: offset edges cross, so the inner outline folds into a small reversed loop and wall faces self-intersect.
3. Thickness larger than half the local feature width (thin text strokes): inner offsets from opposite sides cross; the correct result splits or removes parts of the inner outline.

Fix: replace the per-vertex miter with a real polygon offset that clips the result against itself (Clipper2-style offset + union, or a straight skeleton). Use miter limit / bevel joins at sharp convex corners.

Tests: star outline (sharp tips) and an L/V notch produce non-self-intersecting inner outlines (check offset edges pairwise for crossings); a thin stroke with large thickness splits or drops the inner loop instead of folding; rectangles and rounded shapes are unchanged.

---

## 122: Robust Boolean: triangle-mesh core and Mesh conversion

+++
status: open
priority: high
kind: task
labels: area:csg, effort:m
created: 2026-10-12T01:22:18Z
+++

Part of #65 (port Manifold's robust Boolean to Swift; reference: github.com/elalish/manifold src/, docs/RobustBoolean.pdf). Manifold is Apache-2.0: ported code needs attribution and a NOTICE entry.\n\nPort the data the Boolean works on (Manifold impl.h/impl.cpp subset): triangle halfedges with paired twins, per-face normals, per-vertex pseudo-normals (used by symbolic perturbation), bounding box, and precision epsilon tracking. Convert from Mesh (triangulating n-gons, requiring a manifold input; report non-manifold input as an error) and back to Mesh.\n\nTests: round-trips of primitives are lossless; non-manifold input is rejected; epsilon grows with transforms as in Manifold.

---

## 123: Robust Boolean: BVH broad phase (collider)

+++
status: open
priority: high
kind: task
labels: area:csg, effort:m
created: 2026-10-12T01:22:18Z
+++

Part of #65 (port Manifold's robust Boolean to Swift; reference: github.com/elalish/manifold src/, docs/RobustBoolean.pdf). Manifold is Apache-2.0: ported code needs attribution and a NOTICE entry.\n\nPort Manifold's collider (collider.h; see docs/ParallelBVH.pdf): a BVH over triangle bounds that answers 'which faces of Q overlap this edge/vertex of P', including the XY-projected queries the kernels need. Serial is fine first.\n\nTests: results match brute force on random meshes; benchmark in SwiftMeshBenchmarks.\n\nDepends on: #122.

---

## 124: Robust Boolean: kernels and edge-face intersections with symbolic perturbation

+++
status: open
priority: high
kind: task
labels: area:csg, effort:l
created: 2026-10-12T01:22:18Z
+++

Part of #65 (port Manifold's robust Boolean to Swift; reference: github.com/elalish/manifold src/, docs/RobustBoolean.pdf). Manifold is Apache-2.0: ported code needs attribution and a NOTICE entry.\n\nPort boolean3.cpp's kernel ladder: Shadow01 (vertex vs edge), Kernel11 (edge vs edge), Kernel02 (vertex vs face), Kernel12 (edge vs face), and Intersect12 in both directions (p1q2 and p2q1) producing intersection points and crossing directions (x12). Symbolic perturbation: expand P for union, contract for difference/intersection, as in Boolean3's constructor.\n\nTests: coplanar, coincident-edge, and touching cases give consistent answers (e.g. a mesh minus itself is empty, touching cubes union into one solid); intersection counts match a brute-force reference on generic inputs.\n\nDepends on: #122, #123.

---

## 125: Robust Boolean: winding numbers by flood fill

+++
status: open
priority: high
kind: task
labels: area:csg, effort:s
created: 2026-10-12T01:22:19Z
+++

Part of #65 (port Manifold's robust Boolean to Swift; reference: github.com/elalish/manifold src/, docs/RobustBoolean.pdf). Manifold is Apache-2.0: ported code needs attribution and a NOTICE entry.\n\nPort Winding03: winding number of every vertex of P relative to Q (and vice versa) via Kernel02 on one vertex per connected component plus flood fill across edges not crossed by Q. Also expose a robust point-in-solid query (Manifold's PointWinding).\n\nTests: winding of points inside/outside primitives, nested shells, and points on the surface follow the perturbation rule.\n\nDepends on: #124.

---

## 126: Robust Boolean: result assembly

+++
status: open
priority: high
kind: task
labels: area:csg, effort:l
created: 2026-10-12T01:22:19Z
+++

Part of #65 (port Manifold's robust Boolean to Swift; reference: github.com/elalish/manifold src/, docs/RobustBoolean.pdf). Manifold is Apache-2.0: ported code needs attribution and a NOTICE entry.\n\nPort boolean_result.cpp: convert winding numbers to inclusion values per operation, keep retained vertices, add intersection vertices, split intersected halfedges and pair new edge endpoints (PairUp), and assemble the polygonal faces of the result before triangulation.\n\nTests: union/intersection/difference of overlapping cubes and spheres produce closed, consistently wound polygon sets (validated before triangulation).\n\nDepends on: #125.

---

## 127: Robust Boolean: robust polygon triangulation

+++
status: open
priority: high
kind: task
labels: area:csg, effort:l
created: 2026-10-12T01:22:19Z
+++

Part of #65 (port Manifold's robust Boolean to Swift; reference: github.com/elalish/manifold src/, docs/RobustBoolean.pdf). Manifold is Apache-2.0: ported code needs attribution and a NOTICE entry.\n\nPort Manifold's polygon triangulation (polygon.cpp; see docs/Triangulation.pdf) that handles epsilon-valid polygons with holes and degenerate geometry without failing. SwiftEarcut is not robust enough for Boolean output.\n\nTests: Manifold's polygon test corpus where feasible; degenerate slivers, collinear runs, and touching holes triangulate without overlaps or missing area.\n\nDepends on: #122.

---

## 128: Robust Boolean: degenerate removal and topology cleanup

+++
status: open
priority: high
kind: task
labels: area:csg, effort:l
created: 2026-10-12T01:22:19Z
+++

Part of #65 (port Manifold's robust Boolean to Swift; reference: github.com/elalish/manifold src/, docs/RobustBoolean.pdf). Manifold is Apache-2.0: ported code needs attribution and a NOTICE entry.\n\nPort edge_op.cpp: collapse short edges, swap degenerate triangles, split pinched verts, and other cleanup Manifold runs after a Boolean, preserving manifoldness.\n\nTests: Boolean results contain no zero-area triangles or edges shorter than epsilon; outputs stay manifold.\n\nDepends on: #126, #127.

---

## 129: Robust Boolean: carry vertex attributes

+++
status: open
priority: medium
kind: task
labels: area:csg, effort:m
created: 2026-10-12T01:22:19Z
+++

Part of #65 (port Manifold's robust Boolean to Swift; reference: github.com/elalish/manifold src/, docs/RobustBoolean.pdf). Manifold is Apache-2.0: ported code needs attribution and a NOTICE entry.\n\nPort the property mapping (properties.cpp / triRef): interpolate per-corner attributes (normals, UVs, colors, tangents) onto new vertices and keep them on retained faces, so CSG stops dropping attributes.\n\nTests: UVs on retained faces are unchanged; new vertices on a cut get barycentric-interpolated values.\n\nDepends on: #126.

---

## 130: Robust Boolean: switch Mesh CSG to the new algorithm

+++
status: open
priority: high
kind: task
labels: area:csg, effort:m
created: 2026-10-12T01:22:19Z
+++

Part of #65 (port Manifold's robust Boolean to Swift; reference: github.com/elalish/manifold src/, docs/RobustBoolean.pdf). Manifold is Apache-2.0: ported code needs attribution and a NOTICE entry.\n\nRoute Mesh.union/intersection/difference and csg(_:_:options:) through the new Boolean, keep CSGOptions where meaningful, and remove the BSP implementation. Acceptance: all existing CSG tests pass, every result of a CSG fuzz test (random rotated primitives) is manifold and passes validate(), and benchmarks are recorded before/after. Close #65 when done.\n\nDepends on: #128, #129.

---
