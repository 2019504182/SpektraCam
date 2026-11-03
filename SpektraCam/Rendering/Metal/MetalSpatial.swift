import Foundation
import Metal

/// Test worker around the same encoders used by the combined photographic graph.
actor MetalSpatial {
    enum Failure: Error { case unavailable, allocation, command, invalidScale }
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let kernels: SpatialMetalKernels
    init(source: String) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw Failure.unavailable
        }
        let options = MTLCompileOptions()
        options.mathMode = .safe
        options.mathFloatingPointFunctions = .precise
        let library = try device.makeLibrary(source: source, options: options)
        self.device = device
        self.queue = queue
        kernels = try .init(device: device, library: library)
    }
    func filter(_ image: SpatialCore.Image, scale: SIMD3<Double>, exponential: Bool = false) async throws
        -> SpatialCore.Image
    {
        let input = try kernels.buffer(
            image.pixels.map { SIMD4<Float>(Float($0.x), Float($0.y), Float($0.z), 0) })
        let output = try kernels.allocate(input.length)
        let scratch = try kernels.scratch(length: input.length)
        guard let command = queue.makeCommandBuffer() else { throw Failure.allocation }
        try kernels.encode(
            input: input, output: output, width: image.width, height: image.height,
            scale: scale, exponential: exponential, scratch: scratch, command: command)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            command.addCompletedHandler { completed in
                if let error = completed.error {
                    continuation.resume(throwing: error)
                } else if completed.status != .completed {
                    continuation.resume(throwing: Failure.command)
                } else {
                    continuation.resume()
                }
            }
            command.commit()
        }
        let values = UnsafeBufferPointer(
            start: output.contents().assumingMemoryBound(to: SIMD4<Float>.self), count: image.pixels.count)
        return try SpatialCore.Image(
            width: image.width, height: image.height,
            pixels: values.map { SIMD3<Double>(Double($0.x), Double($0.y), Double($0.z)) })
    }
}

