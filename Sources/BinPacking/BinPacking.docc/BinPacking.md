# ``BinPacking``

Pack rectangles into a fixed-size bin with the MaxRects algorithm.

## Overview

Describe each item as a ``PackingItem`` (an id and a size), pack them with a
``MaxRectsPacker``, and read placements from the ``PackingResult``. Items that don't fit
are reported, not dropped silently. SwiftMesh uses this to lay out planar charts in a
texture atlas, but the library has no mesh dependencies.

    var packer = MaxRectsPacker<Int>(binSize: [1024, 1024], padding: 2)
    let result = packer.pack(items)
    for placement in result.placements { ... }

## Topics

### Packing

- ``MaxRectsPacker``
- ``PackingItem``
- ``PackedRect``
- ``PackingResult``
- ``BinPackingError``

### Geometry

- ``Rect``
- ``RectScalar``
