# ``SwiftMeshIO``

File and framework interchange for SwiftMesh meshes.

## Overview

Read and write Stanford PLY files (ASCII and binary), and convert meshes to RealityKit
`MeshResource`. ModelIO conversion (`MDLMesh`, `MDLAsset`) lives in SwiftMesh itself.

    let mesh = try PLY.read(from: data)
    let binary = PLY.write(mesh, format: .binaryLittleEndian)

## Topics

### PLY

- ``PLY``
- ``PLYError``

### RealityKit

- ``MeshResourceConversionError``
