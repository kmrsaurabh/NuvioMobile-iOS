import AVFoundation
import AVKit
import CoreMedia
import CoreVideo
import Foundation
import UIKit

protocol MPVPictureInPicturePlaybackController: AnyObject {
    var isPlaying: Bool { get }
    var durationMs: Int64 { get }
    func play()
    func pause()
    func seek(byMs offsetMs: Int64)
}

protocol MPVPictureInPictureControllerDelegate: AnyObject {
    func pictureInPictureDidChangeActiveState(active: Bool)
    func pictureInPictureDidRequestExitPlayback()
}

final class MPVPictureInPictureController: NSObject {

    // MARK: - Public

    weak var delegate: MPVPictureInPictureControllerDelegate?
    weak var playbackController: MPVPictureInPicturePlaybackController?

    var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    private(set) var isStarting: Bool = false
    private(set) var isActive: Bool = false {
        didSet {
            guard oldValue != isActive else { return }
            delegate?.pictureInPictureDidChangeActiveState(active: isActive)
        }
    }

    var isStartingOrActive: Bool {
        isStarting || isActive
    }

    let displayLayer: AVSampleBufferDisplayLayer

    // MARK: - Private

    private var pictureInPictureController: AVPictureInPictureController?
    private var hostView: UIView?
    private let renderQueue = DispatchQueue(label: "nuvio.pip.render", qos: .userInteractive)
    
    private var isRecoveringDisplayLayer = false
    private var lastEnqueuedPresentationSeconds: Double = 0
    private var lastPlaybackPositionSeconds: Double = 0
    private var timebase: CMTimebase?
    private let stateLock = NSLock()
    private var pipFormatDescription: CMVideoFormatDescription?
    
    // Lifecycle tracking
    private var isStoppingPiPForForegroundTransition = false
    private var isRestoringPiPUserInterface = false
    private var didRestorePiPUserInterface = false
    private var didRequestForegroundTransitionStop = false

    override init() {
        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.black.cgColor
        self.displayLayer = layer
        super.init()
        createTimebaseIfNeeded()
    }

    func attach(toHostView host: UIView) {
        guard hostView !== host else { return }
        detachFromHost()
        hostView = host
        displayLayer.frame = host.bounds
        host.layer.insertSublayer(displayLayer, at: 0)

        if AVPictureInPictureController.isPictureInPictureSupported() {
            let controller = AVPictureInPictureController(
                contentSource: AVPictureInPictureController.ContentSource(
                    sampleBufferDisplayLayer: displayLayer,
                    playbackDelegate: self
                )
            )
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            controller.delegate = self
            pictureInPictureController = controller
        }
    }

    func detachFromHost() {
        pictureInPictureController?.delegate = nil
        pictureInPictureController = nil
        displayLayer.removeFromSuperlayer()
        hostView = nil
        isStarting = false
        isActive = false
    }

    func shutdownSynchronously() {
        pictureInPictureController?.delegate = nil
        pictureInPictureController = nil
        displayLayer.flushAndRemoveImage()
        displayLayer.removeFromSuperlayer()
        hostView = nil
        isStarting = false
        isActive = false
    }

    func updateLayout() {
        guard let host = hostView else { return }
        displayLayer.frame = host.bounds
    }

    func startPictureInPicture() {
        guard let controller = pictureInPictureController else { return }
        guard !controller.isPictureInPictureActive else { return }
        DispatchQueue.main.async {
            controller.startPictureInPicture()
        }
    }

    func stopPictureInPicture() {
        DispatchQueue.main.async { [weak self] in
            self?.pictureInPictureController?.stopPictureInPicture()
        }
    }

    func invalidatePlaybackState() {
        DispatchQueue.main.async { [weak self] in
            self?.pictureInPictureController?.invalidatePlaybackState()
        }
    }

    func beginForegroundTransition() {
        isStoppingPiPForForegroundTransition = true
        stopPictureInPicture()
    }

    // MARK: - Frame Enqueueing

