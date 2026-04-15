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
status: closed
priority: medium
kind: feature
created: 2026-04-15T00:51:16Z
updated: 2026-04-15T05:04:43Z
closed: 2026-04-15T05:04:43Z

Bidirectional ModelIO conversion. MDLMesh → Mesh (import positions, normals, UVs, submeshes, reconstruct topology) and Mesh → MDLMesh (export for SceneKit/RealityKit/USD). Should live in SwiftMeshIO.

- `2026-04-15T05:04:43Z`: Implemented bidirectional ModelIO conversion: MDLMesh → MTKMesh → MetalMesh → Mesh, and Mesh → MDLMesh

---

## 8: MetalMesh → Mesh conversion
status: closed
priority: medium
kind: feature
created: 2026-04-15T00:51:21Z
updated: 2026-04-15T04:54:54Z
closed: 2026-04-15T04:54:54Z

Convert MetalMesh back to Mesh. Will produce a triangle-only mesh with duplicated vertices (no topology recovery). Useful for importing GPU meshes back into the editing pipeline.

- `2026-04-15T04:54:54Z`: Implemented MetalMesh.toMesh() with position dedup, per-corner attribute preservation, and submesh support

---

## 9: Binary PLY support
status: new
priority: low
kind: feature
created: 2026-04-15T00:51:26Z

Add binary PLY read/write to SwiftMeshIO. Needed for large meshes — ASCII PLY is too slow/large.

---

## 10: Subdivision surfaces (Catmull-Clark, Loop)
status: closed
priority: medium
kind: feature
created: 2026-04-15T00:51:30Z
updated: 2026-04-15T05:22:59Z
closed: 2026-04-15T05:22:59Z

Subdivision surface algorithms. Catmull-Clark for quad meshes, Loop for triangle meshes. Operate on Mesh, return a new refined Mesh.

- `2026-04-15T05:22:59Z`: Implemented

---

## 11: Boolean / CSG operations
status: closed
priority: medium
kind: feature
created: 2026-04-15T00:51:34Z
updated: 2026-04-15T05:14:55Z
closed: 2026-04-15T05:14:55Z

Union, intersection, difference on Mesh. Requires robust intersection detection and mesh splitting.

- `2026-04-15T05:14:55Z`: Implemented

---

## 12: Mesh editing operations (split, collapse, extrude)
status: closed
priority: medium
kind: feature
created: 2026-04-15T00:51:42Z
updated: 2026-04-15T05:29:20Z
closed: 2026-04-15T05:29:20Z

Edge split, edge collapse, face extrude, vertex welding/deduplication. Core editing primitives for a mesh editor.

- `2026-04-15T05:29:20Z`: Superseded by individual issues #40-#44

---

## 13: Additional UV projection methods
status: closed
priority: low
kind: feature
created: 2026-04-15T00:51:47Z
updated: 2026-04-15T05:20:20Z
closed: 2026-04-15T05:20:20Z

Planar, cylindrical, and box UV projection. Currently only spherical projection is supported.

- `2026-04-15T05:20:20Z`: Implemented planar, cylindrical, and box UV projection

---

## 14: Mesh transform methods (scale, translate, rotate)
status: closed
priority: high
kind: feature
created: 2026-04-15T00:51:52Z
updated: 2026-04-15T06:52:08Z
closed: 2026-04-15T06:52:08Z

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
status: closed
priority: low
kind: task
created: 2026-04-15T00:52:07Z
updated: 2026-04-15T04:12:19Z
closed: 2026-04-15T04:12:19Z

Port capsule, hemisphere, icoSphere, cubeSphere, circle from old TrivialMesh+Shapes to Mesh primitives.

- `2026-04-15T04:12:19Z`: Superseded by individual issues #35-#39

---

## 17: Mesh simplification / decimation
status: closed
priority: low
kind: feature
created: 2026-04-15T00:52:14Z
updated: 2026-04-15T07:05:32Z
closed: 2026-04-15T07:05:32Z

Reduce mesh polygon count while preserving shape. Quadric error metrics or similar.

---

