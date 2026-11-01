@preconcurrency import AVFoundation
import Foundation

nonisolated enum CameraFormat: String, CaseIterable, Identifiable, Sendable {
    case proRAW, bayerRAW
    var id: Self { self }
    var title: String { self == .proRAW ? "Apple ProRAW" : "Bayer RAW" }
}

nonisolated enum CameraFailure: LocalizedError {
    case unavailable, denied, configuration, rawUnavailable, notReady, noData
    var errorDescription: String? {
        switch self {
        case .unavailable: "Camera capture needs a physical iPhone."
        case .denied: "Allow camera access in Settings to take photos."
        case .configuration: "The camera could not start."
        case .rawUnavailable: "This camera does not support RAW capture."
        case .notReady: "The camera is not ready. Try again."
        case .noData: "The camera did not return a RAW photo."
        }
    }
}

/// Session configuration, capture and file writing run away from the main actor.
actor CameraService {
    nonisolated enum Event: Sendable {
        case ready(Bool)
        case interrupted, resumed
        case failed(String)
        case readings(CameraReadings)
    }
    nonisolated let events: AsyncStream<Event>
    private let sink: AsyncStream<Event>.Continuation
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let video = AVCaptureVideoDataOutput()
    private let meterQueue = DispatchQueue(label: "SpektraCam.CameraMeter", qos: .utility)
    private var meter: CameraMeter?
    private var devices: [String: AVCaptureDevice] = [:]
    private var lenses: [CameraLens] = []
    private var activeLens: CameraLens?
    private var macro = false
    private var source: CameraPreviewSource?
    private var formats: [CameraFormat: OSType] = [:]
    private var capture: RAWPhotoCapture?
    private var stopRequested = false
    private var closed = false
    private var observations: [NSObjectProtocol] = []
    private var readiness: NSKeyValueObservation?

    init() {
        let channel = AsyncStream<Event>.makeStream(bufferingPolicy: .bufferingNewest(8))
        events = channel.stream
        sink = channel.continuation
    }
    struct Configuration: Sendable {
        let source: CameraPreviewSource
        let formats: [CameraFormat]
        let lenses: [CameraLens]
        let selectedLens: CameraLens
        let macro: Bool
    }
    func start() async throws -> Configuration {
        guard !closed else { throw CancellationError() }
        #if targetEnvironment(simulator)
            throw CameraFailure.unavailable
        #else
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            var allowed = status == .authorized
            if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
            guard !closed else { throw CancellationError() }
            guard allowed else { throw CameraFailure.denied }
            if source == nil { try configure() }
            stopRequested = false
            if !session.isRunning { session.startRunning() }
            guard session.isRunning, source != nil else { throw CameraFailure.configuration }
            sink.yield(.ready(output.captureReadiness == .ready))
            return try configuration()
        #endif
    }
    private func configuration() throws -> Configuration {
        guard let source, let activeLens else { throw CameraFailure.configuration }
        return Configuration(
            source: source, formats: CameraFormat.allCases.filter { formats[$0] != nil },
            lenses: lenses, selectedLens: activeLens, macro: macro)
    }
    private func configure() throws {
        let discovered = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video, position: .unspecified
        ).devices.filter { !$0.isVirtualDevice }
        devices = Dictionary(uniqueKeysWithValues: discovered.map { ($0.uniqueID, $0) })
        lenses = discovered.map {
            CameraLens(
                id: $0.uniqueID, millimeters: Int($0.nominalFocalLengthIn35mmFilm.rounded()),
                front: $0.position == .front,
                macro: $0.deviceType == .builtInUltraWideCamera
                    && $0.isFocusModeSupported(.continuousAutoFocus),
                primary: $0.deviceType == .builtInWideAngleCamera)
        }.sorted { $0.front == $1.front ? $0.millimeters < $1.millimeters : !$0.front }
        guard
            let device = discovered.first(where: {
                $0.position == .back && $0.deviceType == .builtInWideAngleCamera
            })
        else { throw CameraFailure.unavailable }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        for old in session.inputs { session.removeInput(old) }
        for old in session.outputs { session.removeOutput(old) }
        session.sessionPreset = .photo
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraFailure.configuration }
        session.addInput(input)
        guard session.canAddOutput(output) else { throw CameraFailure.configuration }
        session.addOutput(output)
        if session.canAddOutput(video) {
            session.addOutput(video)
            video.alwaysDiscardsLateVideoFrames = true
            video.automaticallyConfiguresOutputBufferDimensions = false
            video.deliversPreviewSizedOutputBuffers = true
        }
        try configureOutput(device: device, macro: false)
        activeLens = lenses.first { $0.id == device.uniqueID }
        observeSession()
    }
    private func configureOutput(device: AVCaptureDevice, macro: Bool) throws {
        try device.lockForConfiguration()
        device.videoZoomFactor = 1
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        if device.isAutoFocusRangeRestrictionSupported {
            device.autoFocusRangeRestriction = macro ? .near : .none
        }
        device.unlockForConfiguration()
        output.isAppleProRAWEnabled = output.isAppleProRAWSupported
        output.maxPhotoQualityPrioritization = .quality
        if let dimensions = device.activeFormat.supportedMaxPhotoDimensions.min(by: {
            Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
        }) {
            output.maxPhotoDimensions = dimensions
        }
        formats = [:]
        for value in output.availableRawPhotoPixelFormatTypes {
            if AVCapturePhotoOutput.isAppleProRAWPixelFormat(value) { formats[.proRAW] = value }
            if AVCapturePhotoOutput.isBayerRAWPixelFormat(value) { formats[.bayerRAW] = value }
        }
        guard !formats.isEmpty else { throw CameraFailure.rawUnavailable }
        if session.outputs.contains(video) {
            guard
                let type = [
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                ].first(where: { video.availableVideoPixelFormatTypes.contains($0) })
            else {
                video.setSampleBufferDelegate(nil, queue: nil)
                meter = nil
                source = CameraPreviewSource(session: session, device: device)
                return
            }
            video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: type]
            let sink = sink
            meter = CameraMeter(device: device) { sink.yield(.readings($0)) }
            video.setSampleBufferDelegate(meter, queue: meterQueue)
        }
        source = CameraPreviewSource(session: session, device: device)
    }
    func selectLens(_ id: String, macro: Bool = false) throws -> Configuration {
        guard !closed, capture == nil, let device = devices[id],
            let lens = lenses.first(where: { $0.id == id }),
            let previous = session.inputs.first as? AVCaptureDeviceInput
        else { throw CameraFailure.notReady }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.removeInput(previous)
        do {
            guard session.canAddInput(input) else { throw CameraFailure.configuration }
            session.addInput(input)
            try configureOutput(device: device, macro: macro && lens.macro)
            activeLens = lens
            self.macro = macro && lens.macro
        } catch {
            if session.inputs.contains(input) { session.removeInput(input) }
            if session.canAddInput(previous) { session.addInput(previous) }
            try? configureOutput(device: previous.device, macro: self.macro)
            throw error
        }
        return try configuration()
    }
    private func observeSession() {
        guard observations.isEmpty else { return }
        let sink = sink
        let center = NotificationCenter.default
        observations = [
            center.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil
            ) { _ in
                sink.yield(.interrupted)
            },
            center.addObserver(
                forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil
            ) { _ in
                sink.yield(.resumed)
            },
            center.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
            ) { note in
                let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
                sink.yield(.failed(error?.localizedDescription ?? "The camera stopped. Try again."))
            },
        ]
        readiness = output.observe(\.captureReadiness, options: [.initial, .new]) { output, _ in
            sink.yield(.ready(output.captureReadiness == .ready))
        }
    }
    func stop() {
        stopRequested = true
        if capture == nil && session.isRunning { session.stopRunning() }
    }
    func shutdown() {
        closed = true
        stop()
        observations.forEach(NotificationCenter.default.removeObserver)
        observations.removeAll()
        readiness = nil
        video.setSampleBufferDelegate(nil, queue: nil)
        meter = nil
        sink.finish()
    }
    func takePhoto(format: CameraFormat, rotation: CGFloat, inbox: CameraInbox) async throws -> URL {
        guard capture == nil, session.isRunning, !session.isInterrupted,
            output.captureReadiness == .ready, let pixelFormat = formats[format]
        else { throw CameraFailure.notReady }
        let settings = AVCapturePhotoSettings(rawPixelFormatType: pixelFormat)
        settings.maxPhotoDimensions = output.maxPhotoDimensions
        settings.photoQualityPrioritization = format == .bayerRAW ? .speed : .quality
        if let codec = settings.availableRawEmbeddedThumbnailPhotoCodecTypes.first {
            let size = output.maxPhotoDimensions
            let scale = 1080.0 / Double(max(size.width, size.height))
            settings.rawEmbeddedThumbnailPhotoFormat = [
                AVVideoCodecKey: codec, AVVideoWidthKey: max(1, Int(Double(size.width) * scale)),
                AVVideoHeightKey: max(1, Int(Double(size.height) * scale)),
            ]
        }
        guard let connection = output.connection(with: .video) else { throw CameraFailure.notReady }
        let angle =
            connection.isVideoRotationAngleSupported(rotation)
            ? rotation : (rotation / 90).rounded() * 90
        guard connection.isVideoRotationAngleSupported(angle) else { throw CameraFailure.configuration }
        connection.videoRotationAngle = angle
        defer {
            capture = nil
            if stopRequested && session.isRunning { session.stopRunning() }
        }
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = RAWPhotoCapture(inbox: inbox, continuation: continuation)
            capture = delegate
            output.capturePhoto(with: settings, delegate: delegate)
        }
    }
}

/// AVFoundation serializes the callbacks for this single capture request.
nonisolated private final class RAWPhotoCapture: NSObject, AVCapturePhotoCaptureDelegate {
    private let inbox: CameraInbox
    private let continuation: CheckedContinuation<URL, Error>
    private var result: Result<URL, Error>?
    init(inbox: CameraInbox, continuation: CheckedContinuation<URL, Error>) {
        self.inbox = inbox
        self.continuation = continuation
    }
    func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?
    ) {
        if let error {
            result = .failure(error)
            return
        }
        guard photo.isRawPhoto, let data = photo.fileDataRepresentation() else {
            result = .failure(CameraFailure.noData)
            return
        }
        // Default file representation preserves full lossless ProRAW quality.
        result = Result { try inbox.store(data) }
    }
    func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(with: result ?? .failure(CameraFailure.noData))
        }
    }
}