    func enqueue(frame pixelBuffer: CVPixelBuffer, mediaTime: CMTime) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.enqueue(frame: pixelBuffer, mediaTime: mediaTime)
            }
            return
        }

        recoverDisplayLayerIfNeeded()
        guard displayLayer.status != .failed else { return }

        stateLock.lock()
        if pipFormatDescription == nil {
            var formatDescription: CMVideoFormatDescription?
            guard CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &formatDescription
            ) == noErr, let formatDescription else {
                stateLock.unlock()
                return
            }
            pipFormatDescription = formatDescription
        }
        let formatDescription = pipFormatDescription
        stateLock.unlock()
        guard let formatDescription else { return }

        let rawSeconds = max(CMTimeGetSeconds(mediaTime), 0.0)
        let jumpedBackward = rawSeconds + 0.5 < lastPlaybackPositionSeconds
        let jumpedForward = rawSeconds - lastPlaybackPositionSeconds > 5.0
        if jumpedBackward || jumpedForward {
            displayLayer.flushAndRemoveImage()
            lastEnqueuedPresentationSeconds = rawSeconds
        }
        lastPlaybackPositionSeconds = rawSeconds

        let presentationSeconds = max(rawSeconds, lastEnqueuedPresentationSeconds + 0.01)
        lastEnqueuedPresentationSeconds = presentationSeconds

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(seconds: presentationSeconds, preferredTimescale: 600),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else { return }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0,
           let attachment = CFArrayGetValueAtIndex(attachments, 0) {
            let dictionary = unsafeBitCast(attachment, to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }

        displayLayer.enqueue(sampleBuffer)
        if displayLayer.status == .failed {
            recoverDisplayLayerIfNeeded()
        }
    }

    private func recoverDisplayLayerIfNeeded() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.recoverDisplayLayerIfNeeded()
            }
            return
        }
        guard displayLayer.status == .failed else { return }
        guard !isRecoveringDisplayLayer else { return }

        isRecoveringDisplayLayer = true
        displayLayer.flushAndRemoveImage()
        displayLayer.controlTimebase = nil
        timebase = nil
        lastEnqueuedPresentationSeconds = 0
        lastPlaybackPositionSeconds = 0
        createTimebaseIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.isRecoveringDisplayLayer = false
        }
    }

    func flushPipLayer() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastEnqueuedPresentationSeconds = 0
            self.lastPlaybackPositionSeconds = 0
            self.displayLayer.flushAndRemoveImage()
        }
    }

    private func createTimebaseIfNeeded() {
        guard timebase == nil else { return }
        var tb: CMTimebase?
        let result = CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &tb
        )
        guard result == noErr, let tb else { return }
        timebase = tb
        displayLayer.controlTimebase = tb
        CMTimebaseSetRate(tb, rate: 0.0)
        CMTimebaseSetTime(tb, time: .zero)
    }

    func setPlaybackRate(_ rate: Double) {
        createTimebaseIfNeeded()
        guard let timebase else { return }
        CMTimebaseSetRate(timebase, rate: rate)
    }

    func notifyPipFormatChanged() {
        stateLock.lock()
        pipFormatDescription = nil
        stateLock.unlock()
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension MPVPictureInPictureController: AVPictureInPictureControllerDelegate {

    func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        isStarting = true
        isActive = true
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        isStarting = false
        isActive = true
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print("[NuvioPiP] failed to start: \(error.localizedDescription)")
        isStarting = false
        isActive = false
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ controller: AVPictureInPictureController) {
        guard isStoppingPiPForForegroundTransition else { return }
        // Handle foreground transition UI setup if necessary
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        isStarting = false
        isActive = false
        
        let shouldRequestExitPlayback = !didRequestForegroundTransitionStop
        if isStoppingPiPForForegroundTransition {
            isStoppingPiPForForegroundTransition = false
            didRestorePiPUserInterface = false
            didRequestForegroundTransitionStop = false
        }
        
        if shouldRequestExitPlayback {
            delegate?.pictureInPictureDidRequestExitPlayback()
        }
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        
        isRestoringPiPUserInterface = true
        didRestorePiPUserInterface = true
        
        DispatchQueue.main.async {
            completionHandler(true)
        }
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension MPVPictureInPictureController: AVPictureInPictureSampleBufferPlaybackDelegate {

    func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        DispatchQueue.main.async { [weak self] in
            if playing {
                self?.playbackController?.play()
            } else {
                self?.playbackController?.pause()
            }
        }
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        let start = CMTime(seconds: 0, preferredTimescale: 600)
        let durationMs = playbackController?.durationMs ?? 0
        guard durationMs > 0 else {
            return CMTimeRange(start: start, duration: .positiveInfinity)
        }
        let duration = CMTime(seconds: Double(durationMs) / 1000.0, preferredTimescale: 600)
        return CMTimeRange(start: start, duration: duration)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        return !(playbackController?.isPlaying ?? false)
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            let offsetMs = Int64(CMTimeGetSeconds(skipInterval) * 1000.0)
            self?.playbackController?.seek(byMs: offsetMs)
            DispatchQueue.main.async {
                completionHandler()
            }
        }
    }
    
    func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        return false
    }
}
