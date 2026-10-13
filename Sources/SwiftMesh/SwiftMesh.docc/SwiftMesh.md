# ``SwiftMesh``

Half-edge meshes with n-gon faces, per-corner attributes, mesh operations, and Metal export.

## Overview

A ``Mesh`` has a ``HalfEdgeTopology``, vertex positions, and optional per-corner attributes. The
topology connects vertices, half-edges, and faces. A face can be any polygon, and it can have holes.
SwiftMesh triangulates faces only for ``MetalMesh`` export and for operations that need triangles.

You can make a mesh from a primitive, a path, text, a set of points, or a scalar field. Then you can
edit the mesh and examine it with the diagnostics. To draw the mesh, convert it to a ``MetalMesh``.

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

### Editing

- ``Mesh/splitEdge(_:at:)``
- ``Mesh/flipEdge(_:)``
- ``Mesh/extrudingFace(_:distance:)``
- ``Mesh/chamfered(distance:segments:edges:attributes:)``
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
- ``Mesh/windingNumbers(at:)``

### Texture Atlases

- ``AtlasLayout``

### 2D Meshes

- ``Mesh2D``
