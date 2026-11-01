import Foundation
import Metal

#if os(iOS)
    import os
#endif

/// Conservative admission check before decoding a full-size source. A rejected request
/// stays at the chosen size; it never silently substitutes a low-resolution export.
nonisolated enum RenderMemoryBudget {
    struct Failure: LocalizedError {
        var errorDescription: String? {
            "This size needs more rendering memory. Choose M or S and try again."
        }
    }
    static func check(width: Int, height: Int, recipe: EditRecipe) throws {
        guard width > 0, height > 0, width <= 65536, height <= 65536,
            let device = MTLCreateSystemDefaultDevice()
        else { throw Failure() }
        let pixels = UInt64(width) * UInt64(height)
        guard pixels <= UInt64(device.maxBufferLength / 16) else { throw Failure() }
        var estimate = pixels * 224 + 96 * 1024 * 1024
        if recipe.monochromeGrain && recipe.flag("film_render.grain.active") { estimate += pixels * 32 }
        if !recipe.tone.isIdentity { estimate += pixels * 48 }
        if recipe.look.mode == .lut { estimate += pixels * 96 }
        if recipe.temperature != nil { estimate += pixels * 32 }
        let pitch = recipe.number("camera.film_format_mm") * 1000 / Double(max(width, height))
        for prefix in ["camera.diffusion_filter", "enlarger.diffusion_filter"] {
            if prefix.hasPrefix("enlarger") && recipe.bypassesPrint { continue }
            guard recipe.flag(prefix + ".active"), recipe.number(prefix + ".strength") > 0 else { continue }
            var p = DiffusionCore.Parameters()
            p.family = recipe.choice(prefix + ".filter_family")
            p.spatialScale = recipe.number(prefix + ".spatial_scale")
            p.size = .init(
                recipe.number(prefix + ".core_size"), recipe.number(prefix + ".halo_size"),
                recipe.number(prefix + ".bloom_size"))
            let radius = try DiffusionCore.radius(
                width: width, height: height, pixelSize: pitch, parameters: p)
            func power(_ value: Int) -> UInt64 {
                var n: UInt64 = 1
                while n < value { n *= 2 }
                return n
            }
            estimate += power(width + 2 * radius) * power(height + 2 * radius) * 128
        }
        let processAllowance: UInt64
        #if os(iOS) && !targetEnvironment(simulator)
            processAllowance = UInt64(os_proc_available_memory()) * 3 / 4
        #else
            processAllowance = min(ProcessInfo.processInfo.physicalMemory / 3, 8 * 1024 * 1024 * 1024)
        #endif
        // Simulator reports zero when this advisory Metal limit is unavailable.
        // Use the process allowance then; zero must not reject every export size.
        let recommended = device.recommendedMaxWorkingSetSize
        let allocated = UInt64(device.currentAllocatedSize)
        let metalAllowance =
            recommended == 0
            ? processAllowance
            : (recommended > allocated ? recommended - allocated : 0)
        guard estimate < min(processAllowance, metalAllowance) else { throw Failure() }
    }
}
