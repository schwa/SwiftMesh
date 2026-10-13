# ``SwiftMesh/Mesh2D``

## Overview

`Mesh2D<ID>` is a 2D mesh. It has ``HalfEdgeTopology`` connections, a `CGPoint` position for each
vertex, and a label of type `ID` for each half-edge. You select the `ID` type.

Use `Mesh2D` for planar subdivisions. You put line segments in a plane. Then you can classify the
faces that the segments enclose, query winding and adjacency, and delete edges. When you delete an
edge between two faces, the two faces merge.

## Make a mesh from line segments

`init(segments:)` builds the planar subdivision from a set of segments. The segments must have no
duplicates, and they must be split at each crossing (no T-junctions).

Each segment becomes a pair of twin half-edges. At each vertex, `init(segments:)` connects the
half-edges in counterclockwise angle order. Thus, each closed cycle becomes a face.

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

Both twin half-edges keep the label of their segment. `mesh.label(heID)` returns the segment `ID`.

## Make a mesh from points and face definitions

If the arrangement is already valid and has no intersections, use `init(points:faces:)`. It is
faster, and it keeps the order of the vertex indices. The labels are the indices of the undirected
edges, in sequence.

```swift
let points: [CGPoint] = [[0, 0], [4, 0], [4, 4], [0, 4],
                         [1, 1], [1, 3], [3, 3], [3, 1]]

let faces = [
    HalfEdgeTopology.FaceDefinition(outer: [0, 1, 2, 3], holes: [[4, 5, 6, 7]])
]

let mesh = Mesh2D(points: points, faces: faces)
// Mesh2D<Int> with one face that has a square hole
```

## Query faces

Most face queries use the signed area. A positive area is counterclockwise. A negative area is
clockwise.

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

## Traverse the topology

`Mesh2D` gives access to its `topology` property, so all ``HalfEdgeTopology`` queries are available.

```swift
mesh.topology.vertexLoop(for: fID)    // [VertexID] around a face
mesh.topology.halfEdgeLoop(for: fID)  // [HalfEdgeID] around a face
mesh.topology.boundaryLoops()         // [[VertexID]] of open boundaries

// Raw arrays for whole-mesh iteration
for face in mesh.topology.faces { ... }
for he in mesh.topology.halfEdges { ... }
```

`Mesh2D.boundaryLoops()` returns the boundary loops as `[[CGPoint]]`.

## List undirected edges

`undirectedEdges()` returns one tuple for each undirected edge. It does not return the two twins
separately.

```swift
for (a, b, label) in mesh.undirectedEdges() {
    let pa = mesh.point(a)
    let pb = mesh.point(b)
    // draw segment from pa to pb tagged with `label`
}
```

## Delete edges

`deleteEdge(label:)` removes the undirected edge that has the label.

- If two faces share the edge, the two faces merge into one face. The signed area of the merged
  face is calculated again.
- If the edge is on the boundary, `deleteEdge(label:)` disconnects it from its face.

```swift
var mesh = Mesh2D(segments: diamondWithDiagonal)
// Before: 2 interior triangles sharing "NS"
mesh.deleteEdge(label: "NS")
// After: 1 interior quadrilateral
```

The deleted half-edges stay in the array, but they have no connections. Thus, the indices do not
change, and a lookup with an old `HalfEdgeID` does not crash. The half-edge of that ID has
`face == nil`.

## Validate the topology

`HalfEdgeTopology.validate()` returns an array of `ValidationIssue` values. Each value describes an
error in the connections, for example a broken twin pair or a face loop that is not closed.

```swift
let issues = mesh.topology.validate()
precondition(issues.isEmpty, "Bad mesh: \(issues)")
```

## The `ID` type parameter

`Mesh2D<ID>` is generic over the label type. `ID` must be `Hashable & Sendable`.

| `ID` | Use |
|---|---|
| `String` | Segment names that people can read, for tests and debugging |
| `Int` | Segment indices. `init(points:faces:)` uses this type. |
| `SplitID<UserID>` | The output of `Geometry.split(segments:)`. It records the source segment of each part after the split. |
| A custom struct | Other data, for example the ID of the source curve or a stroke style |

## Limits

- `init(segments:)` needs clean input: no duplicates and no T-junctions. To clean other segments,
  use `Geometry.split(segments:)` first.
- `Mesh2D` merges vertices only when their `CGPoint` values are exactly equal. If your input is not
  on a grid, snap it to a grid first. For an example, see
  [`SelfIntersection.swift`](https://github.com/schwa/Vector).
- Positions are `CGPoint`, not `SIMD2<Float>`. For GPU use, convert them at the boundary.
