import Foundation
import AVFoundation
import AVKit
import CoreMedia
import CoreVideo
import UIKit
import Libmpv
import ComposeApp

// MARK: - Player Bridge Implementation (Kotlin protocol conformance)

final class MPVPlayerBridgeImpl: NSObject, NuvioPlayerBridge {

    private var playerVC: MPVPlayerViewController?

    func createPlayerViewController() -> UIViewController {
        let vc = MPVPlayerViewController()
        self.playerVC = vc
        return vc
    }

    func loadFile(url: String) { playerVC?.loadFile(url) }
    func loadFileWithAudio(videoUrl: String, audioUrl: String?, headersJson: String?) {
        playerVC?.loadFile(
            videoUrl,
            audioUrl: audioUrl,
            requestHeaders: parseRequestHeaders(headersJson)
        )
    }
    func play() { playerVC?.playPlayback() }
    func pause() { playerVC?.pausePlayback() }
    func seekTo(positionMs: Int64) { playerVC?.seekToMs(positionMs) }
    func seekBy(offsetMs: Int64) { playerVC?.seekByMs(offsetMs) }
    func retry() { playerVC?.retryPlayback() }
    func configureVideoOutput(
        hardwareDecoder: String,
        targetColorspaceHint: Bool,
        toneMapping: String,
        hdrComputePeak: Bool,
        targetPrimaries: String,
        targetTransfer: String,
        extendedDynamicRange: Bool,
        deband: Bool,
        interpolation: Bool,
        brightness: Int32,
        contrast: Int32,
        saturation: Int32,
        gamma: Int32
    ) {
        playerVC?.configureVideoOutput(
            hardwareDecoder: hardwareDecoder,
            targetColorspaceHint: targetColorspaceHint,
            toneMapping: toneMapping,
            hdrComputePeak: hdrComputePeak,
            targetPrimaries: targetPrimaries,
            targetTransfer: targetTransfer,
            extendedDynamicRange: extendedDynamicRange,
            deband: deband,
            interpolation: interpolation,
            brightness: Int(brightness),
            contrast: Int(contrast),
            saturation: Int(saturation),
            gamma: Int(gamma)
        )
    }
    func configureAudioOutput(audioOutput: String) {
        playerVC?.configureAudioOutput(audioOutput: audioOutput)
    }
    func setPlaybackSpeed(speed: Float) { playerVC?.setSpeed(speed) }
    func getVolume() -> Float { playerVC?.getVolume() ?? 1.0 }
    func setVolume(volume: Float) { playerVC?.setVolume(volume) }
    func setMuted(muted: Bool) { playerVC?.setMuted(muted) }
    func setResizeMode(mode: Int32) { playerVC?.setResize(Int(mode)) }

    // Audio tracks
    func getAudioTrackCount() -> Int32 { Int32(playerVC?.audioTracks.count ?? 0) }
    func getAudioTrackIndex(at: Int32) -> Int32 {
        guard let t = playerVC?.audioTracks, Int(at) < t.count else { return 0 }
        return Int32(t[Int(at)].index)
    }
    func getAudioTrackId(at: Int32) -> String {
        guard let t = playerVC?.audioTracks, Int(at) < t.count else { return "0" }
        return "\(t[Int(at)].id)"
    }
    func getAudioTrackLabel(at: Int32) -> String {
        guard let t = playerVC?.audioTracks, Int(at) < t.count else { return "" }
        return t[Int(at)].title
    }
    func getAudioTrackLang(at: Int32) -> String {
        guard let t = playerVC?.audioTracks, Int(at) < t.count else { return "" }
        return t[Int(at)].lang
    }
    func isAudioTrackSelected(at: Int32) -> Bool {
        guard let t = playerVC?.audioTracks, Int(at) < t.count else { return false }
        return t[Int(at)].selected
    }

    // Subtitle tracks
    func getSubtitleTrackCount() -> Int32 { Int32(playerVC?.subtitleTracks.count ?? 0) }
    func getSubtitleTrackIndex(at: Int32) -> Int32 {
        guard let t = playerVC?.subtitleTracks, Int(at) < t.count else { return 0 }
        return Int32(t[Int(at)].index)
    }
    func getSubtitleTrackId(at: Int32) -> String {
        guard let t = playerVC?.subtitleTracks, Int(at) < t.count else { return "0" }
        return "\(t[Int(at)].id)"
    }
    func getSubtitleTrackLabel(at: Int32) -> String {
        guard let t = playerVC?.subtitleTracks, Int(at) < t.count else { return "" }
        return t[Int(at)].title
    }
    func getSubtitleTrackLang(at: Int32) -> String {
        guard let t = playerVC?.subtitleTracks, Int(at) < t.count else { return "" }
        return t[Int(at)].lang
    }
    func isSubtitleTrackSelected(at: Int32) -> Bool {
        guard let t = playerVC?.subtitleTracks, Int(at) < t.count else { return false }
        return t[Int(at)].selected
    }

    func selectAudioTrack(trackId: Int32) { playerVC?.selectAudio(Int(trackId)) }
    func selectSubtitleTrack(trackId: Int32) { playerVC?.selectSubtitle(Int(trackId)) }
    func setSubtitleUrl(url: String) { playerVC?.addSubtitleUrl(url) }
    func clearExternalSubtitle() { playerVC?.removeExternalSubtitles() }
    func clearExternalSubtitleAndSelect(trackId: Int32) { playerVC?.removeExternalSubtitlesAndSelect(Int(trackId)) }
    func setSubtitleDelayMs(delayMs: Int32) { playerVC?.setSubtitleDelayMs(Int(delayMs)) }
    func applySubtitleStyle(
        textColor: String,
        backgroundColor: String,
        outlineColor: String,
        outlineSize: Float,
        bold: Bool,
        fontSize: Float,
        subPos: Int32
    ) {
        playerVC?.applySubtitleStyle(
            textColor: textColor,
            backgroundColor: backgroundColor,
            outlineColor: outlineColor,
            outlineSize: outlineSize,
            bold: bold,
            fontSize: fontSize,
            subPos: Int(subPos)
        )
    }