/// Immutable Metal pipelines. Frame-owned scratch is reused across sequential blur nodes;
/// no intermediate image leaves the GPU. Input, output and scratch buffers must be distinct.
nonisolated struct SpatialMetalKernels: Sendable {
    struct Scratch { let hi: MTLBuffer, lo: MTLBuffer }
    private let device: MTLDevice
    private let fir: MTLComputePipelineState, iir: MTLComputePipelineState, sum: MTLComputePipelineState
    init(device: MTLDevice, library: MTLLibrary) throws {
        func pipeline(_ name: String) throws -> MTLComputePipelineState {
            guard let function = library.makeFunction(name: name) else {
                throw MetalSpatial.Failure.unavailable
            }
            return try device.makeComputePipelineState(function: function)
        }
        self.device = device
        fir = try pipeline("fir_pass")
        iir = try pipeline("iir_pass")
        sum = try pipeline("weighted_sum")
    }
    func scratch(length: Int) throws -> Scratch {
        try .init(hi: allocate(length), lo: allocate(length))
    }
    func encode(
        input: MTLBuffer, output: MTLBuffer, width: Int, height: Int, scale: SIMD3<Double>,
        exponential: Bool = false, scratch: Scratch, command: MTLCommandBuffer
    ) throws {
        let count = width * height
        guard width > 0, height > 0, count <= Int(UInt32.max),
            (0..<3).allSatisfy({ scale[$0].isFinite && scale[$0] >= 0 }), input !== output,
            [scratch.hi, scratch.lo].allSatisfy({ $0 !== input && $0 !== output }),
            input.length >= count * 16, output.length >= count * 16
        else { throw MetalSpatial.Failure.invalidScale }
        try Task.checkCancellation()
        let hi = scratch.hi
        let lo = scratch.lo
        let fit = exponential ? [(0.1633, 0.5360), (0.6496, 1.5236), (0.1870, 2.7684)] : [(1.0, 1.0)]
        for (component, entry) in fit.enumerated() {
            let sigma = scale * entry.1
            var weights = Array(repeating: SIMD4<Float>.zero, count: 19)
            var coefficients = Array(repeating: SIMD4<Float>.zero, count: 8)
            for channel in 0..<3 {
                let s = sigma[channel]
                if s > 0 && s < 3 {
                    let radius = Int(3 * s + 0.5)
                    let values = (-radius...radius).map { exp(-0.5 * pow(Double($0) / s, 2)) }
                    let total = values.reduce(0, +)
                    for k in -radius...radius { weights[k + 9][channel] = Float(values[k + radius] / total) }
                } else {
                    weights[9][channel] = 1
                }
                let c = s >= 3 ? SpatialCore.iirCoefficients(s) : SIMD4<Double>(1, 0, 0, 0)
                for k in 0..<4 {
                    let high = Float(c[k])
                    coefficients[2 * k][channel] = high
                    coefficients[2 * k + 1][channel] = Float(c[k] - Double(high))
                }
            }
            let hasFIR = (0..<3).contains { sigma[$0] > 0 && sigma[$0] < 3 && Int(3 * sigma[$0] + 0.5) > 0 }
            let hasIIR = (0..<3).contains { sigma[$0] >= 3 }
            var current = input
            if hasFIR {
                let kernel = try buffer(weights)
                for axis in 0..<2 {
                    let target = axis == 0 ? hi : (!hasIIR && fit.count == 1 ? output : lo)
                    let encoder = try encoder(command, fir, [current, target, kernel])
                    var shape = SIMD4<UInt32>(UInt32(width), UInt32(height), UInt32(axis), 0)
                    encoder.setBytes(&shape, length: MemoryLayout.size(ofValue: shape), index: 3)
                    dispatch(encoder, fir, count)
                    current = target
                }
            }
            if hasIIR {
                // Each IIR thread owns one complete line. It reads the current input before
                // storing the forward pair, then consumes each pair before overwriting it.
                // These two work buffers can therefore hold input, recurrence and output.
                let constants = try buffer(coefficients)
                for axis in 0..<2 {
                    let target = axis == 0 ? hi : (fit.count == 1 ? output : lo)
                    let encoder = try encoder(command, iir, [current, target, hi, lo, constants])
                    var shape = SIMD4<UInt32>(UInt32(width), UInt32(height), UInt32(axis), 0)
                    encoder.setBytes(&shape, length: MemoryLayout.size(ofValue: shape), index: 5)
                    dispatch(encoder, iir, axis == 0 ? height : width)
                    current = target
                }
            }
            if current === output { continue }
            let encoder = try encoder(command, sum, [current, output])
            var mix = SIMD2<Float>(Float(entry.0), component == 0 ? 0 : 1)
            var elementCount = UInt32(count)
            encoder.setBytes(&mix, length: MemoryLayout.size(ofValue: mix), index: 2)
            encoder.setBytes(&elementCount, length: MemoryLayout.size(ofValue: elementCount), index: 3)
            dispatch(encoder, sum, count)
        }
    }
    func allocate(_ length: Int) throws -> MTLBuffer {
        guard let result = device.makeBuffer(length: length, options: .storageModeShared) else {
            throw MetalSpatial.Failure.allocation
        }
        return result
    }
    func buffer<T>(_ values: [T]) throws -> MTLBuffer {
        guard
            let result = values.withUnsafeBytes({
                device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
            })
        else { throw MetalSpatial.Failure.allocation }
        return result
    }
    private func encoder(
        _ command: MTLCommandBuffer, _ pipeline: MTLComputePipelineState, _ buffers: [MTLBuffer]
    ) throws -> MTLComputeCommandEncoder {
        guard let result = command.makeComputeCommandEncoder() else { throw MetalSpatial.Failure.allocation }
        result.setComputePipelineState(pipeline)
        for (i, buffer) in buffers.enumerated() { result.setBuffer(buffer, offset: 0, index: i) }
        return result
    }
    private func dispatch(
        _ encoder: MTLComputeCommandEncoder, _ pipeline: MTLComputePipelineState, _ count: Int
    ) {
        let width = min(128, pipeline.maxTotalThreadsPerThreadgroup)
        // Every spatial kernel bounds-checks its index. Full groups also support
        // Simulator devices that reject non-uniform threadgroups.
        encoder.dispatchThreadgroups(
            MTLSize(width: (count + width - 1) / width, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
        encoder.endEncoding()
    }
}
