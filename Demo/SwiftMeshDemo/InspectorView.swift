import SwiftMesh
import SwiftUI

struct InspectorView: View {
    @State private var mesh: Mesh = .cylinder()
    @State private var showInspector = true

    var body: some View {
        MeshInteractiveView(mesh: mesh)
            .inspector(isPresented: $showInspector) {
                Form {
                    Section("Topology") {
                        LabeledContent("Vertices", value: "\(mesh.vertexCount)")
                        LabeledContent("Faces", value: "\(mesh.faceCount)")
                        LabeledContent("Edges", value: "\(mesh.edgeCount)")
                        LabeledContent("Submeshes", value: "\(mesh.submeshes.count)")
                    }
                    Section("Attributes") {
                        LabeledContent("Normals", value: mesh.normals != nil ? "✓" : "—")
                        LabeledContent("UVs", value: mesh.textureCoordinates != nil ? "✓" : "—")
                        LabeledContent("Tangents", value: mesh.tangents != nil ? "✓" : "—")
                        LabeledContent("Bitangents", value: mesh.bitangents != nil ? "✓" : "—")
                        LabeledContent("Colors", value: mesh.colors != nil ? "✓" : "—")
                    }
                }
                .inspectorColumnWidth(min: 200, ideal: 250, max: 300)
            }
            .toolbar {
                Toggle(isOn: $showInspector) {
                    Label("Inspector", systemImage: "sidebar.right")
                }
            }
    }
}

#Preview {
    InspectorView()
}
