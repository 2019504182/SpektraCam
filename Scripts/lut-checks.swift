import CoreGraphics
import CoreImage
import Foundation

private func cubeText(
    title: String, low: Float = 0, high: Float = 1, transform: (SIMD3<Float>) -> SIMD3<Float>
) -> String {
    var text =
        "TITLE \"\(title)\"\nLUT_3D_SIZE 2\nDOMAIN_MIN \(low) \(low) \(low)\nDOMAIN_MAX \(high) \(high) \(high)\n"
    for b in 0...1 {
        for g in 0...1 {
            for r in 0...1 {
                let v = transform(
                    SIMD3<Float>(Float(r), Float(g), Float(b)) * (high - low) + SIMD3<Float>(repeating: low))
                text += "\(v.x) \(v.y) \(v.z)\n"
            }
        }
    }
    return text
}
private func decode(_ x: Float) -> Float { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
private func encode(_ x: Float) -> Float { x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055 }
private let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
private let context = CIContext(options: [.workingColorSpace: space, .workingFormat: CIFormat.RGBAf])
private func image(_ colors: [SIMD3<Float>]) -> CGImage {
    let pixels = colors.map { SIMD4<Float>(decode($0.x), decode($0.y), decode($0.z), 1) }
    let data = pixels.withUnsafeBytes { Data($0) }
    let source = CIImage(
        bitmapData: data, bytesPerRow: colors.count * 16, size: CGSize(width: colors.count, height: 1),
        format: .RGBAf, colorSpace: space)
    return context.createCGImage(source, from: source.extent, format: .RGBAf, colorSpace: space)!
}
@main struct Checks {
    @MainActor static func main() async throws {
        let identityData = Data(cubeText(title: "Identity # 1", transform: { $0 }).utf8)
        let identity = try CubeLUT(data: identityData, filename: "identity.cube")
        precondition(
            identity.size == 2 && identity.title == "Identity # 1" && identity.values[1].x == 1
                && identity.values[1].y == 0)
        for invalid in [
            "LUT_1D_SIZE 2\n0 0 0\n1 1 1", "LUT_3D_SIZE 66", "LUT_3D_SIZE 2\nnan 0 0", "LUT_3D_SIZE 2\n0 0 0",
            "LUT_3D_SIZE 2\nDOMAIN_MIN 1 0 0\nDOMAIN_MAX 0 1 1",
        ] {
            do {
                _ = try CubeLUT(data: Data(invalid.utf8), filename: "bad.cube")
                preconditionFailure("Invalid cube was accepted")
            } catch {}
        }
        let spatial = CGContext(
            data: nil, width: 64, height: 259, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        spatial.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1))
        spatial.fill(CGRect(x: 0, y: 0, width: 64, height: 259))
        let cleanImage = spatial.makeImage()!
        spatial.setFillColor(CGColor(red: 1, green: 0.2, blue: 0.1, alpha: 1))
        spatial.fill(CGRect(x: 3, y: 2, width: 19, height: 13))
        spatial.fill(CGRect(x: 7, y: 120, width: 31, height: 42))
        let spatialImage = spatial.makeImage()!
        let spatialInput = try PhotoColorBridge.decode(spatialImage)
        let spatialOutput = try PhotoColorBridge.decode(
            ToneRenderer.working(spatialImage, tone: .init(), luts: [.init(cube: identity, mix: 1)]))
        let spatialError = zip(spatialInput, spatialOutput).map {
            abs($0.x - $1.x) + abs($0.y - $1.y) + abs($0.z - $1.z)
        }.max()!
        precondition(spatialError < 0.0001, "LUT texture pass changed spatial detail or orientation")
        print("PASS: spatial identity LUT preserves edges and orientation; max error", spatialError)
        var stripeTone = EditRecipe.Tone()
        stripeTone.contrast = 1.2
        let whole = try PhotoColorBridge.decode(
            ToneRenderer.working(
                spatialImage, tone: stripeTone,
                luts: [.init(cube: identity, mix: 0.7)], residual: (spatialImage, cleanImage),
                monochromeResidual: true))
        let strips = try PhotoColorBridge.decode(
            ToneRenderer.tiledWorking(
                spatialImage, tone: stripeTone,
                luts: [.init(cube: identity, mix: 0.7)], residual: (spatialImage, cleanImage),
                monochromeResidual: true))
        let stripeError = zip(whole, strips).map { abs($0.x - $1.x) + abs($0.y - $1.y) + abs($0.z - $1.z) }
            .max()!
        precondition(stripeError < 0.00001, "Strip export changed pixels, orientation or boundary rows")
        print("PASS: strip/whole grade, LUT and monochrome grain agree; error", stripeError)
        let colors: [SIMD3<Float>] = [
            .init(0.8, 0.5, 0.2), .init(0.8, 0.2, 0.5), .init(0.5, 0.8, 0.2), .init(0.2, 0.8, 0.5),
            .init(0.5, 0.2, 0.8), .init(0.2, 0.5, 0.8), .init(-0.1, 1.4, 2),
        ]
        let source = image(colors)
        let bright = image(Array(repeating: SIMD3<Float>(repeating: 0.8), count: colors.count))
        let dark = image(Array(repeating: SIMD3<Float>(repeating: 0.2), count: colors.count))
        let added = try PhotoColorBridge.decode(
            ToneRenderer.working(source, tone: .init(), residual: (bright, dark)))
        precondition(
            added[0].x > decode(colors[0].x) + 0.4, "Effect residual did not reach the native texture pass")
        let unchanged = try PhotoColorBridge.decode(
            ToneRenderer.working(source, tone: .init(), luts: [.init(cube: identity, mix: 1)]))
        for (a, b) in zip(unchanged, colors) {
            precondition(
                abs(a.x - decode(b.x)) < 0.0001 && abs(a.y - decode(b.y)) < 0.0001
                    && abs(a.z - decode(b.z)) < 0.0001,
                "Identity clipped a channel or used the wrong cube order")
        }
        let tetra = try CubeLUT(
            data: Data(cubeText(title: "Tetra", transform: { v in .init(repeating: v.x * v.y * v.z) }).utf8),
            filename: "tetra.cube")
        let sampled = try PhotoColorBridge.decode(
            ToneRenderer.working(
                image(Array(colors.prefix(6))), tone: .init(), luts: [.init(cube: tetra, mix: 1)]))
        for pixel in sampled {
            precondition(abs(pixel.x - decode(0.2)) < 0.0001, "Tetrahedral interpolation failed")
        }
        let first = try CubeLUT(
            data: Data(cubeText(title: "Half Red", transform: { .init($0.x * 0.5, $0.y, $0.z) }).utf8),
            filename: "first.cube")
        let second = try CubeLUT(
            data: Data(cubeText(title: "Swap", transform: { .init($0.z, $0.y, $0.x) }).utf8),
            filename: "second.cube")
        let c = colors[0]
        let original = SIMD3<Float>(decode(c.x), decode(c.y), decode(c.z))
        let stage = SIMD3<Float>((decode(c.x * 0.5) + original.x) * 0.5, original.y, original.z)
        let expected = stage * 0.75 + SIMD3<Float>(stage.z, stage.y, stage.x) * 0.25
        let result = try PhotoColorBridge.decode(
            ToneRenderer.working(
                image([c]), tone: .init(),
                luts: [.init(cube: first, mix: 0.5), .init(cube: second, mix: 0.25)]))[0]
        precondition(
            abs(result.x - expected.x) < 0.0001 && abs(result.y - expected.y) < 0.0001
                && abs(result.z - expected.z) < 0.0001, "LUT order or linear-light mixes changed")
        let mixedDomain = try CubeLUT(
            data: Data(cubeText(title: "Domain", low: -1, high: 2, transform: { $0 }).utf8),
            filename: "domain.cube")
        let domainResult = try PhotoColorBridge.decode(
            ToneRenderer.working(source, tone: .init(), luts: [.init(cube: mixedDomain, mix: 1)]))
        precondition(
            zip(domainResult, unchanged).allSatisfy {
                abs($0.x - $1.x) < 0.0001 && abs($0.y - $1.y) < 0.0001 && abs($0.z - $1.z) < 0.0001
            })
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SpektraCam-LUT-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let file = base.appendingPathComponent("identity.cube")
        try identityData.write(to: file)
        var library: LUTLibrary? = LUTLibrary(root: base)
        let item = try await library!.importFile(file)
        let duplicate = try await library!.importFile(file)
        precondition(item.id == duplicate.id && library!.items.count == 1)
        try await library!.rename(item.id, name: "  Test Look  ")
        precondition(library!.name(item.id) == "Test Look")
        let secondFile = base.appendingPathComponent("second.cube")
        try Data(cubeText(title: "Second") { $0 * 0.5 }.utf8).write(to: secondFile)
        let secondItem = try await library!.importFile(secondFile)
        try await library!.move(from: IndexSet(integer: 1), to: 0)
        try await library!.load()
        precondition(library!.items.first?.id == secondItem.id, "Restart lost the LUT order")
        try await library!.remove([secondItem.id], protected: [])
        let owner = UUID()
        library!.protect(owner, ids: [item.id])
        do {
            try await library!.remove([item.id], protected: [])
            preconditionFailure("Deleted an active editor or Undo reference")
        } catch {}
        library!.release(owner)
        library = nil
        library = LUTLibrary(root: base)
        try await library!.load()
        precondition(library!.items.count == 1)
        precondition(library!.name(item.id) == "Test Look", "Restart lost the LUT name")
        do {
            try await library!.remove([item.id], protected: [item.id])
            preconditionFailure("Deleted a referenced LUT")
        } catch {}
        let restored = try CubeLUT.load(id: item.id, directory: library!.directory)
        precondition(restored.values == identity.values)
        try await library!.remove([item.id], protected: [])
        precondition(library!.items.isEmpty)
        let after = try Data(contentsOf: file)
        precondition(after == identityData, "LUT management changed the external file")
        let files = CommandLine.arguments.dropFirst().prefix(2).map { URL(fileURLWithPath: $0) }
        if files.count == 2 {
            let real = try files.map {
                try CubeLUT(data: Data(contentsOf: $0), filename: $0.lastPathComponent)
            }
            let one = try ToneRenderer.working(source, tone: .init(), luts: [.init(cube: real[0], mix: 1)])
            let two = try ToneRenderer.working(source, tone: .init(), luts: [.init(cube: real[1], mix: 1)])
            let together = try ToneRenderer.working(
                source, tone: .init(), luts: [.init(cube: real[0], mix: 0.6), .init(cube: real[1], mix: 0.4)])
            let a = try PhotoColorBridge.decode(one)
            let b = try PhotoColorBridge.decode(two)
            let c = try PhotoColorBridge.decode(together)
            precondition(
                a != b && c != a && c != b && c.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
            )
            print("PASS: supplied LUTs, separate and two-slot mixed renders:", files.map(\.lastPathComponent))
        }
        print(
            "PASS: 3D parser validation, red-fastest order, six tetrahedra, two sequential linear mixes, HDR/domain extension, durable import, duplicate linking and protected deletion"
        )
    }
}
