import Foundation
import UIKit
import AVFoundation

private var pipCoordinatorKey: UInt8 = 0

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

    func invalidatePipPlaybackState() {
        pipCoordinator?.invalidatePlaybackState()
    }

    func setPipPlaybackRate(_ rate: Double) {
        pipCoordinator?.setPlaybackRate(rate)
    }

    func flushPipLayer() {
        pipCoordinator?.flushPipLayer()
    }

    func notifyPipFormatChanged() {
        pipCoordinator?.notifyPipFormatChanged()
    }
}

// MARK: - PiP Delegate / Playback Controller Conformance

extension MPVPlayerViewController: MPVPictureInPictureControllerDelegate {
    func pictureInPictureDidChangeActiveState(active: Bool) {
        // If we need to notify Kotlin in the future, we can add a listener here.
    }

    func pictureInPictureDidRequestExitPlayback() {
        NotificationCenter.default.post(
            name: Notification.Name("NuvioPlayerPiPDidRequestExitPlayback"),
            object: nil
        )
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
}