    // State - refreshes position from mpv on each call (polled from Kotlin every 250ms)
    func pollPlaybackState() { playerVC?.refreshPlaybackState() }
    func getIsLoading() -> Bool { playerVC?.refreshPlaybackState(); return playerVC?.isPlayerLoading ?? true }
    func getIsPlaying() -> Bool { return playerVC?.isPlayerPlaying ?? false }
    func getIsEnded() -> Bool { return playerVC?.isPlayerEnded ?? false }
    func getDurationMs() -> Int64 { return playerVC?.durationMs ?? 0 }
    func getPositionMs() -> Int64 { return playerVC?.positionMs ?? 0 }
    func getBufferedMs() -> Int64 { return playerVC?.bufferedMs ?? 0 }
    func getPlaybackSpeed() -> Float { playerVC?.currentSpeed ?? 1.0 }
    func getErrorMessage() -> String { playerVC?.currentErrorMessage ?? "" }
    func updateNowPlayingMetadata(title: String, subtitle: String?, artworkUrl: String?) {
        playerVC?.updateNowPlayingMetadata(title: title, subtitle: subtitle, artworkUrl: artworkUrl)
    }
    func clearNowPlayingInfo() {
        playerVC?.clearNowPlayingInfo()
    }

    func destroy() {
        playerVC?.destroyPlayer()
        playerVC = nil
    }

    private func parseRequestHeaders(_ headersJson: String?) -> [String: String] {
        guard
            let headersJson,
            !headersJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let data = headersJson.data(using: .utf8),
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }

        var headers: [String: String] = [:]
        headers.reserveCapacity(raw.count)
        raw.forEach { key, value in
            guard let headerValue = value as? String else { return }
            headers[key] = headerValue
        }
        return headers
    }
}

// MARK: - Track Info

struct TrackInfo {
    let index: Int
    let id: Int
    let type: String
    let title: String
    let lang: String
    let selected: Bool
}

private struct PendingLoadRequest {
    let urlString: String
    let audioUrl: String?
    let requestHeaders: [String: String]
    let queuedAtUptime: TimeInterval
}

// MARK: - MPV Player View Controller

final class MPVPlayerViewController: UIViewController, AVPictureInPictureSampleBufferPlaybackDelegate, AVPictureInPictureControllerDelegate {

    private static let defaultAudioOutput = "avfoundation,audiounit,"

    private let errorStateLock = NSLock()
    private let pipDisplayLayer = AVSampleBufferDisplayLayer()
    private var pipController: AVPictureInPictureController?
    private var timebase: CMTimebase?
    private var mpvRenderContext: OpaquePointer?
    private var pendingLoadRequest: PendingLoadRequest?
    private var pendingLoadRetryWorkItem: DispatchWorkItem?
    internal var mpv: OpaquePointer?
    private lazy var eventQueue = DispatchQueue(label: "mpv-events", qos: .userInitiated)
    private lazy var renderQueue = DispatchQueue(label: "mpv-render", qos: .userInitiated)
    private var recentPlaybackLogs: [String] = []
    private var activeRequestHeaders: [String: String] = [:]
    private var isAudioSessionConfigured = false
    private var needsAudioSessionActivationOnPlayback = false
    private let stateLock = NSLock()
    private var isDestroying = false
    private var isRecoveringDisplayLayer = false
    private var lastEnqueuedPresentationSeconds: Double = 0
    private var lastPlaybackPositionSeconds: Double = 0
    private var renderInProgress = false
    private var renderNeedsAnotherPass = false
    private var renderSize: CGSize = .zero
    private var pixelBufferPool: CVPixelBufferPool?
    private var pipFormatDescription: CMVideoFormatDescription?
    private let pipTransitionOverlay = UIView()

    // Cached track lists
    var audioTracks: [TrackInfo] = []
    var subtitleTracks: [TrackInfo] = []

    // State (polled from Kotlin every 250ms)
    var isPlayerLoading: Bool = true
    var isPlayerPlaying: Bool = false
    var isPlayerEnded: Bool = false
    var durationMs: Int64 = 0
    var positionMs: Int64 = 0
    var bufferedMs: Int64 = 0
    var currentSpeed: Float = 1.0
    var currentErrorMessage: String {
        errorStateLock.lock()
        defer { errorStateLock.unlock() }
        return _currentErrorMessage ?? ""
    }
    private var _currentErrorMessage: String?

    override var prefersHomeIndicatorAutoHidden: Bool {
        true
    }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        [.bottom, .left, .right]
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    private var isPiPEnabled: Bool {
#if targetEnvironment(simulator)
        return false
#else
        return true
#endif
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.layer.masksToBounds = true
        configurePipLayer()
        setupMpv()
        setupPictureInPicture()
        setupNotifications()
        refreshImmersiveSystemUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshImmersiveSystemUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPipLayer()
        attemptStartPendingLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshImmersiveSystemUI()
        becomeFirstResponder()
        UIApplication.shared.beginReceivingRemoteControlEvents()
        attemptStartPendingLoad()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        layoutPipLayer()
        refreshImmersiveSystemUI()
        attemptStartPendingLoad()
    }

    private func configurePipLayer() {
        pipDisplayLayer.backgroundColor = UIColor.black.cgColor
        pipDisplayLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(pipDisplayLayer)
        pipTransitionOverlay.backgroundColor = .black
        pipTransitionOverlay.alpha = 0.0
        pipTransitionOverlay.isUserInteractionEnabled = false
        view.addSubview(pipTransitionOverlay)
        layoutPipLayer()

        if isPiPEnabled, AVPictureInPictureController.isPictureInPictureSupported() {
            let source = AVPictureInPictureController.ContentSource(
                sampleBufferDisplayLayer: pipDisplayLayer,
                playbackDelegate: self
            )
            pipController = AVPictureInPictureController(contentSource: source)
            pipController?.delegate = self
            pipController?.canStartPictureInPictureAutomaticallyFromInline = true
            observePictureInPictureAvailability()
        }

        createTimebaseIfNeeded()
    }

