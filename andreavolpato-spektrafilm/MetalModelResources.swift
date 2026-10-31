import Foundation
import Metal

/// Immutable stock/curve/spectral buffers shared by color-only checks and the image graph.
/// Each actor owns its resources; mutable frame buffers never cross actor boundaries.
nonisolated struct MetalModelResources {
    enum Failure: Error { case allocation }
    let buffers: [MTLBuffer]
    let uniforms: [SIMD4<Float>]
    let shape: SIMD4<UInt32>, flags: SIMD4<UInt32>
    init(device: MTLDevice, pipeline: ColorPipeline) throws {
        func buffer<T>(_ values: [T]) throws -> MTLBuffer {
            guard
                let result = values.withUnsafeBytes({
                    device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
                })
            else { throw Failure.allocation }
            return result
        }
        func vector(_ rgb: SIMD3<Double>, _ fourth: Double = 0) -> SIMD4<Float> {
            .init(Float(rgb.x), Float(rgb.y), Float(rgb.z), Float(fourth))
        }
        func curve(_ curve: SpectralCore.DensityCurve) -> [SIMD4<Float>] {
            curve.values.indices.map { vector(curve.values[$0], curve.axis[$0]) }
        }
        let coupled = pipeline.coupledDevelopment
        let printCurve = pipeline.printCurve ?? pipeline.filmCurve
        let table = try buffer(pipeline.exposure.table.samples.map { vector($0) })
        let original = try buffer(curve(pipeline.filmCurve))
        let corrected = try buffer(curve(coupled?.beforeCouplers ?? pipeline.filmCurve))
        let paper = try buffer(curve(printCurve))
        var printSamples = [SIMD4<Float>]()
        if let enlarger = pipeline.enlarger {
            for i in enlarger.channels.indices {
                printSamples.append(vector(enlarger.channels[i], enlarger.base[i]))
                printSamples.append(vector(enlarger.sensitivity[i] * enlarger.printLight[i]))
            }
        } else {
            printSamples = [.zero]
        }
        var scanSamples = [SIMD4<Float>]()
        let scan = pipeline.scanBasis
        for i in scan.channels.indices {
            scanSamples.append(vector(scan.channels[i], scan.base[i]))
            scanSamples.append(vector(scan.cmfs[i] * scan.illuminant[i] / scan.normalization))
        }
        let printBasis = try buffer(printSamples)
        let scanBasis = try buffer(scanSamples)
        let boundary = try buffer(pipeline.compression.boundary.values.map(Float.init))
        var preparedUniforms = Array(repeating: SIMD4<Float>.zero, count: 30)
        preparedUniforms[0] = SIMD4(
            Float(pow(2, pipeline.recipe.number("camera.exposure_compensation_ev"))), 1,
            0, 0)
        preparedUniforms[1] = vector(coupled?.maximum ?? .zero)
        for i in 0..<3 {
            preparedUniforms[2 + i] = vector(pipeline.exposure.rgbBasisXYZ[i])
            preparedUniforms[5 + i] = vector(coupled?.matrix.rows[i] ?? .zero)
            preparedUniforms[10 + i] = vector(pipeline.scanMatrix[i])
            preparedUniforms[13 + i] = vector(pipeline.encodingMatrix[i])
            preparedUniforms[16 + i] = vector(pipeline.compression.matrixToXYZ[i])
            preparedUniforms[19 + i] = vector(pipeline.compression.matrixFromXYZ[i])
            preparedUniforms[27 + i] = vector(pipeline.compression.appearance.inverse16[i])
        }
        if let enlarger = pipeline.enlarger {
            preparedUniforms[8] = SIMD4(Float(enlarger.factor), Float(enlarger.printExposure), 0, 0)
            preparedUniforms[9] = vector(enlarger.preflash)
        }
        let cam = pipeline.compression.appearance
        let bounds = pipeline.compression.boundary
        preparedUniforms[22] = vector(cam.adaptation, cam.fl)
        preparedUniforms[23] = SIMD4(Float(cam.n), Float(cam.nbb), Float(cam.z), Float(cam.aw))
        preparedUniforms[24] = SIMD4(Float(pipeline.compression.whiteJ), 0, 0, 0)
        preparedUniforms[25] = SIMD4(
            Float(bounds.lightness[0]), Float(bounds.lightness.last!), Float(bounds.lightness.count),
            Float(bounds.hue.count))
        preparedUniforms[26] = SIMD4(Float(bounds.hue[0]), Float(bounds.hue[1] - bounds.hue[0]), 0, 0)
        buffers = [table, original, corrected, paper, printBasis, scanBasis, boundary]
        uniforms = preparedUniforms
        shape = SIMD4<UInt32>(
            0, UInt32(pipeline.exposure.table.size), UInt32(pipeline.filmCurve.axis.count),
            UInt32(printCurve.axis.count))
        flags = SIMD4<UInt32>(
            coupled == nil ? 0 : 1, coupled?.positive == true ? 1 : 0, pipeline.recipe.bypassesPrint ? 1 : 0,
            UInt32(scan.channels.count))
    }
}
