import Foundation
private struct Case: Decodable {let kind: String,width: Int,height: Int,scale: [Double],input: [[Double]],expected: [[Double]]}
private struct Fixture: Decodable {let cases: [Case]}
@main struct SpatialChecks {
    static func main() throws {
        let fixture=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        func v(_ x:[Double])->SIMD3<Double>{.init(x[0],x[1],x[2])}
        var maximum=0.0,count=0
        for f in fixture.cases {
            let image=try SpatialCore.Image(width:f.width,height:f.height,pixels:f.input.map(v))
            let result=f.kind == "gaussian" ? image.gaussian(v(f.scale)) : image.exponential(v(f.scale))
            for i in result.pixels.indices {for ch in 0..<3 {
                let error=abs(result.pixels[i][ch]-f.expected[i][ch])
                precondition(error<1e-9,"Spatial \(f.kind) mismatch sigma \(f.scale), shape \(f.width)x\(f.height): \(error)")
                maximum=max(maximum,error);count+=1
            }}
        }
        print("PASS: \(fixture.cases.count) FIR/IIR/exponential spatial cases; \(count) values; max absolute error \(maximum)")
    }
}
