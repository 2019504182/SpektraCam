import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main struct Checks {
    static func main() throws {
        guard CommandLine.arguments.count > 1 else { print("SKIP: supply genuine RAW/JPEG paths with --input"); return }
        for path in CommandLine.arguments.dropFirst() {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let photo = ImportedPhoto.decode(data) else { preconditionFailure("Import failed: \(path)") }
            var recipe = EditRecipe(); recipe.temperature = photo.rawTemperature
            let initial = try SourceImageRenderer.prepare(data: data, fallback: photo.preview, recipe: recipe, maximum: 1080)
            precondition(max(initial.width, initial.height) <= 1081)
            precondition(initial.width < initial.height, "Portrait orientation was lost")
            recipe.source.exposureEV = 1
            let brighter = try SourceImageRenderer.prepare(data: data, fallback: photo.preview, recipe: recipe, maximum: 1080)
            let mean0 = initial.pixels.reduce(0.0) { $0 + Double($1.y) } / Double(initial.pixels.count)
            let mean1 = brighter.pixels.reduce(0.0) { $0 + Double($1.y) } / Double(brighter.pixels.count)
            precondition(mean1 > mean0 * 1.5, "Source EV was cancelled or clipped")
            if photo.rawTemperature != nil {
                recipe.source.exposureEV = 0
                recipe.temperature! += 1500
                let warm = try SourceImageRenderer.prepare(data: data, fallback: photo.preview, recipe: recipe, maximum: 1080)
                precondition(warm.pixels != initial.pixels, "RAW Kelvin did not affect pixels")
            }
            let type = CGImageSourceGetType(CGImageSourceCreateWithData(data as CFData,nil)!)! as String
            print(URL(fileURLWithPath: path).lastPathComponent, type, "RAW", photo.rawTemperature as Any,
                  "oriented",initial.width,initial.height,"EV brightness ratio",mean1/mean0)
        }
        print("PASS: provided files decode with upright pixels and source exposure; genuine RAW Kelvin affects decoded data")
    }
}
