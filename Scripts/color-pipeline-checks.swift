import Foundation
private struct Case: Decodable { let recipe: EditRecipe, expected: [[Double]] }
private struct Fixture: Decodable { let width: Int,height: Int,input: [[Double]],cases: [Case] }
@main struct PipelineChecks {
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1])
        let fixture=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:root.appending(path:"Reference/Fixtures/color-pipeline.json")))
        let library=try ModelLibrary(directory:root.appending(path:"andreavolpato-spektrafilm/ModelData"))
        let input=fixture.input.map(ModelLibrary.vector)
        var maximum=0.0,count=0
        for f in fixture.cases {
            let pipeline=try ColorPipeline(library:library,recipe:f.recipe)
            let output=try pipeline.process(input,width:fixture.width,height:fixture.height)
            for i in output.indices {for ch in 0..<3 {
                let error=abs(output[i][ch]-f.expected[i][ch])
                precondition(error<2e-8,"Pipeline mismatch \(f.recipe.filmID)/\(f.recipe.printID) pixel \(i), channel \(ch): \(output[i][ch]) vs \(f.expected[i][ch]); error \(error)")
                maximum=max(maximum,error);count+=1
            }}
        }
        print("PASS: \(fixture.cases.count) native end-to-end color-only cases; \(count) RGB values; max absolute error \(maximum)")
    }
}
