import Foundation
import ImageIO

@main struct Checks {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 4 else {
            print("SKIP: supply a DNG and recipe JSON")
            return
        }
        let project = URL(fileURLWithPath: args[1])
        let data = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        let photo = ImportedPhoto.decode(data)!
        var recipe = try JSONDecoder().decode(
            EditRecipe.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
        recipe.temperature = photo.rawTemperature
        do {
            try RenderMemoryBudget.check(width: 65537, height: 1, recipe: recipe, allowOvercommit: true)
            preconditionFailure("Override bypassed hard dimension limits")
        } catch let failure as RenderMemoryBudget.Failure { precondition(failure.estimated == nil) }
        let renderer = PhotoRenderer(
            source: photo.preview,
            directory: project.appendingPathComponent("SpektraCam/Resources/ModelData"),
            data: data, temperature: photo.rawTemperature)
        let start = ProcessInfo.processInfo.systemUptime
        let result = try await renderer.export(
            recipe, size: .full, format: .jpeg, quality: 1, allowOvercommit: true)
        let source = CGImageSourceCreateWithURL(result.0 as CFURL, nil)!
        let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        precondition(decoded.width == result.1 && decoded.height == result.2)
        precondition(max(result.1, result.2) == max(photo.width, photo.height))
        print(
            "PASS: stress export", result.1, result.2, "seconds",
            ProcessInfo.processInfo.systemUptime - start, "file", result.0.path)
    }
}
