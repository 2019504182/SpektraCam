import Foundation

/// Share immutable model data and compiled Metal kernels across library thumbnail jobs.
actor FilmRenderResources {
    private let directory: URL
    private var model: ModelLibrary?
    private var gpu: MetalFilmPipeline?

    init(directory: URL) { self.directory = directory }

    func load() throws -> (ModelLibrary, MetalFilmPipeline) {
        if model == nil { model = try ModelLibrary(directory: directory) }
        if gpu == nil {
            let sources = try ["ColorPipeline", "Spatial", "Grain", "Diffusion", "FilmPipeline"].map {
                try String(contentsOf: directory.appendingPathComponent($0 + ".metalSource"), encoding: .utf8)
            }
            gpu = try MetalFilmPipeline(sources: sources)
        }
        return (model!, gpu!)
    }
}
