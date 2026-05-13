@testable import BinPacking
import simd
import Testing

@Suite
struct RectTests {
    @Test
    func intInit() {
        let r = Rect<Int>(x: 1, y: 2, width: 3, height: 4)
        #expect(r.minX == 1)
        #expect(r.minY == 2)
        #expect(r.maxX == 4)
        #expect(r.maxY == 6)
        #expect(r.area == 12)
    }

    @Test
    func contains() {
        let outer = Rect<Int>(x: 0, y: 0, width: 10, height: 10)
        let inner = Rect<Int>(x: 1, y: 1, width: 2, height: 2)
        #expect(outer.contains(inner))
        #expect(!inner.contains(outer))
    }

    @Test
    func intersects() {
        let a = Rect<Int>(x: 0, y: 0, width: 5, height: 5)
        let b = Rect<Int>(x: 4, y: 4, width: 5, height: 5)
        let c = Rect<Int>(x: 5, y: 5, width: 5, height: 5)
        #expect(a.intersects(b))
        #expect(!a.intersects(c))
    }

    @Test
    func sizeOnlyInit() {
        let r = Rect<Int>(size: SIMD2(7, 9))
        #expect(r.origin == SIMD2<Int>(0, 0))
        #expect(r.width == 7)
        #expect(r.height == 9)
        #expect(r.max == SIMD2<Int>(7, 9))
    }
}

@Suite
struct MaxRectsPackerTests {
    @Test
    func packsSingleItem() {
        var packer = MaxRectsPacker<Int>(binSize: SIMD2(100, 100))
        let result = packer.pack([SIMD2(50, 40)])
        #expect(result.allPlaced)
        #expect(result.placements.count == 1)
        #expect(result.placements[0].rect.size == SIMD2(50, 40))
    }

    @Test
    func placedItemsDoNotOverlapAndAreInBounds() {
        var packer = MaxRectsPacker<Int>(binSize: SIMD2(256, 256))
        let items: [SIMD2<Int>] = [
            SIMD2(64, 64), SIMD2(64, 32), SIMD2(32, 64), SIMD2(128, 32),
            SIMD2(32, 32), SIMD2(96, 96), SIMD2(48, 48), SIMD2(16, 200)
        ]
        let result = packer.pack(items)
        // All in-bounds.
        for p in result.placements {
            #expect(p.rect.minX >= 0 && p.rect.minY >= 0)
            #expect(p.rect.maxX <= 256 && p.rect.maxY <= 256)
        }
        // No two placed rects overlap.
        for i in 0..<result.placements.count {
            for j in (i + 1)..<result.placements.count {
                #expect(!result.placements[i].rect.intersects(result.placements[j].rect))
            }
        }
        SVGDump.dump(result, name: "placedItemsDoNotOverlapAndAreInBounds")
    }

    @Test
    func reportsUnplacedWhenBinIsFull() {
        var packer = MaxRectsPacker<Int>(binSize: SIMD2(10, 10))
        let result = packer.pack([SIMD2(10, 10), SIMD2(1, 1)])
        #expect(result.placements.count == 1)
        #expect(result.unplaced == [1])
        #expect(!result.allPlaced)
    }

    @Test
    func rotationEnablesFit() {
        var packer = MaxRectsPacker<Int>(binSize: SIMD2(10, 20), allowRotation: true)
        // 20x10 only fits rotated into a 10x20 bin.
        let result = packer.pack([SIMD2(20, 10)])
        #expect(result.allPlaced)
        #expect(result.placements[0].rotated)
    }

    @Test
    func rotationDisabledRejectsItem() {
        var packer = MaxRectsPacker<Int>(binSize: SIMD2(10, 20), allowRotation: false)
        let result = packer.pack([SIMD2(20, 10)])
        #expect(result.unplaced == [0])
    }

    @Test
    func lookupByStringID() {
        var packer = MaxRectsPacker<Int>(binSize: SIMD2(100, 100))
        let items = [
            PackingItem(id: "alpha", size: SIMD2(40, 40)),
            PackingItem(id: "beta", size: SIMD2(30, 30)),
            PackingItem(id: "gamma", size: SIMD2(200, 200))  // too large
        ]
        let result = packer.pack(items)
        #expect(result["alpha"] != nil)
        #expect(result["beta"] != nil)
        #expect(result["gamma"] == nil)
        #expect(result.unplaced == ["gamma"])
        #expect(result["alpha"]?.rect.size == SIMD2(40, 40))
    }

    @Test
    func lookupByIntIDViaConvenience() {
        var packer = MaxRectsPacker<Int>(binSize: SIMD2(100, 100))
        let result = packer.pack([SIMD2(40, 40), SIMD2(30, 30)])
        #expect(result[0] != nil)
        #expect(result[1] != nil)
        #expect(result[99] == nil)
    }

    @Test
    func worksWithFloatScalars() {
        var packer = MaxRectsPacker<Float>(binSize: SIMD2(1.0, 1.0))
        let result = packer.pack([SIMD2(0.4, 0.5), SIMD2(0.5, 0.5), SIMD2(0.1, 0.1)])
        #expect(result.allPlaced)
    }

