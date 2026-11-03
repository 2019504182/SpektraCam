#if DEBUG
    import Foundation
    import Metal
    import ImageIO
    import os

    /// Explicit launch-only check. Reads an app copy and writes a temporary report; never edits its recipe.
    @MainActor enum ExportValidation {
        static func checkBypass(_ library: PhotoLibrary) async {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "--check-bypass"), index + 1 < arguments.count,
                let requested = UUID(uuidString: arguments[index + 1]),
                let photo = library.photo(requested)
            else { return }
            do {
                let imported = try await library.files.decodedPhoto(photo)
                var recipe = EditRecipe()
                recipe.look.mode = .lut
                let sdr = try SourceImageRenderer.prepare(
                    data: imported.data, fallback: imported.preview, recipe: recipe, maximum: 1080)
                recipe.look.mode = .spektrafilm
                let hdr = try SourceImageRenderer.prepare(
                    data: imported.data, fallback: imported.preview, recipe: recipe, maximum: 1080)
                let a = sdr.pixels.reduce(0.0) { $0 + Double($1.y) } / Double(sdr.pixels.count)
                let b = hdr.pixels.reduce(0.0) { $0 + Double($1.y) } / Double(hdr.pixels.count)
                let report = ["sdrMean": a, "hdrMean": b, "ratio": b / a]
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]).write(
                    to: URL.cachesDirectory.appendingPathComponent("bypass-check.json"), options: .atomic)
                NSLog("BYPASS CHECK %@", report.description)
            } catch { NSLog("BYPASS CHECK failed %@", error.localizedDescription) }
        }
        static func run(_ library: PhotoLibrary) async {
            let arguments = ProcessInfo.processInfo.arguments
            let requestedID = arguments.firstIndex(of: "--check-photo").flatMap { index in
                index + 1 < arguments.count ? UUID(uuidString: arguments[index + 1]) : nil
            }
            guard arguments.contains("--check-export"),
                let photo = library.photos.first(where: {
                    $0.isRAW && (requestedID == nil || $0.id == requestedID)
                })
            else { return }
            var report: [String: String] = ["photo": photo.id.uuidString]
            let sampler = Task { () -> UInt64 in
                var minimum = UInt64(os_proc_available_memory())
                while !Task.isCancelled {
                    minimum = min(minimum, UInt64(os_proc_available_memory()))
                    do { try await Task.sleep(for: .milliseconds(20)) } catch { break }
                }
                return minimum
            }
            do {
                let imported = try await library.files.decodedPhoto(photo)
                let restored = try photo.recipeData.map {
                    try JSONDecoder().decode(EditRecipe.self, from: $0)
                }
                var recipe = restored ?? EditRecipe()
                recipe.temperature = imported.rawTemperature
                if ProcessInfo.processInfo.arguments.contains("--check-lut") {
                    recipe.look.mode = .lut
                    recipe.look.first.id = library.luts.items.first?.id
                }
                let renderer = PhotoRenderer(
                    source: imported.preview, directory: Bundle.main.resourceURL!, data: imported.data,
                    temperature: imported.rawTemperature, lutDirectory: library.luts.directory)
                report["availableMB"] = String(os_proc_available_memory() / 1_048_576)
                let start = ProcessInfo.processInfo.systemUptime
                let result = try await renderer.export(
                    recipe, size: .full, format: .jpeg, quality: 1,
                    allowOvercommit: arguments.contains("--check-overcommit"))
                guard let encoded = CGImageSourceCreateWithURL(result.0 as CFURL, nil),
                    let checked = CGImageSourceCreateImageAtIndex(encoded, 0, nil),
                    checked.width == result.1, checked.height == result.2
                else {
                    throw PhotoExporter.Failure.encode
                }
                report["result"] = "PASS"
                report["dimensions"] = "\(result.1)x\(result.2)"
                report["seconds"] = String(ProcessInfo.processInfo.systemUptime - start)
                try? FileManager.default.removeItem(at: result.0)
            } catch {
                report["result"] = "FAIL"
                report["error"] = error.localizedDescription
            }
            sampler.cancel()
            report["minimumHeadroomMB"] = String(await sampler.value / 1_048_576)
            let url = URL.cachesDirectory.appendingPathComponent("export-check.json")
            try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(
                to: url, options: .atomic)
            NSLog("EXPORT CHECK %@", report.description)
        }
    }
#endif
