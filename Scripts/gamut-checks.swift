import Foundation
private struct Case: Decodable {
    let space: String, white: [Double], lAxis: [Double], hAxis: [Double], byteOffset: Int, byteLength: Int
    let matrixToXYZ: [[Double]], matrixFromXYZ: [[Double]], input: [[Double]], expected: [[Double]]
}
private struct Fixtures: Decodable { let cases: [Case] }
@main struct GamutChecks {
    static func main() throws {
        let folder=URL(fileURLWithPath:CommandLine.arguments[1])
        let fixture=try JSONDecoder().decode(Fixtures.self,from:Data(contentsOf:folder.appending(path:"gamut-stages.json")))
        let bytes=try Data(contentsOf:folder.appending(path:"gamut-boundaries.f64"))
        func v(_ a:[Double])->SIMD3<Double>{.init(a[0],a[1],a[2])}
        var maximum=0.0,count=0
        for f in fixture.cases {
            let values=stride(from:f.byteOffset,to:f.byteOffset+f.byteLength,by:8).map { i in
                bytes.withUnsafeBytes { Double(bitPattern:UInt64(littleEndian:$0.loadUnaligned(fromByteOffset:i,as:UInt64.self))) }
            }
            let boundary=try GamutCore.Boundary(lightness:f.lAxis,hue:f.hAxis,values:values)
            let model=try GamutCore.CAM16Compression(white:v(f.white),boundary:boundary,matrixToXYZ:f.matrixToXYZ.map(v),matrixFromXYZ:f.matrixFromXYZ.map(v))
            for i in f.input.indices {
                let result=model.compress(v(f.input[i]))
                for ch in 0..<3 {
                    let error=abs(result[ch]-f.expected[i][ch])
                    precondition(error<1e-10,"Gamut mismatch \(f.space) input \(f.input[i]): \(result[ch]) vs \(f.expected[i][ch])")
                    maximum=max(maximum,error);count+=1
                }
            }
        }
        print("PASS: CAM16-UCS output compression in three RGB spaces; \(count) values; max absolute error \(maximum)")
    }
}