    @Test
    func bestLongSideFitHeuristic() {
        var packer = MaxRectsPacker<Int>(binSize: SIMD2(100, 100), heuristic: .bestLongSideFit)
        let result = packer.pack([SIMD2(40, 40), SIMD2(30, 30), SIMD2(20, 20)])
        #expect(result.allPlaced)
        SVGDump.dump(result, name: "bestLongSideFit")
    }

    @Test
    func bestAreaFitHeuristic() {
        var packer = MaxRectsPacker<Int>(binSize: SIMD2(100, 100), heuristic: .bestAreaFit)
        let result = packer.pack([SIMD2(40, 40), SIMD2(30, 30), SIMD2(20, 20)])
        #expect(result.allPlaced)
        SVGDump.dump(result, name: "bestAreaFit")
    }

    @Test
    func bottomLeftHeuristic() {
        var packer = MaxRectsPacker<Int>(binSize: SIMD2(100, 100), heuristic: .bottomLeft)
        let result = packer.pack([SIMD2(40, 40), SIMD2(30, 30), SIMD2(20, 20)])
        #expect(result.allPlaced)
        SVGDump.dump(result, name: "bottomLeft")
    }

    /// Deterministic pseudo-random size list for stress packing.
    static func stressItems(count: Int, minSide: Int, maxSide: Int, seed: UInt64) -> [SIMD2<Int>] {
        var state = seed &+ 0x9E37_79B9_7F4A_7C15
        func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z &>> 31)
        }
        let range = UInt64(maxSide - minSide + 1)
        var items: [SIMD2<Int>] = []
        items.reserveCapacity(count)
        for _ in 0..<count {
            let w = Int(next() % range) + minSide
            let h = Int(next() % range) + minSide
            items.append(SIMD2(w, h))
        }
        return items
    }

    @Test
    func stressPackManyItems() {
        let items = Self.stressItems(count: 600, minSide: 8, maxSide: 64, seed: 42)
        var packer = MaxRectsPacker<Int>(binSize: SIMD2(512, 512))
        let result = packer.pack(items)
        // Sanity: no overlaps, all in bounds.
        for p in result.placements {
            #expect(p.rect.minX >= 0 && p.rect.minY >= 0)
            #expect(p.rect.maxX <= 512 && p.rect.maxY <= 512)
        }
        for i in 0..<result.placements.count {
            for j in (i + 1)..<result.placements.count {
                #expect(!result.placements[i].rect.intersects(result.placements[j].rect))
            }
        }
        SVGDump.dump(result, name: "stress")
    }

    @Test(arguments: [
        MaxRectsPacker<Int>.Heuristic.bestShortSideFit,
        .bestLongSideFit,
        .bestAreaFit,
        .bottomLeft
    ])
    func heuristicComparison(heuristic: MaxRectsPacker<Int>.Heuristic) {
        let items = Self.stressItems(count: 600, minSide: 8, maxSide: 64, seed: 42)
        var packer = MaxRectsPacker<Int>(binSize: SIMD2(512, 512), heuristic: heuristic)
        let result = packer.pack(items)
        let name: String
        switch heuristic {
        case .bestShortSideFit: name = "heuristic-bestShortSideFit"
        case .bestLongSideFit: name = "heuristic-bestLongSideFit"
        case .bestAreaFit: name = "heuristic-bestAreaFit"
        case .bottomLeft: name = "heuristic-bottomLeft"
        }
        SVGDump.dump(result, name: name)
    }

    @Test
    func paddingEnforcesGapBetweenItems() {
        var packer = MaxRectsPacker<Int>(binSize: SIMD2(100, 100), padding: 4)
        let result = packer.pack([SIMD2(40, 40), SIMD2(40, 40), SIMD2(40, 40), SIMD2(40, 40)])
        // Items must not overlap and must have at least 4 units of gap between any pair.
        for i in 0..<result.placements.count {
            for j in (i + 1)..<result.placements.count {
                let a = result.placements[i].rect
                let b = result.placements[j].rect
                #expect(!a.intersects(b))
                let xGap = Swift.max(a.minX, b.minX) - Swift.min(a.maxX, b.maxX)
                let yGap = Swift.max(a.minY, b.minY) - Swift.min(a.maxY, b.maxY)
                #expect(xGap >= 4 || yGap >= 4)
            }
        }
        SVGDump.dump(result, name: "padding")
    }

    @Test
    func paddingAllowsItemsToTouchBinBorder() {
        // 50+50+padding=104 wouldn't fit in 100 wide if padding stole from the border;
        // but border padding is free, so two 50x50 items fit with 4 px between them and 0 at edges? No — 50+4+50=104 > 100.
        // So instead verify two 48x48 items with padding 4 fit (48+4+48=100).
        var packer = MaxRectsPacker<Int>(binSize: SIMD2(100, 50), padding: 4, heuristic: .bottomLeft)
        let result = packer.pack([SIMD2(48, 48), SIMD2(48, 48)])
        #expect(result.allPlaced)
        // At least one item should sit flush against x=0 (no wasted border padding).
        #expect(result.placements.contains { $0.rect.minX == 0 })
    }

    @Test
    func resetClearsState() {
        var packer = MaxRectsPacker<Int>(binSize: SIMD2(100, 100))
        _ = packer.pack([SIMD2(100, 100)])
        packer.reset()
        let result = packer.pack([SIMD2(100, 100)])
        #expect(result.allPlaced)
    }
}