## 18: Support separate-buffer (SoA) vertex layout in MetalMesh
status: closed
priority: medium
kind: feature
created: 2026-04-15T01:09:58Z
updated: 2026-04-15T05:01:06Z
closed: 2026-04-15T05:01:06Z

Currently MetalMesh always interleaves attributes into one buffer. Add option for separate MTLBuffers per attribute (positions, normals, UVs, etc.) — avoids per-vertex byte packing and enables near-zero-cost conversion from Mesh's SoA arrays.

- `2026-04-15T05:01:06Z`: Implemented BufferLayout enum (interleaved vs separateBuffers)

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
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:27Z
updated: 2026-04-15T03:46:58Z
closed: 2026-04-15T03:46:58Z


---

## 24: Generate UVs for cube primitive
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:32Z
updated: 2026-04-15T03:11:58Z
closed: 2026-04-15T03:11:58Z


---

## 25: Generate UVs for octahedron primitive
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:33Z
updated: 2026-04-15T03:46:58Z
closed: 2026-04-15T03:46:58Z


---

## 26: Generate UVs for icosahedron primitive
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:33Z
updated: 2026-04-15T03:46:58Z
closed: 2026-04-15T03:46:58Z


---

## 27: Generate UVs for dodecahedron primitive
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:33Z
updated: 2026-04-15T03:46:58Z
closed: 2026-04-15T03:46:58Z


---

## 28: Generate UVs for triangle() primitive
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:33Z
updated: 2026-04-15T03:39:51Z
closed: 2026-04-15T03:39:51Z


---

## 29: Generate UVs for quad() primitive
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:33Z
updated: 2026-04-15T03:39:51Z
closed: 2026-04-15T03:39:51Z


---

## 30: Generate UVs for box() primitive
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:33Z
updated: 2026-04-15T03:39:51Z
closed: 2026-04-15T03:39:51Z


---

## 31: Generate UVs for torus() primitive
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:33Z
updated: 2026-04-15T03:46:58Z
closed: 2026-04-15T03:46:58Z


---

## 32: Generate UVs for cylinder() primitive
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:34Z
updated: 2026-04-15T03:39:51Z
closed: 2026-04-15T03:39:51Z


---

## 33: Generate UVs for cone() primitive
status: closed
priority: low
kind: feature
created: 2026-04-15T02:57:34Z
updated: 2026-04-15T03:39:51Z
closed: 2026-04-15T03:39:51Z


---

## 34: Add teapot primitive
status: closed
priority: low
kind: feature
created: 2026-04-15T04:11:12Z
updated: 2026-04-15T05:12:44Z
closed: 2026-04-15T05:12:44Z

- `2026-04-15T05:12:44Z`: Implemented — loads bundled OBJ via ModelIO pipeline

---

## 35: Add capsule primitive
status: closed
priority: low
kind: feature
created: 2026-04-15T04:12:03Z
updated: 2026-04-15T04:16:36Z
closed: 2026-04-15T04:16:36Z

- `2026-04-15T04:16:36Z`: Implemented hemisphere() and capsule() primitives with extents, UV support, and full test coverage

---

## 36: Add hemisphere primitive
status: closed
priority: low
kind: feature
created: 2026-04-15T04:12:03Z
updated: 2026-04-15T04:16:36Z
closed: 2026-04-15T04:16:36Z

- `2026-04-15T04:16:36Z`: Implemented hemisphere() and capsule() primitives with extents, UV support, and full test coverage

---

## 37: Add icoSphere primitive
status: closed
priority: low
kind: feature
created: 2026-04-15T04:12:03Z
updated: 2026-04-15T04:22:43Z
closed: 2026-04-15T04:22:43Z

- `2026-04-15T04:22:43Z`: Implemented

---

## 38: Add cubeSphere primitive
status: closed
priority: low
kind: feature
created: 2026-04-15T04:12:03Z
updated: 2026-04-15T04:22:43Z
closed: 2026-04-15T04:22:43Z

- `2026-04-15T04:22:43Z`: Implemented

---

## 39: Add circle primitive
status: closed
priority: low
kind: feature
created: 2026-04-15T04:12:03Z
updated: 2026-04-15T04:22:43Z
closed: 2026-04-15T04:22:43Z

- `2026-04-15T04:22:43Z`: Implemented

