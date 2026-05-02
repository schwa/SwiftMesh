# RFC: Exact CSG via EMBER Algorithm

**Status:** Proposal
**Date:** 2025-05-02

## Summary

Add an `ExactCSG` target to SwiftMesh implementing the EMBER algorithm for exact mesh Boolean operations. EMBER (Exact Mesh Booleans via Efficient & Robust Local Arrangements) computes union, intersection, and difference on polygon meshes with guaranteed exactness, robustness, and high performance.

**Paper:** Trettner, Nehring-Wirxel, Kobbelt. "EMBER: Exact Mesh Booleans via Efficient & Robust Local Arrangements." ACM Trans. Graph. 41, 4, Article 39 (July 2022). [DOI: 10.1145/3528223.3530181](https://doi.org/10.1145/3528223.3530181). Project page: [graphics.rwth-aachen.de/ember-exact-mesh-booleans](https://graphics.rwth-aachen.de/ember-exact-mesh-booleans)

## Motivation

The existing `CSG.swift` uses a classic BSP-merge algorithm with `Float` arithmetic. This approach:

- Suffers from numerical instability (coplanar faces, thin triangles, near-edge intersections)
- Produces incorrect topology and geometry on degenerate configurations
- Accumulates error in iterated CSG (difference of difference of union, etc.)
- Cannot guarantee watertight output

EMBER solves all of these by using fixed-width integer arithmetic and plane-based geometry. The paper demonstrates it is faster than even inexact methods while guaranteeing exact results.

## Why EMBER over other exact methods?

| Method | Exact? | Speed (geometric mean) | Notes |
|--------|--------|----------------------|-------|
| QuickCSG | No | 72 ms | Fails on coplanar configs |
| Cork | No | 139 ms | Frequent topology errors |
| Mesh Arrangements | Yes | 8570 ms | Arbitrary precision, slow |
| CGAL Nef | Yes | 3164 ms | Memory-heavy |
| **EMBER** | **Yes** | **1.6 ms** | Fixed-width integers |

EMBER's key insight is that all arithmetic stays within 256-bit integers — no arbitrary-precision needed. This maps well to a pure Swift implementation using fixed-width integer types.

## Algorithm Overview

The paper's approach, at a high level:

1. **Import:** Scale and round input coordinates to 26-bit integers.
2. **Represent:** Convert each polygon to plane-based form (supporting plane + edge planes, integer coefficients).
3. **Subdivide:** Recursively split the bounding box along axis-aligned planes (adaptive kd-tree). Clip polygons against splitting planes. Propagate a reference point with known winding number vector (WNV) into each subproblem.
4. **Intersect:** In leaf nodes, compute pairwise face-face intersections and build per-polygon BSPs to partition each face into non-self-intersecting convex sub-polygons.
5. **Classify:** For each sub-polygon, trace segments from the reference point to determine the WNV in front and behind. Apply the Boolean indicator function to decide keep/discard/invert.
6. **Export:** Convert output polygons back to floating-point vertex positions.

### Core Mathematical Operations

Everything is built on two primitives:

- **`intersect(p, q, r)`** — Intersection of three planes → 4D homogeneous integer point (3×3 determinants, Eq. 3 in paper)
- **`classify(x, s)`** — Which side of plane `s` does point `x` lie on? → `{-1, 0, 1}` (Eq. 4 in paper)

From these, polygon clipping, segment-polygon intersection, and BSP construction all follow.

## Implementation Plan

### Target Structure

New target `ExactCSG` in the SwiftMesh package, depending on `SwiftMesh` for `Mesh`/`TriangleSoup` types. No external dependencies.

```
Sources/
  ExactCSG/
    WideInteger/
      Int128.swift
      Int256.swift
      WideIntegerArithmetic.swift
    PlaneGeometry/
      ExactPlane.swift
      HomogeneousPoint.swift
      Intersect.swift
      Classify.swift
      ConvexPolygon.swift
      Segment.swift
    Subdivision/
      AABB.swift
      SubdivisionTask.swift
      PolygonClipping.swift
      ReferencePointPropagation.swift
      SplittingStrategy.swift
    BSP/
      LocalBSP.swift
      FaceIntersection.swift
      OverlapHandling.swift
    Classification/
      WindingNumberVector.swift
      SegmentTracing.swift
      BooleanIndicator.swift
    ExactCSG.swift              # Public API
    MeshConversion.swift        # Mesh ↔ plane-based conversion
```

### Phases

Each phase produces testable, compilable code. Build and run tests after each.

---

#### Phase 1: Wide Integer Arithmetic

**Goal:** `Int128` and `Int256` value types with the operations EMBER needs.

**What:**
- `Int128` as two `Int64` (or `UInt64` + sign handling). Swift has `Int128` in the standard library as of recent toolchains — evaluate whether it's stable enough to use directly. If not, implement from scratch.
- `Int256` as two `Int128`.
- Required operations: add, subtract, multiply (widening: `Int128 × Int128 → Int256`), negate, compare, sign.
- Specialized reduced-width types where the paper calls for them (axis-aligned planes have coefficients that are -1, 0, or 1).
- No division needed — EMBER deliberately avoids it.

**Tests:**
- Arithmetic correctness against known values
- Overflow boundary cases
- Widening multiply: `Int128.widenedMultiply(_:) -> Int256`
- Sign/comparison for all quadrants

**Key paper reference:** Section 3, Section 4.5.5 ("Various coefficients of axis-aligned planes and lines are −1, 0, or 1. Many intermediate results can be safely computed with reduced bit sizes.")

---

#### Phase 2: Plane-Based Geometry Kernel

**Goal:** Exact plane representation, `intersect`, and `classify`.

**What:**
- `ExactPlane` — four integer coefficients `(a, b, c, d)` representing `ax + by + cz + d = 0`. Bit widths depend on provenance (input planes vs. constructed planes).
- `HomogeneousPoint` — 4D integer coordinates `(x1, x2, x3, x4)`. A point in 3-space at `(x1/x4, x2/x4, x3/x4)`.
- `intersect(p, q, r) -> HomogeneousPoint` — three 3×3 determinants + one for `x4` (Eq. 3).
- `classify(x, s) -> Int` — `sign(⟨x, s⟩) * sign(x4)` (Eq. 4).
- Parallelism predicate: `isParallel(p, q) -> Bool` — cross product of normals == zero (Eq. 2).

**Tests:**
- `intersect` of three axis-aligned planes → known point
- `classify` a point against a plane → correct side
- Degenerate cases: parallel planes, point on plane
- Round-trip: construct point from three planes, classify against each → all zero

**Key paper reference:** Section 3

---

#### Phase 3: Convex Polygon & Segment Primitives

**Goal:** Plane-based convex polygon and segment types with intersection operations.

**What:**
- `ExactConvexPolygon` — supporting plane `s` + edge planes `e_1...e_n`. A point belongs to the polygon iff `classify(s, x) == 0` and `classify(e_i, x) <= 0` for all `i`.
- `ExactSegment` — four planes `(l0, l1, r0, r1)`: supporting line `(l0, l1)` + two bounding planes.
- `ExactRay` — three planes `(l0, l1, r)`.
- Segment-polygon intersection: `intersect(l0, l1, s)` then check against edge planes and bounding planes (Section 3.1, Fig. 2).
- Axis-aligned segment construction from integer coordinates (the common fast path).

**Tests:**
- Triangle-as-polygon, point-in-polygon via classify
- Segment-polygon intersection: hit, miss, edge hit, coplanar
- Axis-aligned segments through known polygons

**Key paper reference:** Section 3.1, 3.2, Fig. 2

---

#### Phase 4: Polygon Clipping

**Goal:** Clip a convex polygon against an axis-aligned splitting plane.

**What:**
- Classify each vertex against splitting plane → `{-1, 0, 1}`.
- If all non-positive → "left". All non-negative → "right". Mixed → split.
- For each edge crossing -1↔1, construct new vertex via `intersect(supporting_plane, edge_plane, splitting_plane)`.
- Produce two sub-polygons from the split (Section 4.2.1, Fig. 6).
- Propagate winding number transition vectors (WNTVs) — each polygon carries a `Δw` vector.

**Tests:**
- Clip a triangle fully on one side → unchanged
- Clip a triangle spanning the plane → two valid polygons covering original area
- Clip at a vertex → correct handling (no degenerate output)
- Clip coplanar polygon → assigned to "left"

**Key paper reference:** Section 4.2.1, Fig. 6

---

#### Phase 5: Mesh Import/Export

**Goal:** Convert `Mesh`/`TriangleSoup` to plane-based representation and back.

**What:**
- Scale and round input `Float` positions to 26-bit integer coordinates.
- For each triangle: compute supporting plane and three edge planes from integer vertex positions.
- Assign WNTV `Δw` per polygon (one-hot vector based on which input mesh it belongs to).
- Export: convert `HomogeneousPoint` back to `Float`/`Double` via division.

**Tests:**
- Round-trip: mesh → exact → back → positions within quantization tolerance
- Plane normals consistent with triangle winding
- Edge planes consistent with vertex ordering

**Key paper reference:** Section 3, 3.3

---

#### Phase 6: Subdivision Engine

**Goal:** Adaptive recursive kd-tree subdivision with reference point propagation.

**What:**
- Integer AABB type.
- Subdivision task: split AABB at axis-aligned plane, clip all polygons, distribute to sub-problems.
- Splitting strategy: center-of-gravity along largest-variance axis, with WNTV-aware candidate selection (Section 4.5.3).
- Reference point propagation: when `x_ref` is not in the new sub-AABB, project onto it and trace segments to compute the new WNV (Section 4.2.2).
- Leaf threshold: stop subdividing when polygon count ≤ 25.

**Tests:**
- Subdivision of a simple scene into expected sub-problems
- Reference point correctly propagated across splits
- Polygon counts decrease with subdivision depth

**Key paper reference:** Section 4.1, 4.2, 4.5.3, Fig. 4

---

#### Phase 7: Local BSP Construction

**Goal:** Per-polygon BSP for intersection resolution.

**What:**
- For each polygon `t` in a leaf, build a 2D BSP within `t`'s supporting plane.
- Compute pairwise face-face intersections: cases C1 (none), C2 (point), C3 (segment), C4 (overlap).
- For C3: add intersection segment `(v0, v1, s_t')` to the BSP. Each leaf containing part of the segment is split (Section 4.3, Fig. 7).
- For C4 (overlap): add all edges of `t'` to BSP, disable overlapping leaves based on polygon index ordering (Fig. 8).
- Result: each BSP leaf is a convex sub-polygon with no interior intersections.

**Tests:**
- Two non-intersecting triangles → BSPs unchanged
- Two crossing triangles → each BSP has correct number of leaves
- Coplanar overlapping triangles → overlap regions disabled for higher-index polygon
- Three-way intersection at a single polygon

**Key paper reference:** Section 4.3, Fig. 7, Fig. 8

---

#### Phase 8: Winding Number Classification

**Goal:** Classify each BSP leaf polygon by segment-tracing WNVs.

**What:**
- Winding number vector (WNV) type: `[Int]` of dimension = number of input meshes.
- Winding number transition vector (WNTV): the `Δw` associated with each input polygon.
- WNV propagation along a segment: for each polygon intersected by the segment, apply `Δw` or `-Δw` depending on which side the normal faces (Section 3.4, Eq. 6/7).
- Target point construction: compute interior point of leaf polygon via edge-plane offset method (Section 4.4).
- 3-segment path construction between two homogeneous points by iteratively swapping defining planes (Fig. 9, Section 4.4).
- Simple fast path: axis-aligned line from approximate centroid (succeeds in vast majority of cases).
- Classify `(w_F, w_B)` for each leaf polygon. Apply indicator function.

**Tests:**
- Single cube: all exterior faces classify (0→1), interior is empty
- Two overlapping cubes, union: correct faces emitted
- Two overlapping cubes, difference: correct faces emitted/inverted
- Segment trace across known polygon arrangement → correct WNV at endpoint
- 3-segment path construction between two homogeneous points → valid path

**Key paper reference:** Section 3.4, 4.4, Fig. 3, Fig. 9, Fig. 10

---

#### Phase 9: Boolean Indicator Functions & Output Assembly

**Goal:** Complete end-to-end Boolean operations.

**What:**
- Indicator functions for union, intersection, difference, symmetric difference (Section 3.4, Eq. 5).
- Variadic operations (N-way union, milling simulation subtraction).
- Output polygon emission: `(out, in)` → keep, `(in, out)` → invert, others → discard.
- Collect all emitted polygons, convert back to `Mesh`/`TriangleSoup`.
- Public API surface on `TriangleSoup` and `Mesh` mirroring existing CSG methods.

**Tests:**
- Union/intersection/difference of two cubes → watertight, correct volume
- Self-union of self-intersecting mesh → clean output
- Difference A−B then B−A → complementary results
- Comparison against existing inexact CSG for simple cases (same topology, positions within quantization tolerance)

**Key paper reference:** Section 3.4, Fig. 3(b)

---

#### Phase 10: Early-Out Optimizations

**Goal:** Performance parity with the paper's results.

**What:**
- NSI (no self-intersection) / NNC (no nested components) flags per WNTV class. Skip BSP construction for single-WNTV leaves with NSI. Single classification for NNC (Section 4.5.1, Fig. 11).
- WNV reachability analysis: given reference WNV and available WNTVs, can any reachable WNV be "in"? If not, discard entire subtree (Section 4.5.2, Fig. 12).
- Conservative AABB pre-tests before any segment intersection.

**Tests:**
- Profile before/after on non-trivial meshes
- Verify early-outs don't change results (run with and without, compare output)

**Key paper reference:** Section 4.5.1, 4.5.2

---

#### Phase 11: Parallelism

**Goal:** Multi-threaded subdivision via work-stealing.

**What:**
- Each subdivision step is a pure function of local data → embarrassingly parallel.
- Work-stealing queue of subproblems. One branch recurses, the other is enqueued.
- Swift concurrency: `TaskGroup` or a custom work-stealing queue with `DispatchQueue`/actors.
- Thread-local memory pools for polygon/BSP allocation.

**Tests:**
- Correctness: parallel output == single-threaded output
- Scaling: measure speedup on 2/4/8 cores

**Key paper reference:** Section 4.5.4, Fig. 18

---

## Public API

```swift
// On TriangleSoup
extension TriangleSoup {
    func exactUnion(_ other: TriangleSoup) -> TriangleSoup
    func exactIntersection(_ other: TriangleSoup) -> TriangleSoup
    func exactDifference(_ other: TriangleSoup) -> TriangleSoup
}

// On Mesh
extension Mesh {
    func exactUnion(_ other: Mesh) -> Mesh
    func exactIntersection(_ other: Mesh) -> Mesh
    func exactDifference(_ other: Mesh) -> Mesh
}

// Variadic
struct ExactCSG {
    static func evaluate(meshes: [(Mesh, Int)], operation: ExactCSGOperation) -> Mesh
}

enum ExactCSGOperation {
    case union
    case intersection
    case difference
    case custom((WindingNumberVector) -> Bool)
}
```

## Key Risks & Open Questions

1. **Wide integer performance in Swift.** The paper's C++ implementation uses template-specialized fixed-width integers with statically known bit widths at each call site. Swift generics may not optimize as aggressively. We may need `@inlinable` everywhere and potentially SIMD intrinsics for the hot paths (128-bit multiply).

2. **Swift's `Int128`.** Available in recent toolchains but not fully stable API. If we use it, we couple to a specific Swift version. If we roll our own, it's more work but more portable.

3. **No triangulation of output.** EMBER outputs convex polygons, not triangles. The existing `Mesh` type supports arbitrary polygons via `HalfEdgeTopology`, so this should be fine. Fan triangulation can be offered as an optional post-process.

4. **T-junctions in output.** EMBER's output contains T-junctions at subdivision cell boundaries. These are geometrically exact but can cause rendering artifacts (cracks) with floating-point rasterization. May need a T-junction removal post-process.

5. **Quantization.** Input coordinates are rounded to 26-bit integers (~15 nm accuracy for a 1 m³ scene). This is plenty for most use cases but should be documented clearly. The quantization step could re-introduce tiny self-intersections at import boundaries.

6. **Memory.** The paper's implementation reuses memory aggressively via the recursive structure. Swift's ARC and value semantics may make this harder. May need to use classes or unsafe buffers for performance-critical paths.

7. **Complexity.** This is a large implementation (~2000–4000 lines estimated). The phased approach mitigates risk — each phase is independently useful and testable.

## Non-Goals (for now)

- Replacing the existing inexact CSG implementation. Both will coexist.
- GPU acceleration. EMBER is CPU-only by design (exact integer arithmetic).
- Iterated CSG with persistent kd-tree (mentioned as future work in the paper).
- Attribute transfer (UVs, normals) beyond basic polygon provenance tracking.

## References

- [Trettner et al. 2022] EMBER paper — DOI: 10.1145/3528223.3530181
- [Nehring-Wirxel et al. 2021] Fast Exact Booleans for Iterated CSG using Octree-Embedded BSPs — integer homogeneous coordinates foundation
- [Bernstein & Fussell 2009] Fast, Exact, Linear Booleans — plane-based polygon definition
- [Jacobson et al. 2013] Robust Inside-Outside Segmentation using Generalized Winding Numbers
- [Zhou et al. 2016] Mesh Arrangements for Solid Geometry — WNV-based classification
