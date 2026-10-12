@testable import BinPacking
import Testing

@Suite("Large packing")
struct LargePackingTests {
    /// RoomPlan-like charts: 145 surfaces plus 100 boxes with 6 faces each (745 total).
    private func roomPlanSizes() -> [SIMD2<Int>] {
        var state: UInt64 = 7
        func next(_ range: ClosedRange<Int>) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return range.lowerBound + Int(state >> 33) % (range.upperBound - range.lowerBound + 1)
        }
        var sizes = (0..<145).map { _ in SIMD2(next(60...420), next(60...300)) }
        for _ in 0..<100 {
            let box = SIMD3(next(10...120), next(10...120), next(10...120))
            sizes += [[box.x, box.y], [box.x, box.y], [box.y, box.z], [box.y, box.z], [box.x, box.z], [box.x, box.z]]
        }
        return sizes
    }

    @Test("745 charts all place, stay in the bin, and keep padding", arguments: [MaxRectsPacker<Int>.Heuristic.bestShortSideFit, .bestLongSideFit, .bestAreaFit, .bottomLeft])
    func roomPlan(heuristic: MaxRectsPacker<Int>.Heuristic) {
        let sizes = roomPlanSizes()
        let padding = 2
        var packer = MaxRectsPacker<Int>(binSize: [4_096, 4_096], padding: padding, heuristic: heuristic)
        let result = packer.pack(sizes)
        #expect(result.allPlaced)
        let bin = Rect<Int>(size: [4_096, 4_096])
        let rects = result.placements.map(\.rect)
        #expect(rects.allSatisfy { bin.contains($0) })
        for (index, rect) in rects.enumerated() {
            let grown = Rect(x: rect.minX - padding, y: rect.minY - padding, width: rect.width + 2 * padding, height: rect.height + 2 * padding)
            for other in rects[(index + 1)...] {
                #expect(!grown.intersects(other))
            }
        }
        // Placed sizes match the requests (allowing rotation).
        for placement in result.placements {
            let requested = sizes[placement.id]
            let placed = placement.rect.size
            #expect(placed == (placement.rotated ? SIMD2(requested.y, requested.x) : requested))
        }
    }
}
