import simd

extension SIMD3<Float> {
    /// Unit-length copy, or `fallback` when the length is zero.
    func normalized(or fallback: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(self)
        return length > 0 ? self / length : fallback
    }
}
