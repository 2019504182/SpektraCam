import CoreGraphics
import Foundation
import ImageIO

@main struct Checks {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let directory = root.appendingPathComponent("andreavolpato-spektrafilm/ModelData")
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
            let full = try await renderer.export(recipe, size: .full, format: .jpeg, quality: 0.95)
            precondition(
                max(full.1, full.2) == max(photo.width, photo.height), "Full export used preview resolution")
            let encoded = CGImageSourceCreateWithURL(full.0 as CFURL, nil)!
            let image = CGImageSourceCreateImageAtIndex(encoded, 0, nil)!
            precondition(image.width == full.1 && image.height == full.2)
            let properties = CGImageSourceCopyPropertiesAtIndex(encoded, 0, nil)! as NSDictionary
            precondition(
                (properties[kCGImagePropertyProfileName] as? String)?.contains("sRGB") == true,
                "Export profile missing")
            recipe.geometry.rotateLeft()
            recipe.crop.setAspect(
                .square, imageAspect: CGFloat(photo.preview.height) / CGFloat(photo.preview.width))
            let smaller = try await renderer.export(recipe, size: .small, format: .png, quality: 1)
            precondition(smaller.1 == smaller.2 && smaller.1 <= 1080, "Cropped size cap incorrect")
            reports.append([
                "source": URL(fileURLWithPath: path).lastPathComponent, "raw": photo.rawTemperature != nil,
                "full": [full.1, full.2], "croppedSmall": [smaller.1, smaller.2],
                "seconds": ProcessInfo.processInfo.systemUptime - start,
                "fullFile": full.0.path, "smallFile": smaller.0.path,
            ])
            await renderer.discardExport()
            print(
                "PASS: processed full source and cropped S export",
                URL(fileURLWithPath: path).lastPathComponent, full.1, full.2)
        }
        let out = root.appendingPathComponent("Reference/results/processed-export.json")
        try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys]).write(
            to: out)
    }
}