    private func observePictureInPictureAvailability() {
        pipPossibleObservation?.invalidate()
        pipPossibleObservation = pipController?.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.startPictureInPictureIfPossible()
            }
        }
    }

    private func layoutPipLayer() {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }

        let scale = view.window?.screen.nativeScale ?? UIScreen.main.nativeScale
        let targetSize = CGSize(
            width: (bounds.width * scale).rounded(.toNearestOrAwayFromZero),
            height: (bounds.height * scale).rounded(.toNearestOrAwayFromZero)
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pipDisplayLayer.contentsScale = scale
        pipDisplayLayer.frame = CGRect(origin: .zero, size: bounds.size)
        CATransaction.commit()
        pipTransitionOverlay.frame = CGRect(origin: .zero, size: bounds.size)

        if renderSize != targetSize {
            renderSize = targetSize
            pixelBufferPool = makePixelBufferPool(width: Int(targetSize.width), height: Int(targetSize.height))
            stateLock.lock()
            pipFormatDescription = nil
            stateLock.unlock()
            flushPipLayer()
            scheduleRender()
        }
    }

    // MARK: - MPV Setup

    private func setupMpv() {
        mpv = mpv_create()
        guard mpv != nil else {
            return
        }

        checkError(mpv_request_log_messages(mpv, "warn"))
        checkError(mpv_set_option_string(mpv, "vo", "libmpv"))
        checkError(mpv_set_option_string(mpv, "hwdec", "videotoolbox"))
        checkError(mpv_set_option_string(mpv, "ao", Self.defaultAudioOutput))
        checkError(mpv_set_option_string(mpv, "audio-channels", "auto"))
        checkError(mpv_set_option_string(mpv, "audio-fallback-to-null", "yes"))
        checkError(mpv_set_option_string(mpv, "video-rotate", "no"))
        checkError(mpv_set_option_string(mpv, "subs-match-os-language", "yes"))
        checkError(mpv_set_option_string(mpv, "subs-fallback", "yes"))
        checkError(mpv_set_option_string(mpv, "keep-open", "yes"))
        checkError(mpv_set_option_string(mpv, "target-colorspace-hint", "yes"))
        checkError(mpv_set_option_string(mpv, "tone-mapping", "auto"))
        checkError(mpv_set_option_string(mpv, "hdr-compute-peak", "yes"))
        
        // Caching: RAM cache sized for mobile (iOS devices typically have 3-6GB).
        // Keep it moderate to avoid memory pressure + OOM kills in background.
        checkError(mpv_set_option_string(mpv, "cache", "yes"))
        checkError(mpv_set_option_string(mpv, "demuxer-max-bytes", "50000000"))      // 50MB forward buffer
        checkError(mpv_set_option_string(mpv, "demuxer-max-back-bytes", "30000000")) // 30MB backward buffer
        checkError(mpv_set_option_string(mpv, "network-timeout", "300"))             // Wait 5 minutes for metadata on rare torrents

        checkError(mpv_initialize(mpv))

        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "core-idle", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "eof-reached", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "seeking", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "track-list/count", MPV_FORMAT_INT64)

        mpv_set_wakeup_callback(mpv, { ctx in
            let vc = unsafeBitCast(ctx, to: MPVPlayerViewController.self)
            vc.readEvents()
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))

        setupRenderContext()
    }

    private func setupRenderContext() {
        guard let mpv else { return }
        let api = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_SW as NSString).utf8String)
        var advancedControl: CInt = 1
        var didCreateContext = false

        withUnsafeMutablePointer(to: &advancedControl) { advancedControlPtr in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: api),
                mpv_render_param(type: MPV_RENDER_PARAM_ADVANCED_CONTROL, data: advancedControlPtr),
                mpv_render_param()
            ]
            if mpv_render_context_create(&mpvRenderContext, mpv, &params) < 0 {
                return
            }
            didCreateContext = true
        }

        guard didCreateContext, mpvRenderContext != nil else { return }

        mpv_render_context_set_update_callback(
            mpvRenderContext,
            { ctx in
                let controller = Unmanaged<MPVPlayerViewController>.fromOpaque(ctx!).takeUnretainedValue()
                controller.scheduleRender()
            },
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
    }

    private func scheduleRender() {
        guard !isDestroying else { return }
        guard mpvRenderContext != nil, renderSize.width > 1, renderSize.height > 1 else { return }

        stateLock.lock()
        renderNeedsAnotherPass = true
        guard !renderInProgress else {
            stateLock.unlock()
            return
        }
        renderInProgress = true
        renderNeedsAnotherPass = false
        stateLock.unlock()

        renderQueue.async { [weak self] in
            self?.performRender()
        }
    }

    private func performRender() {
        guard !isDestroying else { return }
        defer {
            let shouldContinue: Bool
            stateLock.lock()
            shouldContinue = renderNeedsAnotherPass
            renderNeedsAnotherPass = false
            renderInProgress = false
            stateLock.unlock()
            if shouldContinue {
                scheduleRender()
            }
        }

        guard !isDestroying else { return }
        guard let ctx = mpvRenderContext else { return }
        let updateFlags = mpv_render_context_update(ctx)
        guard updateFlags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0 else { return }
        guard let pixelBuffer = makeRenderPixelBuffer() else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var size = [Int32(Int(renderSize.width)), Int32(Int(renderSize.height))]
        var stride = bytesPerRow
        var blockForTargetTime: CInt = 0
        let format = UnsafeMutableRawPointer(mutating: ("bgr0" as NSString).utf8String)

        size.withUnsafeMutableBufferPointer { sizePtr in
            withUnsafeMutablePointer(to: &stride) { stridePtr in
                withUnsafeMutablePointer(to: &blockForTargetTime) { blockPtr in
                    var params = [
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: sizePtr.baseAddress),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: format),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: stridePtr),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: baseAddress),
                        mpv_render_param(type: MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, data: blockPtr),
                        mpv_render_param()
                    ]
                    _ = mpv_render_context_render(ctx, &params)
                }
            }
        }

        let mediaTime = currentPresentationTime()
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isDestroying else { return }
            self.enqueue(frame: pixelBuffer, mediaTime: mediaTime)
        }
    }

    private func makeRenderPixelBuffer() -> CVPixelBuffer? {
        guard renderSize.width > 1, renderSize.height > 1 else { return nil }
        if let pool = pixelBufferPool {
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
            if status == kCVReturnSuccess, let pixelBuffer {
                return pixelBuffer
            }
        }

        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(renderSize.width),
            Int(renderSize.height),
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else { return nil }
        return pixelBuffer
    }

    private func makePixelBufferPool(width: Int, height: Int) -> CVPixelBufferPool? {
        let poolAttributes: [CFString: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey: 3
        ]
        let pixelAttributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height
        ]

        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            pixelAttributes as CFDictionary,
            &pool
        )
        guard status == kCVReturnSuccess else { return nil }
        return pool
    }

    private func enqueue(frame pixelBuffer: CVPixelBuffer, mediaTime: CMTime) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.enqueue(frame: pixelBuffer, mediaTime: mediaTime)
            }
            return
        }
        guard !isDestroying else { return }

        recoverDisplayLayerIfNeeded()
        guard pipDisplayLayer.status != .failed else { return }

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
            pipDisplayLayer.flushAndRemoveImage()
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

        pipDisplayLayer.enqueue(sampleBuffer)
        if pipDisplayLayer.status == .failed {
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
        guard pipDisplayLayer.status == .failed else { return }
        guard !isRecoveringDisplayLayer else { return }

        isRecoveringDisplayLayer = true
        pipDisplayLayer.flushAndRemoveImage()
        pipDisplayLayer.controlTimebase = nil
        timebase = nil
        lastEnqueuedPresentationSeconds = 0
        lastPlaybackPositionSeconds = 0
        createTimebaseIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.isRecoveringDisplayLayer = false
        }
    }

    private func flushPipLayer() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastEnqueuedPresentationSeconds = 0
            self.lastPlaybackPositionSeconds = 0
            self.pipDisplayLayer.flushAndRemoveImage()
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
        pipDisplayLayer.controlTimebase = tb
        CMTimebaseSetRate(tb, rate: 0.0)
        CMTimebaseSetTime(tb, time: .zero)
    }

    private func setTimebaseTime(seconds: Double) {
        createTimebaseIfNeeded()
        guard let timebase else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        CMTimebaseSetRate(timebase, rate: 0.0)
        CMTimebaseSetTime(timebase, time: time)
    }

    private func setPlaybackRate(_ rate: Double) {
        createTimebaseIfNeeded()
        guard let timebase else { return }
        CMTimebaseSetRate(timebase, rate: rate)
    }

    private func currentPresentationTime() -> CMTime {
        CMTime(seconds: Double(positionMs) / 1000.0, preferredTimescale: 600)
    }

    private func invalidatePipPlaybackState() {
        guard isPiPEnabled else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pipController?.invalidatePlaybackState()
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(willResignActive),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func enterBackground() {
        guard mpv != nil else { return }
        if isPictureInPictureActive { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self, self.mpv != nil else { return }
            if self.isPictureInPictureActive { return }
            self.pausePlayback()
            self.setStringProperty("vid", "no")
        }
    }

    @objc private func enterForeground() {
        guard mpv != nil else { return }
        if isPictureInPictureActive { return }
        setStringProperty("vid", "auto")
        playPlayback()
    }

    // MARK: - Playback API

    func loadFile(_ urlString: String, audioUrl: String? = nil, requestHeaders: [String: String] = [:]) {
        let request = PendingLoadRequest(
            urlString: urlString,
            audioUrl: audioUrl,
            requestHeaders: requestHeaders,
            queuedAtUptime: ProcessInfo.processInfo.systemUptime
        )

        if Thread.isMainThread {
            queueLoad(request)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.queueLoad(request)
            }
        }
    }

    private func queueLoad(_ request: PendingLoadRequest) {
        pendingLoadRequest = request
        attemptStartPendingLoad()
    }

    private func attemptStartPendingLoad() {
        guard let request = pendingLoadRequest else { return }
        guard mpv != nil else { return }
        guard isViewLoaded, view.window != nil else {
            schedulePendingLoadRetry()
            return
        }
        guard view.bounds.width > 1, view.bounds.height > 1 else {
            schedulePendingLoadRetry()
            return
        }

        pendingLoadRequest = nil
        pendingLoadRetryWorkItem?.cancel()
        pendingLoadRetryWorkItem = nil
        startLoad(request)
    }

    private func startLoad(_ request: PendingLoadRequest) {
        guard mpv != nil else { return }
        needsAudioSessionActivationOnPlayback = true
        configureAudioSession()
        clearPlaybackError()
        let sanitizedHeaders = sanitizeRequestHeaders(request.requestHeaders)
        activeRequestHeaders = sanitizedHeaders
        applyRequestHeaders(sanitizedHeaders)
        isPlayerLoading = true
        isPlayerEnded = false
        isPlayerPlaying = false
        setTimebaseTime(seconds: 0)
        flushPipLayer()
        command("loadfile", args: [request.urlString, "replace"])
        if let audioUrl = request.audioUrl, !audioUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.command("audio-add", args: [audioUrl, "select"], checkForErrors: false)
            }
        }
        scheduleRender()
    }

    private func isViewportReadyForPlayback(queuedAtUptime: TimeInterval) -> Bool {
        guard isViewLoaded, view.window != nil else { return false }
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return false }
        if bounds.width >= bounds.height { return true }

        let age = ProcessInfo.processInfo.systemUptime - queuedAtUptime
        return age >= 0.9
    }

    private func schedulePendingLoadRetry() {
        guard pendingLoadRetryWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.pendingLoadRetryWorkItem = nil
            self?.attemptStartPendingLoad()
        }
        pendingLoadRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    func playPlayback() {
        guard mpv != nil else { return }
        if pendingLoadRequest == nil && !isPlayerLoading {
            configureAudioSession()
        }
        if needsAudioSessionActivationOnPlayback, !isAudioSessionConfigured {
            configureAudioSession()
        }
        setFlag("pause", false)
        setPlaybackRate(1.0)
        scheduleRender()
        isPlayerPlaying = true
        isPlayerLoading = false
        isPlayerEnded = false
        invalidatePipPlaybackState()
    }

    func pausePlayback() {
        guard mpv != nil else { return }
        setFlag("pause", true)
        setPlaybackRate(0.0)
        isPlayerPlaying = false
        invalidatePipPlaybackState()
    }

    func seekToMs(_ ms: Int64) {
        guard mpv != nil else { return }
        let wasPlaying = isPlayerPlaying
        let seconds = Double(ms) / 1000.0
        setTimebaseTime(seconds: seconds)
        flushPipLayer()
        command("seek", args: [String(format: "%.3f", seconds), "absolute"])
        if wasPlaying {
            setFlag("pause", false)
            setPlaybackRate(1.0)
            isPlayerPlaying = true
            currentSpeed = 1.0
        }
        scheduleRender()
    }

    func seekByMs(_ ms: Int64) {
        guard mpv != nil else { return }
        let wasPlaying = isPlayerPlaying
        let seconds = Double(ms) / 1000.0
        flushPipLayer()
        command("seek", args: [String(format: "%.3f", seconds), "relative"])
        if wasPlaying {
            setFlag("pause", false)
            setPlaybackRate(1.0)
            isPlayerPlaying = true
            currentSpeed = 1.0
        }
        scheduleRender()
    }

    func retryPlayback() {
        guard mpv != nil else { return }
        if let path = getString("path") {
            clearPlaybackError()
            applyRequestHeaders(activeRequestHeaders)
            let pos = getDouble("time-pos")
            command("loadfile", args: [path, "replace"])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.command("seek", args: [String(format: "%.3f", pos), "absolute"])
            }
        }
    }

    private func configureAudioSession() {
        guard !isAudioSessionConfigured else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try session.setActive(true)
            isAudioSessionConfigured = true
            needsAudioSessionActivationOnPlayback = false
            audioSessionRetryWorkItem?.cancel()
            audioSessionRetryWorkItem = nil
        } catch {
            scheduleAudioSessionRetryIfNeeded()
            return
        }
    }

    private func scheduleAudioSessionRetryIfNeeded() {
        guard needsAudioSessionActivationOnPlayback else { return }
        guard audioSessionRetryWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.audioSessionRetryWorkItem = nil
            guard self.needsAudioSessionActivationOnPlayback, !self.isAudioSessionConfigured else { return }
            self.configureAudioSession()
        }
        audioSessionRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    func configureVideoOutput(
        hardwareDecoder: String,
        targetColorspaceHint: Bool,
        toneMapping: String,
        hdrComputePeak: Bool,
        targetPrimaries: String,
        targetTransfer: String,
        extendedDynamicRange: Bool,
        deband: Bool,
        interpolation: Bool,
        brightness: Int,
        contrast: Int,
        saturation: Int,
        gamma: Int
    ) {
        guard mpv != nil else { return }

        setStringProperty("hwdec", hardwareDecoder)
        setStringProperty("target-colorspace-hint", targetColorspaceHint ? "yes" : "no")
        setStringProperty("tone-mapping", toneMapping)
        setStringProperty("hdr-compute-peak", hdrComputePeak ? "yes" : "no")
        setStringProperty("target-prim", targetPrimaries)
        setStringProperty("target-trc", targetTransfer)
        setStringProperty("deband", deband ? "yes" : "no")
        setStringProperty("interpolation", interpolation ? "yes" : "no")
        setVideoEqualizer("brightness", brightness)
        setVideoEqualizer("contrast", contrast)
        setVideoEqualizer("saturation", saturation)
        setVideoEqualizer("gamma", gamma)
        if #available(iOS 17.0, *) {
            pipDisplayLayer.wantsExtendedDynamicRangeContent = extendedDynamicRange
        }
    }

    func configureAudioOutput(audioOutput: String) {
        guard mpv != nil else { return }
        setStringProperty("ao", audioOutput)
    }

    func setSpeed(_ speed: Float) {
        guard mpv != nil else { return }
        var s = Double(speed)
        mpv_set_property(mpv, "speed", MPV_FORMAT_DOUBLE, &s)
    }

    func getVolume() -> Float {
        guard mpv != nil else { return 1.0 }
        let baseVolume = getDouble("volume") / 100.0
        let gainDb = getDouble("volume-gain")
        let gainMultiplier = pow(10.0, gainDb / 20.0)
        return Float(max(0.0, min(2.0, baseVolume * gainMultiplier)))
    }

    func setVolume(_ volume: Float) {
        guard mpv != nil else { return }
        let clamped = max(0.0, min(2.0, Double(volume)))

        if clamped <= 0.001 {
            var mutedVolume = 0.0
            var neutralGain = 0.0
            checkError(mpv_set_property(mpv, "volume", MPV_FORMAT_DOUBLE, &mutedVolume))
            checkError(mpv_set_property(mpv, "volume-gain", MPV_FORMAT_DOUBLE, &neutralGain))
            return
        }

        // Keep mpv's base volume at 100 and apply real software amplification through volume-gain.
        // 2.0x equals about +6.02 dB.
        var baseVolume = 100.0
        var gainDb = 20.0 * log10(clamped)
        checkError(mpv_set_property(mpv, "volume", MPV_FORMAT_DOUBLE, &baseVolume))
        checkError(mpv_set_property(mpv, "volume-gain", MPV_FORMAT_DOUBLE, &gainDb))
    }

    func setMuted(_ muted: Bool) {
        guard mpv != nil else { return }
        setFlag("mute", muted)
    }

    func setResize(_ mode: Int) {
        guard mpv != nil else { return }
        switch mode {
        case 1: // Fill
            pipDisplayLayer.videoGravity = .resizeAspectFill
            setStringProperty("panscan", "1.0")
            setStringProperty("video-unscaled", "no")
        case 2: // Zoom
            pipDisplayLayer.videoGravity = .resizeAspectFill
            setStringProperty("panscan", "1.0")
            setStringProperty("video-unscaled", "no")
        default: // Fit
            pipDisplayLayer.videoGravity = .resizeAspect
            setStringProperty("panscan", "0.0")
            setStringProperty("video-unscaled", "no")
        }
    }

    // MARK: - Track selection

    func selectAudio(_ trackId: Int) {
        guard mpv != nil else { return }
        var id = Int64(trackId)
        mpv_set_property(mpv, "aid", MPV_FORMAT_INT64, &id)
        invalidatePipPlaybackState()
    }

    func selectSubtitle(_ trackId: Int) {
        guard mpv != nil else { return }
        if trackId < 0 {
            setStringProperty("sid", "no")
        } else {
            var id = Int64(trackId)
            mpv_set_property(mpv, "sid", MPV_FORMAT_INT64, &id)
        }
        invalidatePipPlaybackState()
    }

    func addSubtitleUrl(_ url: String) {
        guard mpv != nil else { return }
        command("sub-add", args: [url, "select"])
        invalidatePipPlaybackState()
    }

    func removeExternalSubtitles() {
        guard mpv != nil else { return }
        let count = getInt("track-list/count")
        for i in stride(from: count - 1, through: 0, by: -1) {
            let type = getString("track-list/\(i)/type") ?? ""
            let external = getFlag("track-list/\(i)/external")
            if type == "sub" && external {
                let id = getInt("track-list/\(i)/id")
                command("sub-remove", args: ["\(id)"], checkForErrors: false)
            }
        }
        setStringProperty("sid", "no")
        invalidatePipPlaybackState()
    }

    func removeExternalSubtitlesAndSelect(_ trackId: Int) {
        guard mpv != nil else { return }
        let count = getInt("track-list/count")
        for i in stride(from: count - 1, through: 0, by: -1) {
            let type = getString("track-list/\(i)/type") ?? ""
            let external = getFlag("track-list/\(i)/external")
            if type == "sub" && external {
                let id = getInt("track-list/\(i)/id")
                command("sub-remove", args: ["\(id)"], checkForErrors: false)
            }
        }
        if trackId >= 0 {
            selectSubtitle(trackId)
        } else {
            setStringProperty("sid", "no")
            invalidatePipPlaybackState()
        }
    }

    func setSubtitleDelayMs(_ delayMs: Int) {
        guard mpv != nil else { return }
        var delaySeconds = Double(max(-60_000, min(60_000, delayMs))) / 1000.0
        checkError(mpv_set_property(mpv, "sub-delay", MPV_FORMAT_DOUBLE, &delaySeconds))
    }

    func applySubtitleStyle(
        textColor: String,
        backgroundColor: String,
        outlineColor: String,
        outlineSize: Float,
        bold: Bool,
        fontSize: Float,
        subPos: Int
    ) {
        guard mpv != nil else { return }

        checkError(mpv_set_property_string(mpv, "sub-ass-override", "force"))
        checkError(mpv_set_property_string(mpv, "sub-color", textColor))
        checkError(mpv_set_property_string(mpv, "sub-back-color", backgroundColor))
        checkError(mpv_set_property_string(mpv, "sub-outline-color", outlineColor))
        checkError(mpv_set_property_string(mpv, "sub-border-style", backgroundColor.hasPrefix("#00") ? "outline-and-shadow" : "opaque-box"))
        setStringProperty("sub-bold", bold ? "yes" : "no")

        var outline = Double(outlineSize)
        checkError(mpv_set_property(mpv, "sub-outline-size", MPV_FORMAT_DOUBLE, &outline))

        var size = Double(fontSize)
        checkError(mpv_set_property(mpv, "sub-font-size", MPV_FORMAT_DOUBLE, &size))

        var position = Int64(subPos)
        checkError(mpv_set_property(mpv, "sub-pos", MPV_FORMAT_INT64, &position))
    }

    func updateNowPlayingMetadata(title: String, subtitle: String?, artworkUrl: String?) {
        nowPlayingController.updateMetadata(title: title, subtitle: subtitle, artworkUrl: artworkUrl)
        nowPlayingController.syncPlayback(
            positionMs: positionMs,
            durationMs: durationMs,
            isPlaying: isPlayerPlaying,
            playbackSpeed: currentSpeed
        )
    }

    func clearNowPlayingInfo() {
        nowPlayingController.clear()
    }

    func destroyPlayer() {
        isDestroying = true
        NotificationCenter.default.removeObserver(self)
        UIApplication.shared.endReceivingRemoteControlEvents()
        resignFirstResponder()
        pipPossibleObservation?.invalidate()
        pipPossibleObservation = nil
        pendingLoadRetryWorkItem?.cancel()
        pendingLoadRetryWorkItem = nil
        pendingLoadRequest = nil
        teardownPiPIfNeeded()
        pipController = nil
        clearPlaybackError()
        audioSessionRetryWorkItem?.cancel()
        audioSessionRetryWorkItem = nil
        if isAudioSessionConfigured {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            isAudioSessionConfigured = false
        }
        pipController?.delegate = nil
        renderQueue.sync {
            // Drain any in-flight render work before freeing the mpv render context.
        }
        if let context = mpvRenderContext {
            mpvRenderContext = nil
            mpv_render_context_free(context)
        }
        guard let ctx = mpv else { return }
        mpv = nil  // nil first so event loop stops reading
        if let timebase {
            CMTimebaseSetRate(timebase, rate: 0.0)
        }
        mpv_terminate_destroy(ctx)
    }

    // MARK: - State Update

    /// Lightweight state refresh — called by Kotlin polling (every 250ms).
    /// Only reads cheap scalar properties; does NOT re-enumerate tracks.
    func refreshPlaybackState() {
        guard mpv != nil else { return }
        let duration = getDouble("duration")
        let position = getDouble("time-pos")
        let cached = getDouble("demuxer-cache-time")
        let speed = getDouble("speed")
        let paused = getFlag("pause")
        let eofReached = getFlag("eof-reached")
        let idle = getFlag("core-idle")
        let seeking = getFlag("seeking")
        let bufferingCache = getFlag("paused-for-cache")

        isPlayerLoading = (idle && !paused && !eofReached) || seeking || bufferingCache
        isPlayerPlaying = !paused && !idle && !eofReached
        isPlayerEnded = eofReached
        let previousDurationMs = durationMs
        durationMs = Int64(max(duration, 0) * 1000)
        positionMs = Int64(max(position, 0) * 1000)
        if previousDurationMs <= 0 && durationMs > 0 {
            invalidatePipPlaybackState()
        }
        bufferedMs = Int64(max(position + cached, 0) * 1000)
        currentSpeed = Float(speed > 0 ? speed : 1.0)
        let shouldPublishLoadingState = !isPlayerLoading || isPlayerPlaying || durationMs > 0 || positionMs > 0
        if shouldPublishLoadingState {
        }
    }


    /// Full state + track refresh — called from MPV event loop on property changes.
    func updateState() {
        refreshPlaybackState()
        refreshTracks()
    }

    private func refreshTracks() {
        guard mpv != nil else { return }
        var audio = [TrackInfo]()
        var subs = [TrackInfo]()
        let count = getInt("track-list/count")
        var audioIdx = 0
        var subIdx = 0

        for i in 0..<count {
            let type = getString("track-list/\(i)/type") ?? ""
            let id = getInt("track-list/\(i)/id")
            let title = getTrackString(i, "title")
            let lang = getTrackString(i, "lang")
            let codec = getTrackString(i, "codec")
            let decoderDescription = getTrackString(i, "decoder-desc")
            let channels = getTrackString(i, "demux-channels")
            let channelCount = getInt("track-list/\(i)/demux-channel-count")
            let selected = getFlag("track-list/\(i)/selected")
            let displayTitle = formatTrackTitle(
                type: type,
                index: type == "audio" ? audioIdx : subIdx,
                title: title,
                lang: lang,
                codec: codec,
                decoderDescription: decoderDescription,
                channels: channels,
                channelCount: channelCount
            )

            if type == "audio" {
                audio.append(TrackInfo(index: audioIdx, id: id, type: type, title: displayTitle, lang: lang, selected: selected))
                audioIdx += 1
            } else if type == "sub" {
                subs.append(TrackInfo(index: subIdx, id: id, type: type, title: displayTitle, lang: lang, selected: selected))
                subIdx += 1
            }
        }
        audioTracks = audio
        subtitleTracks = subs
    }

    private func getTrackString(_ index: Int, _ field: String) -> String {
        (getString("track-list/\(index)/\(field)") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatTrackTitle(
        type: String,
        index: Int,
        title: String,
        lang: String,
        codec: String,
        decoderDescription: String,
        channels: String,
        channelCount: Int
    ) -> String {
        let base = ifNotBlank(title)
            ?? localizedLanguageName(lang)
            ?? (type == "sub" ? "Subtitle \(index + 1)" : "Track \(index + 1)")
        let codecName = codecDisplayName(codec) ?? codecDisplayName(decoderDescription)
        let channelName = type == "audio" ? channelLayoutName(channels: channels, channelCount: channelCount) : nil
        let details = [channelName, codecName]
            .compactMap { $0 }
            .filter { detail in !base.localizedCaseInsensitiveContains(detail) }
        return details.isEmpty ? base : "\(base) (\(details.joined(separator: ", ")))"
    }

    private func ifNotBlank(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func localizedLanguageName(_ languageCode: String) -> String? {
        guard let code = ifNotBlank(languageCode) else { return nil }
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    private func channelLayoutName(channels: String, channelCount: Int) -> String? {
        if let normalized = ifNotBlank(channels), normalized != "unknown" {
            let lower = normalized.lowercased()
            if lower == "mono" { return "Mono" }
            if lower == "stereo" { return "Stereo" }
            return normalized
        }
        switch channelCount {
        case 1:
            return "Mono"
        case 2:
            return "Stereo"
        case 6:
            return "5.1"
        case 8:
            return "7.1"
        case let count where count > 0:
            return "\(count)ch"
        default:
            return nil
        }
    }

    private func codecDisplayName(_ value: String) -> String? {
        guard let raw = ifNotBlank(value) else { return nil }
        let codec = raw.lowercased()
        if codec.contains("eac3") || codec.contains("e-ac-3") || codec.contains("e ac-3") {
            return codec.contains("joc") || codec.contains("atmos") ? "E-AC-3-JOC" : "E-AC-3"
        }
        if codec.contains("truehd") || codec.contains("true hd") { return "TrueHD" }
        if codec.contains("ac3") || codec.contains("ac-3") { return "AC-3" }
        if codec.contains("dts-hd") || codec.contains("dtshd") || codec.contains("dts hd") { return "DTS-HD" }
        if codec.contains("dts") || codec == "dca" { return "DTS" }
        if codec.contains("aac") { return "AAC" }
        if codec.contains("mp3") || codec.contains("mpeg audio") { return "MP3" }
        if codec.contains("mp2") { return "MP2" }
        if codec.contains("opus") { return "Opus" }
        if codec.contains("vorbis") { return "Vorbis" }
        if codec.contains("flac") { return "FLAC" }
        if codec.contains("alac") { return "ALAC" }
        if codec.contains("pcm") || codec.contains("wav") { return "WAV" }
        if codec.contains("amr_wb") || codec.contains("amr-wb") { return "AMR-WB" }
        if codec.contains("amr_nb") || codec.contains("amr-nb") { return "AMR-NB" }
        if codec.contains("amr") { return "AMR" }
        if codec.contains("iamf") { return "IAMF" }
        if codec.contains("mpegh") || codec.contains("mpeg-h") { return "MPEG-H" }
        if codec.contains("pgs") || codec.contains("hdmv") { return "PGS" }
        if codec.contains("subrip") || codec == "srt" { return "SRT" }
        if codec.contains("ass") || codec.contains("ssa") { return "SSA" }
        if codec.contains("webvtt") || codec == "vtt" { return "VTT" }
        if codec.contains("ttml") { return "TTML" }
        if codec.contains("mov_text") || codec.contains("tx3g") { return "TX3G" }
        if codec.contains("dvb") { return "DVB" }
        return raw
    }

    private func clearPlaybackError() {
        errorStateLock.lock()
        recentPlaybackLogs.removeAll(keepingCapacity: true)
        _currentErrorMessage = nil
        errorStateLock.unlock()
    }

    private func appendPlaybackLog(prefix: String, level: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard level == "warn" || level == "error" || level == "fatal" else { return }

        let formatted = "[\(prefix)] \(trimmed)"
        errorStateLock.lock()
        recentPlaybackLogs.append(formatted)
        if recentPlaybackLogs.count > 4 {
            recentPlaybackLogs.removeFirst(recentPlaybackLogs.count - 4)
        }
        errorStateLock.unlock()
    }

    private func setPlaybackError(_ fallback: String) {
        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        errorStateLock.lock()
        var parts = recentPlaybackLogs.suffix(3)
        if !trimmedFallback.isEmpty && !parts.contains(trimmedFallback) {
            parts.append(trimmedFallback)
        }
        _currentErrorMessage = parts.isEmpty ? "Unable to play this stream." : parts.joined(separator: "\n")
        errorStateLock.unlock()
    }

    // MARK: - Event Loop

    private func readEvents() {
        eventQueue.async { [weak self] in
            guard let self, let mpv = self.mpv else { return }

            while true {
                let event = mpv_wait_event(mpv, 0)
                guard let eventPtr = event else { break }
                if eventPtr.pointee.event_id == MPV_EVENT_NONE { break }

                switch eventPtr.pointee.event_id {
                case MPV_EVENT_PROPERTY_CHANGE:
                    DispatchQueue.main.async { self.updateState() }
                case MPV_EVENT_FILE_LOADED:
                    DispatchQueue.main.async {
                        self.clearPlaybackError()
                        self.isPlayerLoading = false
                        self.isPlayerPlaying = true
                        self.isPlayerEnded = false
                        self.setPlaybackRate(1.0)
                        self.scheduleRender()
                        self.updateState()
                        self.invalidatePipPlaybackState()
                    }
                case MPV_EVENT_END_FILE:
                    if let data = eventPtr.pointee.data {
                        let endFile = UnsafePointer<mpv_event_end_file>(OpaquePointer(data)).pointee
                        if endFile.reason == MPV_END_FILE_REASON_ERROR {
                            let errorText = String(cString: mpv_error_string(endFile.error))
                            self.setPlaybackError("[mpv] \(errorText)")
                        }
                    }
                    DispatchQueue.main.async {
                        self.flushPipLayer()
                        self.isPlayerEnded = true
                        self.isPlayerPlaying = false
                        self.invalidatePipPlaybackState()
                    }
                case MPV_EVENT_SHUTDOWN:
                    return
                case MPV_EVENT_LOG_MESSAGE:
                    if let msg = UnsafeMutablePointer<mpv_event_log_message>(OpaquePointer(eventPtr.pointee.data)) {
                        let prefix = String(cString: msg.pointee.prefix!)
                        let level = String(cString: msg.pointee.level!)
                        let text = String(cString: msg.pointee.text!)
                        self.appendPlaybackLog(prefix: prefix, level: level, text: text)
                    }
                default:
                    break
                }
            }
        }
    }

    // MARK: - MPV Helpers

    private func command(_ command: String, args: [String?] = [], checkForErrors: Bool = true) {
        guard mpv != nil else { return }
        var cargs = makeCArgs(command, args).map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
        defer { for ptr in cargs where ptr != nil { free(UnsafeMutablePointer(mutating: ptr!)) } }
        let ret = mpv_command(mpv, &cargs)
        if checkForErrors { checkError(ret) }
    }

    private func makeCArgs(_ command: String, _ args: [String?]) -> [String?] {
        var strArgs = args
        strArgs.insert(command, at: 0)
        strArgs.append(nil)
        return strArgs
    }

    private func getDouble(_ name: String) -> Double {
        guard mpv != nil else { return 0.0 }
        var data = Double()
        mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
        return data
    }

    private func getString(_ name: String) -> String? {
        guard mpv != nil else { return nil }
        let cstr = mpv_get_property_string(mpv, name)
        let str: String? = cstr == nil ? nil : String(cString: cstr!)
        mpv_free(cstr)
        return str
    }

    private func getFlag(_ name: String) -> Bool {
        guard mpv != nil else { return false }
        var data = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &data)
        return data > 0
    }

    private func setFlag(_ name: String, _ flag: Bool) {
        guard mpv != nil else { return }
        var data: Int = flag ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
    }

    private func setStringProperty(_ name: String, _ value: String) {
        guard mpv != nil else { return }
        checkError(mpv_set_property_string(mpv, name, value))
    }

    private func setOptionString(_ name: String, _ value: String) {
        guard mpv != nil else { return }
        _ = mpv_set_option_string(mpv, name, value)
    }

    private func setVideoEqualizer(_ name: String, _ value: Int) {
        guard mpv != nil else { return }
        var clamped = Int64(max(-100, min(100, value)))
        checkError(mpv_set_property(mpv, name, MPV_FORMAT_INT64, &clamped))
    }

    private func getInt(_ name: String) -> Int {
        guard mpv != nil else { return 0 }
        var data = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_INT64, &data)
        return Int(data)
    }

    private func checkError(_ status: CInt, context: String? = nil) {
        _ = context
        if status < 0 { return }
    }

    private func sanitizeRequestHeaders(_ headers: [String: String]) -> [String: String] {
        guard !headers.isEmpty else { return [:] }

        var sanitized: [String: String] = [:]
        sanitized.reserveCapacity(headers.count)
        headers.forEach { rawKey, rawValue in
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return }
            guard key.caseInsensitiveCompare("Range") != .orderedSame else { return }
            sanitized[key] = value
        }
        return sanitized
    }

    private func applyRequestHeaders(_ headers: [String: String]) {
        guard mpv != nil else { return }
        if headers.isEmpty {
            checkError(mpv_set_property_string(mpv, "http-header-fields", ""))
            return
        }

        let serialized = headers
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { key, value in
                let escapedValue = value
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: ",", with: "\\,")
                return "\(key): \(escapedValue)"
            }
            .joined(separator: ",")
        checkError(mpv_set_property_string(mpv, "http-header-fields", serialized))
    }

    private func refreshImmersiveSystemUI() {
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        setNeedsStatusBarAppearanceUpdate()

        var currentParent = parent
        while let controller = currentParent {
            controller.setNeedsUpdateOfHomeIndicatorAutoHidden()
            controller.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
            controller.setNeedsStatusBarAppearanceUpdate()
            if let rootController = controller as? RootComposeViewController {
                rootController.refreshImmersiveSystemUI()
            }
            currentParent = controller.parent
        }
    }
}

