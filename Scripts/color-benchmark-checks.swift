import Foundation
import Metal
private struct Fixture: Decodable {let input: [[Double]]}
@main struct ColorBenchmark {
    static func seconds(_ duration: Duration)->Double {let c=duration.components;return Double(c.seconds)+Double(c.attoseconds)/1e18}
    static func main() async throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),folder=root.appending(path:"andreavolpato-spektrafilm/ModelData")
        let fixture=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:root.appending(path:"Reference/Fixtures/color-pipeline.json")))
        let library=try ModelLibrary(directory:folder)
        var recipe=EditRecipe();recipe.flags["camera.auto_exposure"]=false
        let prepareStart=ContinuousClock.now,pipeline=try ColorPipeline(library:library,recipe:recipe)
        let prepare=seconds(prepareStart.duration(to:.now))
        let compileStart=ContinuousClock.now
        let engine=try MetalColorPipeline(source:String(contentsOf:folder.appending(path:"ColorPipeline.metalSource"),encoding:.utf8))
        let compile=seconds(compileStart.duration(to:.now))
        let width=1080,height=810
        let cpuInput=(0..<(width*height)).map {ModelLibrary.vector(fixture.input[$0 % fixture.input.count])}
        let input=cpuInput.map {SIMD4<Float>(Float($0.x),Float($0.y),Float($0.z),1)}
        let cpuStart=ContinuousClock.now,cpu=try pipeline.process(cpuInput,width:width,height:height)
        let cpuSeconds=seconds(cpuStart.duration(to:.now))
        let checksum=cpu.reduce(0.0){$0+$1.x+$1.y+$1.z}
        precondition(checksum.isFinite)
        var wall=[Double](),gpu=[Double]()
        for run in 0..<10 {
            let start=ContinuousClock.now,frame=try await engine.process(input,width:width,height:height,pipeline:pipeline)
            let elapsed=seconds(start.duration(to:.now))
            if run>=2 {wall.append(elapsed);gpu.append(frame.gpuSeconds)}
            precondition(frame.pixels.count==input.count)
        }
        let sorted=wall.sorted(),median=(sorted[3]+sorted[4])/2
        let report:[String:Any]=["device":MTLCreateSystemDefaultDevice()?.name ?? "unknown","platform":"macOS host, not iPhone", "width":width,"height":height,
          "build":"Swift -O; Metal safe/precise math","policy":"color-only; auto exposure disabled; buffers prepared per frame; GPU result copied to CPU",
          "prepare_seconds":prepare,"runtime_shader_compile_seconds":compile,"cpu_seconds":cpuSeconds,"metal_wall_median_seconds":median,
          "metal_wall_range_seconds":[sorted.first!,sorted.last!],"gpu_execution_seconds":gpu,"cpu_checksum":checksum]
        let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
        let destination=root.appending(path:"Reference/results/color-benchmark.json")
        try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
        try data.write(to:destination)
        print(String(data:data,encoding:.utf8)!)
    }
}