---

## 40: Edge collapse operation on HalfEdgeTopology
status: closed
priority: medium
kind: feature
created: 2026-04-15T05:24:28Z
updated: 2026-04-15T06:58:51Z
closed: 2026-04-15T06:58:51Z

Merge two vertices connected by an edge into one, removing adjacent faces and rewiring topology. Prerequisite for mesh decimation (#17).

---

## 41: Edge flip operation on HalfEdgeTopology
status: new
priority: low
kind: feature
created: 2026-04-15T05:24:28Z

Swap the diagonal of two adjacent triangles. Useful for mesh quality improvement and Delaunay-like refinement.

---

## 42: Edge split operation on HalfEdgeTopology
status: new
priority: medium
kind: feature
created: 2026-04-15T05:25:32Z

Insert a vertex at an edge midpoint, splitting the two adjacent faces into four. Core editing primitive.

---

## 43: Face extrude operation
status: new
priority: medium
kind: feature
created: 2026-04-15T05:25:33Z

Push a face outward along its normal, creating side wall quads connecting the original boundary to the extruded face.

---

## 44: Vertex weld / deduplication
status: new
priority: low
kind: feature
created: 2026-04-15T05:25:33Z

Merge vertices that are within a tolerance distance of each other, rewiring topology. Useful for cleaning up imported meshes.

---

## 45: Use Interaction3D for gestures in demo
status: closed
priority: low
kind: enhancement
created: 2026-04-15T05:30:18Z
updated: 2026-04-15T05:35:02Z
closed: 2026-04-15T05:35:02Z

Replace manual DragGesture in demo with Interaction3D package (github.com/schwa/Interaction3D) for orbit/pan/zoom camera controls.

- `2026-04-15T05:35:02Z`: Implemented — replaced manual DragGesture with Interaction3D's interactiveCamera modifier

---

## 46: Teapot is squished — fitToExtents scales non-uniformly
status: closed
priority: medium
kind: bug
created: 2026-04-15T05:51:38Z
updated: 2026-04-15T05:53:12Z
closed: 2026-04-15T05:53:12Z

fitToExtents scales each axis independently to match the target extents, which distorts non-cubic meshes like the teapot. Should use uniform scaling (fit within extents while preserving aspect ratio) for bundled meshes, or offer both modes.

- `2026-04-15T05:53:12Z`: Fixed — teapot now uses fitToDiameter for uniform scaling

---

## 47: Coplanar face merging after CSG operations
status: closed
priority: medium
kind: enhancement
created: 2026-04-15T05:55:25Z
updated: 2026-04-15T06:43:20Z
closed: 2026-04-15T06:43:20Z

CSG boolean operations produce excessive triangulation on flat surfaces — e.g. a flat square face becomes a mosaic of many triangles. Add a post-processing pass that merges coplanar adjacent faces back into larger polygons.

- `2026-04-15T06:43:20Z`: Implemented mergingCoplanarFaces() — deletes shared edges between adjacent coplanar faces

---

## 48: Mesh from extruded text
status: new
priority: low
kind: feature
created: 2026-04-15T05:55:51Z

Generate meshes from text strings by converting font glyphs to paths, triangulating the 2D outline, and extruding to 3D. Should support font, size, and extrusion depth parameters.

---

## 49: Mesh from extruded SwiftUI.Path
status: new
priority: medium
kind: feature
created: 2026-04-15T05:56:16Z

Generate meshes by triangulating a SwiftUI Path and extruding to 3D. Should handle holes, produce front/back caps and side walls. Could be the foundation for text extrusion (#48) as well.

---

## 50: Edge fillet (rounding)
status: new
priority: low
kind: feature
created: 2026-04-15T05:57:13Z

Round selected edges by replacing them with a smooth arc of faces. Requires edge split and vertex insertion along the edge neighborhood.

---

## 51: Edge chamfer (beveling)
status: new
priority: low
kind: feature
created: 2026-04-15T05:57:13Z

Bevel selected edges by cutting them at an angle, replacing each edge with a flat face. Simpler than fillet — no curvature, just a single angled cut.

---

## 52: Consolidate demo into single gallery with section groupings
status: closed
priority: medium
kind: enhancement
created: 2026-04-15T05:57:53Z
updated: 2026-04-15T05:59:56Z
closed: 2026-04-15T05:59:56Z

Replace the four separate tabs (Platonic Solids, Surfaces, CSG, Subdivision) with a single scrollable gallery using section headers to group the meshes. Reduces code duplication across gallery views.

- `2026-04-15T05:59:56Z`: Consolidated into single scrollable gallery with section headers

---

## 53: Inspector tab in demo showing mesh details
status: closed
priority: medium
kind: feature
created: 2026-04-15T06:11:30Z
updated: 2026-04-15T06:12:44Z
closed: 2026-04-15T06:12:44Z

New tab with a single mesh (cylinder) and a .inspector() sidebar showing vertex count, face count, edge count, and which attributes are present.

- `2026-04-15T06:12:44Z`: Implemented

---

## 54: Add Select Loop to demo inspector
status: new
priority: low
kind: feature
created: 2026-04-15T06:39:36Z


---

## 55: Stray edges after coplanar face merging
status: closed
priority: high
kind: bug
created: 2026-04-15T06:45:39Z
updated: 2026-04-15T06:47:02Z
closed: 2026-04-15T06:47:02Z

mergingCoplanarFaces() produces degenerate polygons with self-intersecting boundaries. After deleteEdge merges two faces, collinear vertices from the former shared edge remain in the boundary loop, creating crossed/stray edges visible in wireframe. Need to remove collinear vertices from merged face boundaries.

- `2026-04-15T06:47:02Z`: Fixed — remove collinear vertices from merged face boundaries

---

## 56: CSG over-splits faces that don't intersect the other solid
status: new
priority: medium
kind: bug
created: 2026-04-15T06:58:03Z

BSP-based CSG splits cube faces even when the sphere is entirely interior and doesn't intersect those faces. This creates unnecessary triangulation on flat surfaces that coplanar merging can only partially clean up, since the BSP split introduces true boundary edges where none should exist.

---

## 57: Generic Mesh over Float/Double scalar type
status: new
priority: medium
kind: feature
created: 2026-04-15T07:09:54Z

Make Mesh generic over scalar type (Float vs Double). Positions, normals, UVs etc would use the generic scalar. Enables double-precision meshes for CSG and other operations that accumulate floating point error.

---

## 58: CSG operations in Double precision
status: new
priority: medium
kind: enhancement
created: 2026-04-15T07:09:54Z

Run CSG BSP internals in Double precision to reduce vertex drift from plane splitting. Convert back to Float (or keep as Double if Mesh supports it) at the end. Depends on generic Mesh or a separate DoubleMesh type.

---

## 59: Float/Double mesh conversion
status: new
priority: medium
kind: feature
created: 2026-04-15T07:09:54Z

Add conversion between Float and Double precision meshes. MetalMesh only works with Float, so need a way to downconvert Double meshes for GPU use.

---

## 60: Decimation damages CSG difference mesh (sphere − cube)
status: new
priority: high
kind: bug
created: 2026-04-15T07:40:25Z

Decimating the 'Difference: Sphere − Cube' gallery mesh produces a gaping hole. The decimation algorithm likely collapses edges on the CSG boundary where the carved-out region meets the sphere surface, breaking the manifold.

---

## 61: Add isManifold method
status: new
priority: medium
kind: feature
created: 2026-04-15T07:40:38Z

Add a method to check whether a mesh is a closed 2-manifold (every edge has exactly one twin, no boundary edges, consistent orientation).

---

## 62: cubeSphere has unwelded seam vertices, not manifold
status: closed
priority: medium
kind: bug
created: 2026-04-15T07:46:38Z
updated: 2026-04-15T07:53:40Z
closed: 2026-04-15T07:53:40Z

cubeSphere generates 6 independent grids projected onto a sphere but doesn't weld shared vertices at cube face edges/corners. This leaves 192 boundary half-edges with no twins. The mesh should be a closed manifold.

- `2026-04-15T07:53:40Z`: Fixed by welding seam vertices during cubeSphere construction.

---

## 63: teapot mesh is not manifold
status: closed
priority: low
kind: bug
created: 2026-04-15T07:47:21Z
updated: 2026-04-15T07:48:30Z
closed: 2026-04-15T07:48:30Z

Mesh.teapot() has boundary edges from the OBJ import — likely unwelded seam vertices, similar to cubeSphere (#62).

- `2026-04-15T07:48:30Z`: Not a bug — the Utah teapot is intentionally composed of separate patches with open boundaries.

---

## 64: Add Mesh.welded(tolerance:) to merge near-duplicate vertices and rebuild topology
status: closed
priority: medium
kind: feature
created: 2026-04-15T07:48:19Z
updated: 2026-04-15T07:53:40Z
closed: 2026-04-15T07:53:40Z

TriangleSoup.welded(tolerance:) merges positions but doesn't rebuild half-edge topology. Need a Mesh-level weld that merges near-duplicate positions, remaps face indices, and rebuilds HalfEdgeTopology so twin edges form at seams. This would fix cubeSphere (#62).

- `2026-04-15T07:53:40Z`: Implemented Mesh.welded(tolerance:) and used it to fix cubeSphere.

---

## 65: CSG results should be manifold
status: new
priority: medium
kind: bug
created: 2026-04-15T07:54:19Z

CSG union/intersection/difference of two manifold closed meshes should produce a manifold result. Currently the BSP-based algorithm produces meshes with boundary edges and standalone faces due to the TriangleSoup round-trip losing topology. Affected: all CSG operations between closed solids (e.g. cube∪cube, sphere∩cube, sphere−cube).

---

## 66: Add split-by-plane operation
status: new
priority: medium
kind: feature
created: 2026-04-15T07:54:33Z

Split a mesh along an arbitrary plane, producing two separate meshes (one for each side). Faces straddling the plane should be clipped and capped.

- `2026-04-15T14:21:46Z`: Add option to heal (cap) the cut faces after splitting.

---

## 67: Add mesh diagnostic API (is/has-style queries)
status: new
priority: medium
kind: feature
created: 2026-04-15T14:12:08Z

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
- `hasNonMatchingFaceEdgeCounts` — halfedge loop count vs stored face degree
- `hasDuplicateFaces` — two faces sharing all the same vertices
- `hasDuplicateEdges` — more than one edge connecting the same two vertices

---

## 68: Change validate() to return [ValidationIssue] instead of String?
status: closed
priority: medium
kind: feature
created: 2026-04-15T14:12:38Z
updated: 2026-04-15T14:17:18Z
closed: 2026-04-15T14:17:18Z

Currently `validate()` returns `String?` with the first error found. Change to return `[ValidationIssue]` so all issues are reported at once. ValidationIssue should be a structured type with severity, location (edge/face/vertex ID), and description.

- `2026-04-15T14:17:18Z`: Implemented. validate() now returns [ValidationIssue] with severity, location, and message for every issue found.

---

## 69: Refactor demo app to NavigationSplitView
status: closed
priority: medium
kind: feature
created: 2026-04-15T14:13:27Z
updated: 2026-04-15T14:20:11Z
closed: 2026-04-15T14:20:11Z

Replace the current TabView with Gallery/Inspector tabs and the full-screen overlay with a single NavigationSplitView layout. Sidebar shows the mesh list, detail shows the interactive mesh view with the toolbar buttons (weld, triangulate, subdivide, decimate, standalone highlight) and the inspector info (manifold status, face count, etc.).

- `2026-04-15T14:20:11Z`: Refactored to NavigationSplitView with sidebar mesh list, detail interactive view, and inspector panel with topology info and operations.

---

## 70: Add Metal debug shaders for topology visualization
status: new
priority: low
kind: feature
created: 2026-04-15T14:14:11Z

Integrate debug shaders from MetalSprocketsAddons to visualize mesh topology in the demo app. Include: normal visualization (lines or color-mapped), wireframe overlay, face winding display, boundary edge highlighting, vertex valence heatmap.

---

## 71: Support extrusion modes: solid, walls only, thin walls
status: new
priority: medium
kind: feature
created: 2026-04-15T14:20:40Z


---

## 72: Heal holes
status: new
priority: medium
kind: feature
created: 2026-04-15T14:20:52Z


---

