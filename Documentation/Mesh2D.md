# Mesh2D

`Mesh2D<ID>` is a 2D mesh: `HalfEdgeTopology` wiring plus per-vertex `CGPoint` positions
and per-half-edge labels of user-chosen type `ID`.

It's built for planar-subdivision workflows: arrange line segments in the plane,
classify the faces they enclose, query winding and adjacency, and selectively
delete edges (merging faces where appropriate).

## Constructing from line segments

Given a set of segments that are deduplicated and split at every crossing
(T-junction free), `init(segments:)` assembles the planar subdivision. Each
segment becomes a twin pair; next/prev are wired from CCW angular order at each
vertex so every closed cycle becomes a face.

```swift
import CoreGraphics
import Geometry
import SwiftMesh

let segments: [Identified<String, LineSegment>] = [
    Identified(id: "NE", value: LineSegment([0, 1], [1, 0])),
    Identified(id: "ES", value: LineSegment([1, 0], [0, -1])),
    Identified(id: "SW", value: LineSegment([0, -1], [-1, 0])),
    Identified(id: "WN", value: LineSegment([-1, 0], [0, 1])),
    Identified(id: "NS", value: LineSegment([0, 1], [0, -1]))  // diagonal
]

let mesh = Mesh2D(segments: segments)
// 4 vertices, 10 half-edges, 3 faces
// (2 interior triangles with CW winding, 1 exterior face with CCW winding)
```

Labels are preserved on both twin half-edges: `mesh.label(heID)` returns the
segment `ID` that produced it.

## Constructing from indexed points + face definitions

When you already have a valid planar arrangement (no intersections to resolve),
`init(points:faces:)` is faster and preserves vertex index order. Labels are
assigned as sequential undirected-edge indices.

```swift
let points: [CGPoint] = [[0, 0], [4, 0], [4, 4], [0, 4],
                         [1, 1], [1, 3], [3, 3], [3, 1]]

let faces = [
    HalfEdgeTopology.FaceDefinition(outer: [0, 1, 2, 3], holes: [[4, 5, 6, 7]])
]

let mesh = Mesh2D(points: points, faces: faces)
// Mesh2D<Int> with one face that has a square hole
```

## Querying faces

Signed areas drive most face classification:

```swift
// Is this face a "hole" (CW winding)?
mesh.isHole(fID)

// Exact signed area (positive = CCW, negative = CW)
mesh.signedArea(fID)

// Outer boundary as points
mesh.polygon(for: fID)

// Hole boundaries as arrays of points
mesh.holePolygons(for: fID)

// Convexity check
mesh.isConvex(fID)

// Faces sharing an edge with this one (via twins)
mesh.topology.neighborFaces(of: fID)
```

## Traversing topology

Since `Mesh2D` exposes `topology: HalfEdgeTopology`, all topology queries are
available:

```swift
mesh.topology.vertexLoop(for: fID)    // [VertexID] around a face
mesh.topology.halfEdgeLoop(for: fID)  // [HalfEdgeID] around a face
mesh.topology.boundaryLoops()         // [[VertexID]] of open boundaries

// Raw arrays for whole-mesh iteration
for face in mesh.topology.faces { ... }
for he in mesh.topology.halfEdges { ... }
```

For 2D-specific walks, `Mesh2D.boundaryLoops()` returns `[[CGPoint]]` directly.

## Enumerating undirected edges

`undirectedEdges()` emits one tuple per undirected edge (twin pairs collapsed):

```swift
for (a, b, label) in mesh.undirectedEdges() {
    let pa = mesh.point(a)
    let pb = mesh.point(b)
    // draw segment from pa to pb tagged with `label`
}
```

## Deleting edges

`deleteEdge(label:)` removes an undirected edge by its label. If the edge was
interior (shared by two faces), the two faces merge into one and the signed area
is recomputed. If the edge was on the boundary, it's simply unlinked from its
face.

```swift
var mesh = Mesh2D(segments: diamondWithDiagonal)
// Before: 2 interior triangles sharing "NS"
mesh.deleteEdge(label: "NS")
// After: 1 interior quadrilateral
```

Indices remain stable (the half-edges stay in the array, disconnected), so
downstream code holding `HalfEdgeID` values won't crash on lookup — but those IDs
will point to half-edges with `face == nil`.

## Validating

`HalfEdgeTopology.validate()` returns an array of `ValidationIssue`s describing
wiring inconsistencies (broken twin pairs, non-closed face loops, etc.):

```swift
let issues = mesh.topology.validate()
precondition(issues.isEmpty, "Bad mesh: \(issues)")
```

## Type parameter `ID`

`Mesh2D<ID>` is generic in its label type. Useful forms:

| `ID` | Typical use |
|---|---|
| `String` | Human-readable segment names for tests/debug |
| `Int` | Segment indices (default for `init(points:faces:)`) |
| `SplitID<UserID>` | Output of `Geometry.split(segments:)` — preserves traceability after intersection splitting |
| Custom struct | Attach arbitrary metadata (source-curve id, stroke style, etc.) |

`ID` must be `Hashable & Sendable`.

## Caveats

- `init(segments:)` expects clean input — deduplicated, with T-junctions already
  split. Feed arbitrary segments through `Geometry.split(segments:)` first.
- Vertex merging is done by exact `CGPoint` equality. If your input isn't
  snapped to a grid, snap it before constructing (see
  [`SelfIntersection.swift`](https://github.com/schwa/Vector) for an example).
- Positions are `CGPoint` (not `SIMD2<Float>`). For GPU use, convert at the
  boundary.
