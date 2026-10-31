import Foundation

@main struct Checks {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let library = try ModelLibrary(
            directory: root.appendingPathComponent("andreavolpato-spektrafilm/ModelData"))
        typealias RGB = SIMD3<Double>
        let gray = [RGB(repeating: 0.184)]
        func output(_ recipe: EditRecipe) throws -> RGB {
            try ColorPipeline(library: library, recipe: recipe).process(gray, width: 1, height: 1)[0]
        }
        func brightness(_ x: RGB) -> Double { (x.x + x.y + x.z) / 3 }
        var recipe = EditRecipe()
        recipe.flags["camera.auto_exposure"] = false
        let baseline = try output(recipe)
        recipe.numbers["camera.exposure_compensation_ev"] = 1
        let compensated = try output(recipe)
        recipe.flags["enlarger.print_exposure_compensation"] = false
        let uncompensated = try output(recipe)
        precondition(
            abs(brightness(compensated - baseline)) < abs(brightness(uncompensated - baseline)),
            "Print matching did not stabilize middle gray")
        recipe = EditRecipe()
        recipe.flags["camera.auto_exposure"] = false
        recipe.printExposureEV = 1
        let morePrintLight = try output(recipe)
        recipe.printExposureEV = -1
        let lessPrintLight = try output(recipe)
        precondition(
            brightness(morePrintLight) < brightness(baseline)
                && brightness(lessPrintLight) > brightness(baseline),
            "Print exposure direction was mislabeled")
        recipe.scanFilm = true
        let direct = try output(recipe)
        recipe.printExposureEV = 3
        recipe.numbers["enlarger.y_filter_shift"] = 20
        recipe.numbers["enlarger.m_filter_shift"] = -15
        let bypassed = try output(recipe)
        precondition(direct == bypassed, "Print settings affected direct scan")
        recipe = EditRecipe()
        let meter = try ColorPipeline(library: library, recipe: recipe).autoExposureEV(
            gray, width: 1, height: 1)
        recipe.numbers["camera.exposure_compensation_ev"] = 2
        let unchangedMeter = try ColorPipeline(library: library, recipe: recipe).autoExposureEV(
            gray, width: 1, height: 1)
        precondition(meter == unchangedMeter, "Manual offset changed source metering")
        print(
            "PASS: film/print exposure workflow — source metering, middle-gray matching, print-light direction and direct-scan bypass"
        )
    }
}
