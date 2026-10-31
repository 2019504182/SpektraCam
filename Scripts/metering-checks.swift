import Foundation
private struct Case: Decodable {
    let width: Int,height: Int,luminance: [Double],smallWidth: Int,smallHeight: Int,smallLuminance: [Double],expected: [String: Double]
}
private struct Fixtures: Decodable { let cases: [Case] }
@main struct MeteringChecks {
    static func main() throws {
        let fixture=try JSONDecoder().decode(Fixtures.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        var maximum=0.0,count=0
        for f in fixture.cases {
            let image=try MeteringCore.Image(width:f.width,height:f.height,luminance:f.luminance)
            let small=try image.smallPreview()
            precondition(small.width == f.smallWidth && small.height == f.smallHeight)
            for i in small.luminance.indices {
                let error=abs(small.luminance[i]-f.smallLuminance[i]);precondition(error<1e-12,"Metering resize mismatch: \(error)")
                maximum=max(maximum,error);count+=1
            }
            for (method,expected) in f.expected {
                let value=small.exposureEV(method:method),error=abs(value-expected)
                precondition(error<1e-11,"Metering \(method) mismatch: \(value) vs \(expected)")
                maximum=max(maximum,error);count+=1
            }
        }
        print("PASS: seven metering methods, six image shapes and anti-aliased preview sampling; \(count) values; max absolute error \(maximum)")
    }
}
