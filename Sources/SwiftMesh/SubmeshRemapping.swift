extension Mesh {
    /// Submeshes for a mesh rebuilt from this one.
    ///
    /// New face `i` joins the submesh of old face `sources[i]`. A `nil` source joins the first
    /// submesh. A source that belongs to no submesh leaves the new face unassigned.
    /// Labels and submesh order are kept; faces in each submesh are ordered by new face ID.
    func submeshes(rebuiltFrom sources: [HalfEdgeTopology.FaceID?]) -> [Submesh] {
        let groups = submeshIndexByFace()
        var result = submeshes.map { Submesh(label: $0.label, faces: []) }
        for (newFace, source) in sources.enumerated() {
            let group = source.map { groups[$0.raw] } ?? (result.isEmpty ? nil : 0)
            if let group {
                result[group].faces.append(.init(raw: newFace))
            }
        }
        return result
    }

    /// Adds `face` to the submesh that holds `source`, if any.
    mutating func addFace(_ face: HalfEdgeTopology.FaceID, toSubmeshOf source: HalfEdgeTopology.FaceID) {
        if let group = submeshes.firstIndex(where: { $0.faces.contains(source) }) {
            submeshes[group].faces.append(face)
        }
    }

    private func submeshIndexByFace() -> [Int?] {
        var groups = [Int?](repeating: nil, count: topology.faces.count)
        for (index, submesh) in submeshes.enumerated() {
            for face in submesh.faces where groups.indices.contains(face.raw) {
                groups[face.raw] = index
            }
        }
        return groups
    }
}
