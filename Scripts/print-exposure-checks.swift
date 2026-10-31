import Foundation
private struct Profile: Decodable { let channels: [[Double]], base: [Double], sensitivity: [[Double]] }
private struct Case: Decodable {
    let film: String,paper: String,midgray: [Double],midgrayComp: [Double]?,neutral: [Double],shift: [Double],preflashShift: [Double]
    let preflashExposure: Double,printExposure: Double,compensate: Bool,normalize: Bool,input: [[Double]],expected: [[Double]]
}
private struct Fixtures: Decodable { let profiles: [String: Profile], illuminant: [Double],wavelengths: [Double],cases: [Case] }
@main struct PrintExposureChecks {
    static func main() throws {
        let decoder=JSONDecoder();decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity:"Infinity",negativeInfinity:"-Infinity",nan:"NaN")
        let f=try decoder.decode(Fixtures.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        func v(_ a:[Double])->SIMD3<Double>{.init(a[0],a[1],a[2])}
        var maximum=0.0,count=0
        for c in f.cases {
            let film=f.profiles[c.film]!,paper=f.profiles[c.paper]!
            var p=PrintExposureCore.Parameters();p.neutral=v(c.neutral);p.shift=v(c.shift);p.preflashShift=v(c.preflashShift)
            p.preflashExposure=c.preflashExposure;p.printExposure=c.printExposure;p.compensate=c.compensate;p.normalize=c.normalize
            let enlarger=try PrintExposureCore.Enlarger(wavelengths:f.wavelengths,channels:film.channels.map(v),base:film.base,sensitivity:paper.sensitivity.map(v),illuminant:f.illuminant,midgray:c.midgray,compensatedMidgray:c.midgrayComp,parameters:p)
            for i in c.input.indices {
                let actual=enlarger.expose(v(c.input[i]))
                for ch in 0..<3 {
                    let error=abs(actual[ch]-c.expected[i][ch]);precondition(error<1e-11,"Print exposure mismatch \(c.film)/\(c.paper): \(error)")
                    maximum=max(maximum,error);count+=1
                }
            }
        }
        print("PASS: \(f.cases.count) print exposure/YM/preflash cases; \(count) values; max absolute error \(maximum)")
    }
}
