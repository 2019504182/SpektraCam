import CoreGraphics
import Foundation
import ImageIO

@main struct Checks {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let directory = root.appendingPathComponent("andreavolpato-spektrafilm/Resources/ModelData")
        let paths = Array(CommandLine.arguments.dropFirst(2))
        guard !paths.isEmpty else {
            print("SKIP: provide source images with --input")
            return
        }
        var reports = [[String: Any]]()
        for path in paths {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let photo = ImportedPhoto.decode(data)!
            let renderer = PhotoRenderer(
                source: photo.preview, directory: directory, data: data, temperature: photo.rawTemperature)
            var recipe = EditRecipe()
            recipe.temperature = photo.rawTemperature
            let start = ProcessInfo.processInfo.systemUptime
            let preview = try await renderer.render(recipe)
            precondition(max(preview.width, preview.height) <= 1081)
            var full: (URL, Int, Int)?
            do {
                full = try await renderer.export(recipe, size: .full, format: .jpeg, quality: 0.95)
            } catch let error as RenderMemoryBudget.Failure {
                #if targetEnvironment(simulator)
                    print(
                        "PASS: full-size Simulator memory guard", URL(fileURLWithPath: path).lastPathComponent
                    )
                #else
                    throw error
                #endif
            }
            if let full {
                precondition(
                    max(full.1, full.2) == max(photo.width, photo.height),
                    "Full export used preview resolution")
                let encoded = CGImageSourceCreateWithURL(full.0 as CFURL, nil)!
                let image = CGImageSourceCreateImageAtIndex(encoded, 0, nil)!
                precondition(image.width == full.1 && image.height == full.2)
                let properties = CGImageSourceCopyPropertiesAtIndex(encoded, 0, nil)! as NSDictionary
                precondition(
                    (properties[kCGImagePropertyProfileName] as? String)?.contains("sRGB") == true,
                    "Export profile missing")
                print(
                    "PASS: processed full source", URL(fileURLWithPath: path).lastPathComponent, full.1,
                    full.2)
            }
            recipe.geometry.rotateLeft()
            recipe.crop.setAspect(
                .square, imageAspect: CGFloat(photo.preview.height) / CGFloat(photo.preview.width))
            recipe.tone.contrast = 1.2
            recipe.tone.monochrome = true
            recipe.monochromeGrain = true
            let smaller = try await renderer.export(recipe, size: .small, format: .png, quality: 1)
            precondition(smaller.1 == smaller.2 && smaller.1 <= 1080, "Cropped size cap incorrect")
            let smallSource = CGImageSourceCreateWithURL(smaller.0 as CFURL, nil)!
            let pixels = try PhotoColorBridge.decode(CGImageSourceCreateImageAtIndex(smallSource, 0, nil)!)
            precondition(
                pixels.allSatisfy { abs($0.x - $0.y) < 0.0001 && abs($0.y - $0.z) < 0.0001 },
                "Export did not apply neutral B&W")
            reports.append([
                "source": URL(fileURLWithPath: path).lastPathComponent, "raw": photo.rawTemperature != nil,
                "full": full.map { [$0.1, $0.2] } ?? [], "croppedSmall": [smaller.1, smaller.2],
                "seconds": ProcessInfo.processInfo.systemUptime - start,
                "fullFile": full?.0.path ?? "Memory guard", "smallFile": smaller.0.path,
            ])
            await renderer.discardExport()
            print(
                "PASS: cropped S export with tone, B&W and monochrome grain",
                URL(fileURLWithPath: path).lastPathComponent, smaller.1, smaller.2)
        }
        let out = root.appendingPathComponent("Reference/results/processed-export.json")
        try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys]).write(
            to: out)
    }
}
