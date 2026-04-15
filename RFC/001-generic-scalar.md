# RFC: Generic Scalar Type for Mesh

**Status:** In Progress
**Issue:** #57
**Date:** 2026-04-15

## Summary

Make `Mesh` generic over its scalar type (`Float` / `Double`) so that double-precision meshes can be used for CSG and other operations that accumulate floating-point error.

## Approach

Rename `Mesh` to `GenericMesh<S: MeshScalar>` and add `typealias Mesh = GenericMesh<Float>` for backward compatibility. All existing code continues to compile unchanged.

### MeshScalar Protocol

A protocol that bridges Swift's non-generic simd free functions into a generic context:

- **Trig/math:** `sin`, `cos`, `atan2`, `sqrt`, `acos`
- **SIMD3 operations:** `cross`, `dot`, `length`, `normalize`, `distance`, `min`, `max`
- **Conformers:** `Float`, `Double`

### Similarly for TriangleSoup

`GenericTriangleSoup<S: MeshScalar>` with `typealias TriangleSoup = GenericTriangleSoup<Float>`.

## Migration Status

### ✅ Complete

| File | Notes |
|---|---|
| `MeshScalar.swift` | New. Protocol + Float/Double conformance |
| `Mesh.swift` | `GenericMesh<S>`. Float-specific transforms (`rotate(by: simd_quatf)`, `transform(by: simd_float4x4)`) constrained to `where S == Float` |
| `HalfEdgeTopology.swift` | Already scalar-free, no changes needed |
| `Subdivision.swift` | Fully generic. `cos` → `S.cos`, etc. |
| `Decimation.swift` | Fully generic. Replaced `simd_float3x3` inverse with manual Cramer's rule. `Quadric<S>`, `CollapseHeap<S>` |
| `Triangulation.swift` | Fully generic. SwiftEarcut already supports generic `BinaryFloatingPoint` via `PointProviding` |
| `TriangleSoup.swift` | `GenericTriangleSoup<S>` with typealias |
| `MeshAttributes.swift` | Mostly generic. `withTangents()` (MikkTSpace) constrained to `where S == Float` — C interop requires Float |
| `MeshAttributeSet.swift` | `applyAttributes` generic. `applyTangentAttributes` Float-only |

### 🔧 In Progress

| File | Notes |
|---|---|
| `MeshPrimitives.swift` | Being converted. `teapot()` stays `where S == Float` (ModelIO import). All other primitives becoming generic. Complex expressions may need break-up for type checker |

### ⏳ Remaining

| File | Notes |
|---|---|
| `MeshOptimization.swift` | `mergingCoplanarFaces` — could be generic, uses `simd_dot` etc. File-scope structs already at file level. Low priority |
| `CSG.swift` | Uses `TriangleSoup` (now generic). BSP internals (`CSGPlane`, `CSGPolygon`, `CSGNode`, `AABB`) all use `Float` directly. Medium effort |

### Float-only by Design

| File | Reason |
|---|---|
| `MetalMesh.swift` | GPU buffers are Float |
| `ModelIO+Mesh.swift` | ModelIO/MetalKit APIs are Float |

## Patterns

### Replacing simd free functions

```swift
// Before
simd_cross(a, b)
simd_dot(a, b)
simd_length(v)
simd_normalize(v)

// After
S.cross(a, b)
S.dot(a, b)
S.length(v)
S.normalize(v)
```

### Replacing trig functions

```swift
// Before
sin(x)
cos(x)
Float.pi

// After
S.sin(x)
S.cos(x)
S.pi
```

### Replacing Float casts

```swift
// Before
Float(someInt)

// After
S(someInt)
```

### Constructor calls inside generic extensions

```swift
// Before (resolves to GenericMesh<Float> via typealias)
return Mesh(topology: topo, positions: pos)

// After (resolves to GenericMesh<S>)
return GenericMesh(topology: topo, positions: pos)
```

### Local structs in generic functions

Swift doesn't allow local struct definitions inside generic function bodies. Move them to file scope:

```swift
// Before (error: type cannot be nested in generic function)
func foo() -> GenericMesh {
    struct Helper { ... }
}

// After
private struct Helper { ... }
func foo() -> GenericMesh { ... }
```

If the struct uses `S`, make it generic too: `private struct Helper<S: MeshScalar> { ... }` and use `Helper<S>` at call sites.

### Static stored properties in generic types

Not allowed. Use computed properties:

```swift
// Before (error: static stored properties not supported)
static let zero = Self(...)

// After
static var zero: Self { Self(...) }
```

### Complex expressions

The Swift type checker struggles with large generic expressions. Break them up:

```swift
// Before (timeout)
return a * x * x + 2 * b * x * y + ...

// After
var result: S = a * x * x
result += 2 * b * x * y
...
return result
```

### Float-specific APIs (matrices, quaternions, MikkTSpace)

Constrain to `where S == Float`:

```swift
public extension GenericMesh where S == Float {
    func rotate(by quaternion: simd_quatf) { ... }
    func withTangents() -> GenericMesh { ... }
}
```

## Issues Encountered

### Type Checker Performance

