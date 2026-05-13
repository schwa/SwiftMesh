import ModelIO
import Testing

@Suite("ModelIO supported formats")
struct ModelIOFormatsTests {
    /// Print which common 3D mesh file extensions ModelIO claims it can import / export.
    ///
    /// Always on — useful as a reference when deciding whether to keep SwiftMeshIO.
    @Test("Print ModelIO importable/exportable extensions")
    func dumpSupportedExtensions() {
        let formats: [(ext: String, description: String)] = [
            ("obj",     "Wavefront OBJ — ubiquitous text geometry/material interchange"),
            ("ply",     "Stanford PLY — simple polygon mesh (ASCII/binary)"),
            ("stl",     "STL — triangle soup, common for 3D printing"),
            ("usd",     "Pixar USD — ambiguous: usually usdc; can be usda"),
            ("usda",    "USD ASCII"),
            ("usdc",    "USD Crate (binary)"),
            ("usdz",    "USD zip bundle (AR delivery format)"),
            ("abc",     "Alembic — animation/VFX interchange"),
            ("fbx",     "Autodesk FBX — game/VFX interchange"),
            ("dae",     "COLLADA — XML interchange (SceneKit territory)"),
            ("gltf",    "glTF JSON — web/runtime delivery format"),
            ("glb",     "glTF binary container"),
            ("3ds",     "Autodesk 3D Studio (legacy)"),
            ("x3d",     "X3D — successor to VRML"),
            ("blend",   "Blender native"),
            ("off",     "Object File Format — academic geometry-only"),
            ("vrml",    "VRML — legacy web 3D"),
            ("wrl",     "VRML alt extension"),
            ("3mf",     "3D Manufacturing Format — modern 3D printing"),
            ("amf",     "Additive Manufacturing Format — older 3D printing"),
            ("iges",    "CAD interchange (NURBS surfaces)"),
            ("igs",     "IGES alt extension"),
            ("step",    "CAD interchange (ISO 10303)"),
            ("stp",     "STEP alt extension"),
            ("scn",     "SceneKit native archive"),
            ("scnz",    "SceneKit zipped archive"),
            ("reality", "RealityKit native"),
            ("mdl",     "id Software Quake model")
        ]

        print("ModelIO format support:")
        print("  ext      import  export  description")
        for (ext, description) in formats {
            let canImport = MDLAsset.canImportFileExtension(ext)
            let canExport = MDLAsset.canExportFileExtension(ext)
            let extCol = ext.padding(toLength: 9, withPad: " ", startingAt: 0)
            let importCol = (canImport ? "yes" : "no ").padding(toLength: 8, withPad: " ", startingAt: 0)
            let exportCol = (canExport ? "yes" : "no ").padding(toLength: 8, withPad: " ", startingAt: 0)
            print("  \(extCol)\(importCol)\(exportCol)\(description)")
        }
    }
}
