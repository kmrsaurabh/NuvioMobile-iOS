import Foundation
import UIKit
import AVFoundation

private var pipCoordinatorKey: UInt8 = 0
private var pictureInPictureStateListenerKey: UInt8 = 0

extension MPVPlayerViewController {

    var pipCoordinator: MPVPictureInPictureController? {
        get {
            objc_getAssociatedObject(self, &pipCoordinatorKey) as? MPVPictureInPictureController
        }
        set {
            objc_setAssociatedObject(self, &pipCoordinatorKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    var isPictureInPictureSupported: Bool {
        pipCoordinator?.isSupported ?? false
    }

    var isPictureInPictureActive: Bool {
        pipCoordinator?.isActive ?? false
    }

    func setupPictureInPicture() {
        configurePlaybackAudioSession()
        let coordinator = MPVPictureInPictureController()
        coordinator.delegate = self
        coordinator.playbackController = self
        coordinator.frameSource = self
        coordinator.attach(toHostView: view)
        pipCoordinator = coordinator
    }

    private func configurePlaybackAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true, options: [])
        } catch {
            print("[NuvioPiP] AVAudioSession setup failed: \(error.localizedDescription)")
        }
    }

    func startPictureInPicture() {
        pipCoordinator?.startPictureInPicture()
    }

    func stopPictureInPicture() {
        pipCoordinator?.stopPictureInPicture()
    }
}

// MARK: - PiP Delegate / Playback Controller Conformance

extension MPVPlayerViewController: MPVPictureInPictureControllerDelegate {
    func pictureInPictureDidChangeActiveState(active: Bool) {
        // If we need to notify Kotlin in the future, we can add a listener here.
    }
}

extension MPVPlayerViewController: MPVPictureInPicturePlaybackController {
    func play() {
        playPlayback()
    }

    func pause() {
        pausePlayback()
    }

    func seek(byMs offsetMs: Int64) {
        seekByMs(offsetMs)
    }

    var isPlaying: Bool {
        refreshPlaybackState()
        return isPlayerPlaying
    }

    var isBuffering: Bool {
        refreshPlaybackState()
        return isPlayerLoading
    }
}

extension MPVPlayerViewController: MPVPictureInPictureFrameSource {
    func capturePictureInPictureFrame() -> CVPixelBuffer? {
        guard let mpv = self.mpv else { return nil }
        return MPVScreenshotCapture.capture(mpv: mpv)
    }
}
