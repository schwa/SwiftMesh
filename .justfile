default: list

list:
    just --list

build:
    swift build --quiet

test:
    swift test --quiet

coverage-percent:
    swift test --enable-code-coverage --quiet
    xcrun llvm-cov report \
        .build/arm64-apple-macosx/debug/SwiftMeshPackageTests.xctest/Contents/MacOS/SwiftMeshPackageTests \
        -instr-profile=.build/arm64-apple-macosx/debug/codecov/default.profdata \
        -ignore-filename-regex=".build|Tests" \
        | tail -1 | grep -oE '[0-9]+\.[0-9]+%' | head -n1

lint:
    swiftlint lint --quiet

format:
    swiftlint --fix --format --quiet

clean:
    swift package clean
    rm -rf .build
    rm -rf .swiftpm

convert-docs:
    swift package \
        generate-documentation \
        --target SwiftMesh \
        --target SwiftMeshIO \
        --target BinPacking \
        --enable-experimental-combined-documentation \
        --source-service github \
        --source-service-base-url https://github.com/schwa/SwiftMesh/blob/main \
        --checkout-path . \
        --transform-for-static-hosting \
        --output-path /tmp/SwiftMesh

preview-docs target="SwiftMesh":
    swift package \
        --disable-sandbox \
        preview-documentation \
        --target {{target}}

generate-doccarchive:
    swift package \
        --disable-sandbox \
        generate-documentation \
        --target SwiftMesh \
        --target SwiftMeshIO \
        --target BinPacking \
        --enable-experimental-combined-documentation \
        --source-service github \
        --source-service-base-url https://github.com/schwa/SwiftMesh/blob/main \
        --checkout-path . \
        --output-path /tmp/SwiftMesh.doccarchive

check-docs: generate-doccarchive
    lychee '/tmp/SwiftMesh.doccarchive/**/*.json' --verbose --scheme https --scheme http

list-external-links: generate-doccarchive
    lychee '/tmp/SwiftMesh.doccarchive/**/*.json' --scheme https --scheme http --verbose 2>&1 | grep -oE 'https?://[^ |]+' | sort -u

update-api:
    #!/usr/bin/env bash
    set -euo pipefail
    swift-api-tool . -o /tmp/public-api-new.yaml
    if diff -u .public-api.yaml /tmp/public-api-new.yaml > /tmp/public-api-diff 2>/dev/null; then
        echo "No API changes."
    else
        delta < /tmp/public-api-diff || cat /tmp/public-api-diff
        cp /tmp/public-api-new.yaml .public-api.yaml
        echo "Updated .public-api.yaml"
    fi

check-docs-diagnostics:
    #!/usr/bin/env bash
    for target in SwiftMesh SwiftMeshIO BinPacking; do
        swift package --disable-sandbox generate-documentation \
            --target "$target" \
            --diagnostics-file /tmp/docc-diagnostics.json \
            --output-path /tmp/SwiftMesh.doccarchive >/dev/null 2>&1
        jq -r '.diagnostics[] | if .source then "\(.source | sub("file://"; "")):\(.range.start.line): \(.summary)" else "\(.summary)" end' /tmp/docc-diagnostics.json 2>/dev/null
    done
