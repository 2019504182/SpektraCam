import Foundation
import Observation
import UIKit

@MainActor @Observable final class CameraModel {
    enum State: Equatable {
        case starting, ready, paused, denied, unavailable
        case failed(String)
    }
    private(set) var state = State.starting
    private(set) var source: CameraPreviewSource?
    private(set) var formats: [CameraFormat] = []
    var format = CameraFormat.proRAW
    private(set) var busy = false
    private(set) var outputReady = false
    private(set) var savedCount = 0
    private(set) var saveFailure: String?
    private(set) var pendingCount = 0
    private let service = CameraService()
    let library: PhotoLibrary
    private(set) var readings = CameraReadings()
    private(set) var lenses: [CameraLens] = []
    private(set) var selectedLens: CameraLens?
    private(set) var macro = false
    private(set) var highResolution = false
    private(set) var maximumMegapixels = 12
    private(set) var pauseReason: String?
    private(set) var exposureBias = 0.0
    private(set) var exposureRange: ClosedRange<Double> = -3...3
    private let location = CameraLocation()
    private var beforeMacro: String?
    private var backLens: String?
    private var wantsActive = false
    private var starting = false
    private var closed = false
    @ObservationIgnored private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    init(library: PhotoLibrary) { self.library = library }
    var canCapture: Bool { state == .ready && outputReady && !busy && pendingCount == 0 }
    func setActive(_ active: Bool) async {
        guard !closed else { return }
        wantsActive = active
        if !active {
            location.setActive(false)
            state = .paused
            await service.stop()
            return
        }
        guard !starting else { return }
        starting = true
        defer { starting = false }
        state = .starting
        do {
            let configuration = try await service.start()
            apply(configuration)
            if wantsActive {
                state = .ready
                pauseReason = nil
                location.setActive(true)
            } else {
                await service.stop()
            }
        } catch {
            guard wantsActive else {
                state = .paused
                return
            }
            switch error {
            case CameraFailure.denied: state = .denied
            case CameraFailure.unavailable: state = .unavailable
            default: state = .failed(error.localizedDescription)
            }
        }
    }
    func monitor() async {
        for await event in service.events {
            guard !Task.isCancelled else { return }
            switch event {
            case .readings(let value): readings = value
            case .ready(let ready): outputReady = ready
            case .interrupted(let reason):
                pauseReason = reason
                if wantsActive { state = .paused }
            case .resumed: if wantsActive { await setActive(true) }
            case .failed(let message): if wantsActive { state = .failed(message) }
            }
        }
    }
    func takePhoto() async {
        guard canCapture else { return }
        busy = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        beginCaptureTask()
        defer {
            busy = false
            endCaptureTask()
        }
        do {
            _ = try await service.takePhoto(
                format: format, rotation: source?.captureRotation ?? 90,
                inbox: CameraInbox(root: library.files.root), location: location.captureLocation)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            savedCount += try await library.recoverCaptures()
            saveFailure = nil
        } catch { saveFailure = error.localizedDescription }
        pendingCount = (try? await library.files.pendingCaptures().count) ?? 0
    }
    func retryImport() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            savedCount += try await library.recoverCaptures()
            saveFailure = nil
        } catch { saveFailure = error.localizedDescription }
        pendingCount = (try? await library.files.pendingCaptures().count) ?? 0
    }
    private func apply(_ configuration: CameraService.Configuration) {
        source = configuration.source
        formats = configuration.formats
        lenses = configuration.lenses
        selectedLens = configuration.selectedLens
        macro = configuration.macro
        highResolution = configuration.highResolution
        maximumMegapixels = configuration.maximumMegapixels
        exposureBias = configuration.exposureBias
        exposureRange = configuration.exposureRange
        if !formats.contains(format), let first = formats.first { format = first }
    }
    func selectLens(_ lens: CameraLens, macro: Bool = false) async {
        guard !busy, state == .ready else { return }
        busy = true
        defer { busy = false }
        do {
            apply(try await service.selectLens(lens.id, macro: macro))
            saveFailure = nil
            UISelectionFeedbackGenerator().selectionChanged()
        } catch { saveFailure = error.localizedDescription }
    }
    func setHighResolution(_ enabled: Bool) async {
        guard !busy, state == .ready else { return }
        busy = true
        defer { busy = false }
        do { apply(try await service.setHighResolution(enabled)) } catch {
            saveFailure = error.localizedDescription
        }
    }
    func focus(at point: CGPoint) async {
        guard state == .ready, !busy else { return }
        do {
            try await service.focus(at: point)
            UISelectionFeedbackGenerator().selectionChanged()
        } catch { saveFailure = error.localizedDescription }
    }
    func setExposureBias(_ value: Double) {
        guard state == .ready, !busy else { return }
        exposureBias = min(max(value, exposureRange.lowerBound), exposureRange.upperBound)
        let target = exposureBias
        Task {
            do { try await service.setExposureBias(target) } catch {
                saveFailure = error.localizedDescription
            }
        }
    }
    func toggleMacro() async {
        if macro {
            if let lens = lenses.first(where: { $0.id == beforeMacro }) { await selectLens(lens) }
        } else if let lens = lenses.first(where: \.macro) {
            beforeMacro = selectedLens?.id
            await selectLens(lens, macro: true)
        }
    }
    func flip() async {
        if selectedLens?.front == true {
            if let lens = lenses.first(where: { $0.id == backLens })
                ?? lenses.first(where: { !$0.front && $0.primary })
            {
                await selectLens(lens)
            }
        } else if let lens = lenses.first(where: \.front) {
            backLens = selectedLens?.id
            await selectLens(lens)
        }
    }
    private func beginCaptureTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save RAW Photo") { [weak self] in
            Task { @MainActor in self?.endCaptureTask() }
        }
    }
    private func endCaptureTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
    func close() async {
        closed = true
        wantsActive = false
        location.setActive(false)
        await service.shutdown()
    }
}
