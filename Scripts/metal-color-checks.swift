import Foundation
private struct Case: Decodable {let recipe: EditRecipe,expected: [[Double]]}
private struct Fixture: Decodable {let width: Int,height: Int,input: [[Double]],cases: [Case]}
@main struct MetalColorChecks {
    static func main() async throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1])
        let fixture=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:root.appending(path:"Reference/Fixtures/color-pipeline.json")))
        let folder=root.appending(path:"andreavolpato-spektrafilm/Resources/ModelData")
        let library=try ModelLibrary(directory:folder)
        let source=try String(contentsOf:folder.appending(path:"ColorPipeline.metalSource"),encoding:.utf8)
        let engine=try MetalColorPipeline(source:source)
        let input=fixture.input.map {SIMD4<Float>(Float($0[0]),Float($0[1]),Float($0[2]),1)}
        var maximum=0.0,count=0,gpuSeconds=0.0
        for f in fixture.cases {
            let pipeline=try ColorPipeline(library:library,recipe:f.recipe)
            let frame=try await engine.process(input,width:fixture.width,height:fixture.height,pipeline:pipeline)
            gpuSeconds += frame.gpuSeconds
            for i in frame.pixels.indices {for ch in 0..<3 {
                let actual=Double(frame.pixels[i][ch]),expected=f.expected[i][ch],error=abs(actual-expected)
                precondition(error<3e-5,"Metal color mismatch \(f.recipe.filmID)/\(f.recipe.printID), pixel \(i), ch \(ch): \(actual) vs \(expected); error \(error)")
                maximum=max(maximum,error);count+=1
            }}
        }
        print("PASS: Metal end-to-end color-only pipeline; \(fixture.cases.count) cases, \(count) RGB values; max absolute error \(maximum); GPU work \(gpuSeconds)s")
    }
}
