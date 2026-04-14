# AGENTS.md

## Status

**Work in progress.** This project is in early consolidation — code has been gathered from multiple sources and hasn't been unified yet.

## Goal

SwiftMesh is a Swift package for mesh data structures and operations. The vision:

- **HalfEdgeMesh as the canonical representation** — rich topology queries, edge traversal, face manipulation
- **Simple high-level API** — `Mesh.box()`, `mesh.triangulated()`, `mesh.subdivided()` etc. without exposing HE internals
- **3D support** — HalfEdgeMesh is currently 2D (CGPoint), needs to be generic over point type
- **Boolean/CSG operations** — union, intersection, difference
- **Triangulation** via SwiftEarcut (already linked as a dependency)
- **Metal rendering helpers** — convert meshes to Metal buffers for drawing
- **ModelIO import** — load OBJ, PLY, USD etc.

## Current State

The codebase contains multiple mesh types gathered from different projects:

- `PolygonMesh` — simple polygon-face mesh with Platonic solid primitives (pure Swift)
- `TrivialMesh` — indexed triangle mesh with normals/UVs/tangents + shape factories (partially Metal-dependent)
- `HalfEdgeMesh` — half-edge topology with validation, queries, edge deletion (2D only, inlined from GeometryLite2D)
- `Mesh` / `MeshWithEdges` / `VertexDescriptor` — Metal GPU mesh types (from MetalSprocketsAddOns)
- `MikkTSpace` — C library for tangent generation

These need consolidation. See ISSUES.md for the full backlog.

## Key Architectural Issues

- Too many mesh types with no shared foundation
- Metal concerns mixed into the geometry layer — blocks testing and non-GPU use
- HalfEdgeMesh is 2D-only and isolated from the 3D types
- Shape definitions duplicated between PolygonMesh and TrivialMesh
- Heavy transitive dependencies (MetalSprockets, GeometryLite3D) for trivial helpers

## Dependencies

- `swift-collections` — OrderedDictionary for VertexDescriptor
- `GeometryLite3D` — Packed3 type (used in Metal mesh conversion)
- `MetalSprockets` — MetalSprocketsSupport (orFatalError, _MTLCreateSystemDefaultDevice)
- `SwiftEarcut` — polygon triangulation
- `MikkTSpace` — tangent generation (vendored C source)
