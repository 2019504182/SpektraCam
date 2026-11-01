import Foundation
import Metal

@main struct Benchmark {
  static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1])
    let data = root.appendingPathComponent("andreavolpato-spektrafilm/Resources/ModelData")
    let sources = try ["ColorPipeline", "Spatial", "Grain", "Diffusion", "FilmPipeline"].map {
      try String(contentsOf: data.appendingPathComponent($0 + ".metalSource"), encoding: .utf8)
    }
    let started = ProcessInfo.processInfo.systemUptime
    let gpu = try MetalFilmPipeline(sources: sources)
    let compile = ProcessInfo.processInfo.systemUptime - started
    let library = try ModelLibrary(directory: data)
    let width = 1080
    let height = 810
    var pattern = [SIMD4<Float>]()
    for i in 0..<64 {
      let r = Float((i * 17) % 61 + 1) / Float(62)
      let g = Float((i * 31) % 59 + 1) / Float(60)
      let b = Float((i * 13) % 53 + 1) / Float(54)
      pattern.append(SIMD4<Float>(r, g, b, 1))
    }
    let input = (0..<width * height).map { pattern[$0 % 64] }
    var results = [[String: Any]]()
    for name in ["default effects", "camera diffusion"] {
      var recipe = EditRecipe()
      recipe.flags["camera.auto_exposure"] = false
      if name == "camera diffusion" { recipe.flags["camera.diffusion_filter.active"] = true }
      let preparation = ProcessInfo.processInfo.systemUptime
      let pipeline = try FilmPipeline(library: library, recipe: recipe)
      let prepared = ProcessInfo.processInfo.systemUptime - preparation
      _ = try await gpu.process(
        input, width: width, height: height, pipeline: pipeline, seed: 1, autoExposureEV: 0)
      var walls = [Double]()
      var gpuTimes = [Double]()
      for _ in 0..<5 {
        let frame = try await gpu.process(
          input, width: width, height: height, pipeline: pipeline, seed: 1, autoExposureEV: 0)
        walls.append(frame.wallSeconds)
        if let time = frame.gpuSeconds { gpuTimes.append(time) }
      }
      results.append([
        "route": name, "wallMilliseconds": walls.map { $0 * 1000 },
        "wallMedianMilliseconds": walls.sorted()[walls.count / 2] * 1000,
        "gpuMilliseconds": gpuTimes.map { $0 * 1000 },
        "modelPreparationMilliseconds": prepared * 1000,
      ])
    }
    let configuration =
      ProcessInfo.processInfo.environment["SPEKTRAFILM_BENCHMARK_CONFIGURATION"] ?? "unknown"
    let report: [String: Any] = [
      "device": MTLCreateSystemDefaultDevice()!.name, "configuration": configuration,
      "width": width,
      "height": height,
      "shaderSetupMilliseconds": compile * 1000, "results": results,
      "scope":
        "Mac GPU synthetic full film graph with grain, halation, spatial DIR, print glare and scan sharpening. Cached 0 EV; input copies, encoding and Float32 readback included. Not an iPhone measurement.",
    ]
    let output = root.appendingPathComponent(
      "Reference/results/film-benchmark-" + configuration + ".json")
    try FileManager.default.createDirectory(
      at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(
        to: output)
    print(
      String(
        data: try JSONSerialization.data(withJSONObject: report, options: .prettyPrinted),
        encoding: .utf8)!)
  }
}