The Swift type checker struggles significantly with generic arithmetic expressions. Code that compiled instantly with concrete `Float` types causes "unable to type-check this expression in reasonable time" errors when generic. Every complex expression needs to be manually broken into sub-expressions with explicit intermediate variables. This is pervasive in math-heavy code (quadric error computation, Newell's method normals, etc.).

### Sendable Conformance

`SIMD3<S>` is not guaranteed `Sendable` when `S` is a generic `SIMDScalar`. `GenericMesh` and `GenericTriangleSoup` require `@unchecked Sendable` to work around this. The concrete types (`SIMD3<Float>`, `SIMD3<Double>`) are Sendable in practice, but the compiler can't prove it generically.

### No Generic simd Matrix Types

Swift's `simd_float3x3`, `simd_float4x4`, `simd_quatf` have no generic equivalent and no shared protocol. Any code that uses matrix operations (transforms, quadric error optimal position via matrix inverse) must either:
- Be constrained to `where S == Float`
- Reimplement the math manually (e.g. Cramer's rule instead of `simd_float3x3.inverse`)

We chose Cramer's rule for the 3×3 solve in decimation. Transforms (`rotate`, `transform(by:)`) are Float-only.

### No Generic simd Free Functions

Swift's `simd_cross`, `simd_dot`, `simd_normalize` etc. are overloaded for Float/Double but not generic. The entire `MeshScalar` protocol exists to bridge this gap. Every call site must change from `simd_cross(a, b)` to `S.cross(a, b)`. This is purely mechanical but touches hundreds of lines.

### Static Stored Properties in Generic Types

Swift prohibits `static let` in generic types. `Quadric.zero` had to become a computed `static var`. Minor but surprising.

### Local Structs in Generic Functions

Swift prohibits defining structs inside generic function bodies. Since `extension Mesh` (via typealias) makes methods generic, previously-local structs must be hoisted to file scope. Some need their own `<S: MeshScalar>` parameter.

### C Interop (MikkTSpace)

MikkTSpace tangent generation uses C callbacks that traffic in `Float` pointers. This entire subsystem must stay `where S == Float`. Users requesting tangents on a `GenericMesh<Double>` silently get no tangents.

### ModelIO / MetalKit

All Apple GPU/asset APIs are Float. The teapot primitive (OBJ import via ModelIO) and `MetalMesh` export are inherently Float-only. These are natural boundaries — convert at the edge.

## Benefits

### Confirmed

- **Double-precision CSG.** The primary motivation. BSP-based CSG accumulates error at each split plane intersection. Double gives ~15 vs ~7 significant digits, which matters for nested operations (difference of difference of union, etc.).
- **Double-precision subdivision.** Iterated subdivision also accumulates error. Catmull-Clark ×4 on a cube with Double will preserve symmetry better.
- **Clean architecture.** Topology (`HalfEdgeTopology`) was already scalar-free. Making geometry generic enforces a clean separation between topology and geometry.
- **Zero breakage.** The typealias approach means all existing code compiles without changes.

### Potential

- **Mixed-precision workflows.** Model in Double, export to Float for GPU. Issue #59 tracks the conversion API.
- **Validation.** Run the same operation in Float and Double, compare results to detect precision-sensitive code paths.
- **Future scalar types.** Half-precision (`Float16`) for mobile GPU vertex data, or fixed-point for deterministic geometry.

### Uncertain / Costs

- **Performance.** Double SIMD is half the throughput of Float SIMD on most hardware. For large meshes (100k+ faces), subdivision and decimation will be measurably slower in Double. Whether this matters depends on the use case — CSG accuracy vs. frame-rate mesh generation.
- **Code complexity.** Every math-heavy function now has `S.` prefixed calls instead of bare `simd_` functions. Readability is slightly worse. The MeshScalar protocol is boilerplate that exists only because Swift's simd module isn't generic.
- **API surface.** `GenericMesh<Float>` shows up in documentation and error messages instead of `Mesh`. The typealias helps at call sites but not in type signatures.
- **Tangent generation.** Double-precision meshes can't generate MikkTSpace tangents. This is a hard limitation of the C library. A pure-Swift MikkTSpace implementation would fix this but is significant work.

## Open Questions

1. **Should `GenericMesh` eventually be renamed back to `Mesh`?** The typealias works but means `Mesh` appears in docs as `GenericMesh<Float>`. Could use `@_typeEraser` or just accept it. Alternatively, keep the typealias permanently — it's a common Swift pattern.

2. **Float↔Double conversion API.** Issue #59 tracks adding `func converted<T: MeshScalar>() -> GenericMesh<T>`. Straightforward — just map positions and attributes through `T.init(_:)`.

3. **Should CSG operate in Double internally even for Float meshes?** Issue #58. With generic mesh, you could: convert to Double, run CSG, convert back. Clean separation.

4. **Is the MeshScalar protocol the right abstraction?** It exists solely to work around Swift's non-generic simd module. If Apple ever adds generic simd, the protocol becomes unnecessary. Should we petition for this upstream?

5. **Should primitives be generic?** A `GenericMesh<Double>.cube()` is valid but unusual. Most users want Float primitives for rendering. The generic versions add compile-time cost (more specializations). Could keep primitives Float-only and rely on conversion.
