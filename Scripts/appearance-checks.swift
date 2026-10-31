import Foundation
private struct Case: Decodable { let white: [Double], input: [[Double]], jab: [[Double]], inverse: [[Double]] }
private struct Fixtures: Decodable { let cases: [Case] }
@main struct AppearanceChecks {
    static func main() throws {
        let fixtures=try JSONDecoder().decode(Fixtures.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        func v(_ a:[Double])->SIMD3<Double>{.init(a[0],a[1],a[2])}
        var maximum=0.0,count=0
        func check(_ actual:Double,_ expected:Double){
            let error=abs(actual-expected)
            precondition(error<1e-9+abs(expected)*1e-10,"CAM16 mismatch: \(actual) vs \(expected)")
            maximum=max(maximum,error);count+=1
        }
        for f in fixtures.cases {
            let model=AppearanceCore.CAM16(white:v(f.white))
            for i in f.input.indices {
                let jab=model.ucs(v(f.input[i])),xyz=model.xyz(v(f.jab[i]))
                for ch in 0..<3 {check(jab[ch],f.jab[i][ch]);check(xyz[ch],f.inverse[i][ch])}
            }
        }
        print("PASS: CAM16-UCS forward/inverse; \(count) values; max absolute error \(maximum)")
    }
}
