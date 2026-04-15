import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Platonic Solids", systemImage: "cube") {
                PlatonicSolidsGallery()
            }
            Tab("Surfaces", systemImage: "globe") {
                ParametricSurfacesGallery()
            }
            Tab("CSG", systemImage: "square.on.square.intersection.dashed") {
                CSGGallery()
            }
        }
    }
}

#Preview {
    ContentView()
}
