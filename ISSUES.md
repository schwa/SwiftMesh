# ISSUES.md

---

## 1: Polygon triangulation (earcut)
status: closed
priority: high
kind: feature
created: 2026-04-14T20:00:14Z
updated: 2026-04-14T20:12:00Z
closed: 2026-04-14T20:12:00Z

Add polygon triangulation support. There's an existing C++ wrapper at ~/Shared/Projects/earcut-swift but the goal is a pure Swift port. Needed to convert PolygonMesh (polygon faces) to TrivialMesh (triangle indexed mesh).

- `2026-04-14T20:12:00Z`: SwiftEarcut added as a package dependency.

---

## 2: PolygonMesh to TrivialMesh conversion
status: new
priority: high
kind: feature
created: 2026-04-14T20:00:58Z

Add a method to convert PolygonMesh (arbitrary polygon faces) to TrivialMesh (triangle indexed mesh). Requires polygon triangulation (#1). Should handle convex and concave polygons.

---

## 3: Add helper APIs to easily render meshes in Metal
status: new
priority: medium
kind: feature
created: 2026-04-14T20:01:04Z

Provide convenience APIs for rendering SwiftMesh types with Metal. Convert TrivialMesh to Metal buffers, generate MTLVertexDescriptors, draw with MTLRenderCommandEncoder. Some of this exists already (Mesh, TrivialMesh+Mesh, TrivialMesh+Draw, VertexDescriptor) but needs cleanup and a coherent public API surface.

---

## 4: Consolidate mesh types — HalfEdgeMesh as the canonical representation
status: new
priority: high
kind: task
created: 2026-04-14T20:09:20Z

Too many mesh types (PolygonMesh, TrivialMesh, Mesh, HalfEdgeMesh, MeshWithEdges). HalfEdgeMesh should become the primary internal representation. Other types should either become thin convenience wrappers/views over HalfEdgeMesh or be removed. Need simple APIs that hide HE complexity for common use cases (create a box, sphere, etc.).

---

## 5: Simple high-level mesh API
status: new
priority: high
kind: feature
created: 2026-04-14T20:09:26Z

Provide a clean, simple API for common mesh operations without exposing HalfEdgeMesh internals. E.g. Mesh.box(), Mesh.sphere(), mesh.triangulated(), mesh.subdivided(), mesh.normals, etc. The current TrivialMesh+Shapes has the right idea for shape factories but the types underneath are a mess.

---

## 6: Boolean / CSG mesh operations
status: new
priority: medium
kind: feature
created: 2026-04-14T20:09:31Z

Implement boolean operations (union, intersection, difference) on meshes. HalfEdgeMesh is the right foundation for this — its edge traversal and face manipulation primitives (deleteEdge, neighborFaces, etc.) support the split-and-rewire operations CSG needs.

---

## 7: Subdivision surfaces
status: new
priority: low
kind: feature
created: 2026-04-14T20:09:58Z

Implement subdivision surface algorithms (Catmull-Clark for quads/polygons, Loop for triangles). Natural fit given HalfEdgeMesh provides the adjacency queries needed for subdivision stencils.

---

## 8: Generalize HalfEdgeMesh to 3D
status: new
priority: high
kind: feature
created: 2026-04-14T20:10:13Z

HalfEdgeMesh is currently 2D-only (CGPoint). Make the point type generic so it works with SIMD3<Float> and other point types. Abstract 2D-specific bits (signed area, angle sorting) behind a protocol or conditional conformance.

---

## 9: Mesh serialization format
status: new
priority: low
kind: feature
created: 2026-04-14T20:10:17Z

Adopt or design a serialization format for meshes. The .hemesh.json format spec from Scratch/half-edge-mesh is a starting point for HalfEdgeMesh. Also consider general mesh I/O (OBJ, PLY, etc.) for import/export.

---

## 10: Support loading meshes through ModelIO
status: new
priority: medium
kind: feature
created: 2026-04-14T20:12:06Z

Add import support via ModelIO (MDLAsset/MDLMesh). Should be able to load OBJ, PLY, USD, etc. and convert to SwiftMesh types.

---

## 11: Add unit tests
status: new
priority: high
kind: task
created: 2026-04-14T20:12:28Z

No tests currently exist. Need tests for: PolygonMesh (shapes, edges, normals, centers), TrivialMesh (shapes, transforms), HalfEdgeMesh (construction, validation, face queries, edge deletion, boundary loops), and conversions between types.

---

