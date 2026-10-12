# ``SwiftMesh``

Half-edge meshes with n-gon faces, per-corner attributes, mesh operations, and Metal export.

## Overview

A ``Mesh`` pairs a ``HalfEdgeTopology`` (pure wiring: vertices, half-edges, faces) with
vertex positions and optional per-corner attributes. Faces can be any polygon, with holes.
Triangulation happens only where needed: at ``MetalMesh`` export and inside operations that
require triangles.

Build meshes from primitives, paths, text, point sets, or scalar fields; edit them; check
them with diagnostics; then upload them with ``MetalMesh``.

    let mesh = Mesh.cube().withSmoothNormals()
    let metalMesh = MetalMesh(mesh: mesh, device: device)
    encoder.draw(metalMesh)

## Topics

### Essentials

- ``Mesh``
- ``HalfEdgeTopology``
- ``MeshAttributes``
- ``MetalMesh``

### Creating Meshes

- ``Mesh/cube(extents:attributes:)``
- ``Mesh/icoSphere(extents:subdivisions:attributes:)``
- ``Mesh/convexHull(of:attributes:)``
- ``Mesh/convexHull(ofSpheres:subdivisions:attributes:)``
- ``Mesh/extrudedText(_:font:depth:mode:curveSegments:attributes:)``
- ``ExtrusionMode``
- ``Mesh/merged(_:)``
- ``TriangleSoup``

### Editing

- ``Mesh/splitEdge(_:at:)``
- ``Mesh/flipEdge(_:)``
- ``Mesh/extrudingFace(_:distance:)``
- ``Mesh/chamfered(distance:edges:attributes:)``
- ``Mesh/split(planeNormal:point:capped:weldTolerance:)``
- ``Mesh/reversingWinding()``
- ``Mesh/reversingWinding(of:)``

### Whole-Mesh Operations

- ``Mesh/triangulated()``
- ``Mesh/decimated(ratio:)``
- ``Mesh/loopSubdivided(iterations:)``
- ``Mesh/catmullClarkSubdivided(iterations:)``
- ``Mesh/csg(_:_:options:)``
- ``CSGOperation``
- ``CSGOptions``

### Diagnostics

- ``Mesh/validate()``
- ``ValidationIssue``
- ``SurfaceComponent``
- ``Mesh/withConsistentWinding()``

### Texture Atlases

- ``AtlasLayout``

### 2D Meshes

- ``Mesh2D``
