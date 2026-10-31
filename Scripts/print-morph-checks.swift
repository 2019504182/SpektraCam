import Foundation
private struct Case: Decodable {
    let stock: String, positive: Bool, centers: [[Double]], amplitudes: [[Double]], sigmas: [[Double]], axis: [Double]
    let parameters: PrintChemistryCore.Parameters, expected: [[Double]]
}
private struct Fixtures: Decodable { let cases: [Case] }
@main struct MorphChecks {
    static func main() throws {
        let fixture=try JSONDecoder().decode(Fixtures.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        var maximum=0.0,count=0
        for f in fixture.cases {
            let model=try PrintChemistryCore.Model(centers:f.centers,amplitudes:f.amplitudes,sigmas:f.sigmas)
            let curves=try model.curves(axis:f.axis,parameters:f.parameters,positive:f.positive)
            for i in curves.indices { for channel in 0..<3 {
                let error=abs(curves[i][channel]-f.expected[i][channel])
                precondition(error<1e-8,"Print chemistry mismatch \(f.stock): \(error)")
                maximum=max(maximum,error);count+=1
            } }
        }
        print("PASS: \(fixture.cases.count) print-chemistry cases; \(count) values; max absolute error \(maximum)")
    }
}