extension MPVPlayerViewController {
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard isStoppingPiPForForegroundTransition else { return }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        isRestoringPiPUserInterface = true
        didRestorePiPUserInterface = true
        shouldPresentPiPTransitionOverlay = true
        showPiPTransitionOverlay()
        DispatchQueue.main.async {
            completionHandler(true)
        }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        let shouldRequestExitPlayback = !didRequestForegroundTransitionStop
        completePiPForegroundTransition()
        if shouldRequestExitPlayback {
            notifyPiPDidRequestExitPlayback()
        }
        didRestorePiPUserInterface = false
        didRequestForegroundTransitionStop = false
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    setPlaying playing: Bool) {
        DispatchQueue.main.async { [weak self] in
            if playing {
                self?.playPlayback()
            } else {
                self?.pausePlayback()
            }
        }
    }

    private func notifyPiPDidRequestExitPlayback() {
        NotificationCenter.default.post(
            name: Notification.Name("NuvioPlayerPiPDidRequestExitPlayback"),
            object: nil
        )
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        let start = CMTime(seconds: 0, preferredTimescale: 600)
        guard durationMs > 0 else {
            return CMTimeRange(start: start, duration: .positiveInfinity)
        }
        let duration = CMTime(seconds: Double(durationMs) / 1000.0, preferredTimescale: 600)
        return CMTimeRange(start: start, duration: duration)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        return !isPlayerPlaying
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        // No-op. The layer already tracks the host bounds.
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    skipByInterval skipInterval: CMTime,
                                    completion: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            let deltaMs = Int64((skipInterval.seconds * 1000.0).rounded())
            self?.seekByMs(deltaMs)
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        return false
    }
}

// MARK: - Bridge Creator (implements Kotlin protocol)

final class MPVPlayerBridgeCreator: NSObject, NuvioPlayerBridgeCreator {
    func createBridge() -> any NuvioPlayerBridge {
        return MPVPlayerBridgeImpl()
    }
}

// MARK: - Registration (called from Swift app startup)

enum NuvioPlayerRegistration {
    static func register() {
        NuvioPlayerBridgeFactory.shared.registerFactory(creator: MPVPlayerBridgeCreator())
    }
}
