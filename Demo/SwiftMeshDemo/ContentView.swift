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
        }
    }
}

#Preview {
    ContentView()
}
