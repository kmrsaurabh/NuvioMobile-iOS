import Foundation
import UIKit
import MediaPlayer

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}

final class PlayerNowPlayingController {
    private struct Metadata {
        var title: String?
        var subtitle: String?
        var artworkUrl: String?
    }

    private struct PlaybackState {
        var isPlaying: Bool = false
        var positionMs: Int64 = 0
        var durationMs: Int64 = 0
        var playbackSpeed: Float = 1.0
    }

    private struct RemoteCommandTarget {
        let command: MPRemoteCommand
        let token: Any
    }

    private weak var owner: MPVPlayerViewController?
    private var metadata = Metadata()
    private var playbackState = PlaybackState()
    private var currentArtworkImage: UIImage?
    private var currentArtworkURL: String?
    private var artworkTask: URLSessionDataTask?
    private var remoteTargets: [RemoteCommandTarget] = []
    private let artworkCache = NSCache<NSString, UIImage>()


    private func nowPlayingLog(_ message: String) {
        print("[Nuvio][NowPlaying] \(message)")
    }

    init(owner: MPVPlayerViewController) {
        self.owner = owner
        configureRemoteCommands()
    }

    deinit {
        clear()
    }

    func updateMetadata(
        title: String,
        subtitle: String?,
        artworkUrl: String?
    ) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSubtitle = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedArtworkUrl = artworkUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitleLogValue = normalizedSubtitle ?? "nil"
        let artworkLogValue = normalizedArtworkUrl ?? "nil"
        nowPlayingLog("updateMetadata title=\(normalizedTitle) subtitle=\(subtitleLogValue) artworkUrl=\(artworkLogValue)")

        if metadata.title == normalizedTitle,
           metadata.subtitle == normalizedSubtitle,
           currentArtworkURL == normalizedArtworkUrl {
            nowPlayingLog("updateMetadata skipped because metadata did not change")
            return
        }

        metadata.title = normalizedTitle
        metadata.subtitle = normalizedSubtitle

        if normalizedArtworkUrl != currentArtworkURL {
            currentArtworkURL = normalizedArtworkUrl
            currentArtworkImage = nil
            artworkTask?.cancel()
            artworkTask = nil

            guard let urlString = normalizedArtworkUrl, !urlString.isEmpty else {
                nowPlayingLog("artwork cleared: empty URL")
                applyNowPlayingInfo()
                return
            }

            if let cached = artworkCache.object(forKey: urlString as NSString) {
                nowPlayingLog("artwork cache hit url=\(urlString) size=\(cached.size)")
                currentArtworkImage = cached
                applyNowPlayingInfo()
                return
            }

            guard let url = URL(string: urlString) else {
                nowPlayingLog("artwork invalid URL=\(urlString)")
                applyNowPlayingInfo()
                return
            }

            nowPlayingLog("artwork download start url=\(urlString)")
            let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                guard let self else { return }
                if let error {
                    self.nowPlayingLog("artwork download failed url=\(urlString) error=\(error.localizedDescription)")
                    return
                }
                if let http = response as? HTTPURLResponse {
                    self.nowPlayingLog("artwork download response url=\(urlString) status=\(http.statusCode) bytes=\(data?.count ?? 0)")
                }
                guard let data, let image = UIImage(data: data) else {
                    self.nowPlayingLog("artwork decode failed url=\(urlString) bytes=\(data?.count ?? 0)")
                    return
                }
                self.nowPlayingLog("artwork loaded url=\(urlString) size=\(image.size)")
                self.artworkCache.setObject(image, forKey: urlString as NSString)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.currentArtworkURL == urlString else {
                        self?.nowPlayingLog("artwork ignored because URL changed before completion")
                        return
                    }
                    self.currentArtworkImage = image
                    self.applyNowPlayingInfo()
                }
            }
            artworkTask = task
            task.resume()
        }

        applyNowPlayingInfo()
    }

    func syncPlayback(
        positionMs: Int64,
        durationMs: Int64,
        isPlaying: Bool,
        playbackSpeed: Float
    ) {
        playbackState.isPlaying = isPlaying
        playbackState.positionMs = max(0, positionMs)
        playbackState.durationMs = max(0, durationMs)
        playbackState.playbackSpeed = playbackSpeed > 0 ? playbackSpeed : 1.0
        nowPlayingLog("syncPlayback positionMs=\(playbackState.positionMs) durationMs=\(playbackState.durationMs) isPlaying=\(playbackState.isPlaying) speed=\(playbackState.playbackSpeed)")
        applyNowPlayingInfo()
    }

    func clear() {
        nowPlayingLog("clear")
        artworkTask?.cancel()
        artworkTask = nil
        currentArtworkImage = nil
        currentArtworkURL = nil
        metadata = Metadata()
        playbackState = PlaybackState()
        removeRemoteCommandTargets()
        DispatchQueue.main.async {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }

    private let posterArtworkSize = CGSize(width: 600, height: 900)
    private let episodeArtworkSize = CGSize(width: 1140, height: 360)

    private func artworkTargetSize(for image: UIImage) -> CGSize {
        guard image.size.width > 0, image.size.height > 0 else {
            return posterArtworkSize
        }
        return image.size.width > image.size.height ? episodeArtworkSize : posterArtworkSize
    }

    private func nowPlayingArtworkImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
        guard targetSize.width > 0, targetSize.height > 0 else {
            return image
        }

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return image
        }

        let imageAspect = imageSize.width / imageSize.height
        let targetAspect = targetSize.width / targetSize.height

        let drawSize: CGSize
        if imageAspect > targetAspect {
            let height = targetSize.height
            drawSize = CGSize(width: height * imageAspect, height: height)
        } else {
            let width = targetSize.width
            drawSize = CGSize(width: width, height: width / imageAspect)
        }

        let drawOrigin = CGPoint(
            x: (targetSize.width - drawSize.width) / 2.0,
            y: (targetSize.height - drawSize.height) / 2.0
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
    }

    private func applyNowPlayingInfo() {
        let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
            ?? "Nuvio"
        nowPlayingLog("apply title=\(title) durationMs=\(playbackState.durationMs) positionMs=\(playbackState.positionMs) isPlaying=\(playbackState.isPlaying) speed=\(playbackState.playbackSpeed) hasArtwork=\(currentArtworkImage != nil)")

        let buildInfo = {
            var info: [String: Any] = [:]
            info[MPMediaItemPropertyTitle] = title
            if let subtitle = self.metadata.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
                info[MPMediaItemPropertyArtist] = subtitle
            }
            info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
            let durationSeconds = Double(self.playbackState.durationMs) / 1000.0
            let elapsedSeconds = Double(self.playbackState.positionMs) / 1000.0
            let defaultRate = Double(self.playbackState.playbackSpeed)
            let playbackRate = self.playbackState.isPlaying ? defaultRate : 0.0

            if durationSeconds.isFinite && durationSeconds > 0 {
                info[MPMediaItemPropertyPlaybackDuration] = durationSeconds
                info[MPNowPlayingInfoPropertyIsLiveStream] = false
            } else {
                info[MPNowPlayingInfoPropertyIsLiveStream] = true
            }
            if elapsedSeconds.isFinite && elapsedSeconds >= 0 {
                info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedSeconds
            }
            info[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate
            info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = defaultRate
            if let artwork = self.currentArtworkImage {
                let targetSize = self.artworkTargetSize(for: artwork)
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: targetSize) { _ in
                    self.nowPlayingArtworkImage(artwork, targetSize: targetSize)
                }
            }

            let center = MPNowPlayingInfoCenter.default()
            center.nowPlayingInfo = info
        }

        if Thread.isMainThread {
            buildInfo()
        } else {
            DispatchQueue.main.async(execute: buildInfo)
        }
    }

    private func configureRemoteCommands() {
        guard remoteTargets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.seekForwardCommand.isEnabled = true
        center.seekBackwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]

        remoteTargets.append(
            RemoteCommandTarget(
                command: center.playCommand,
                token: center.playCommand.addTarget { [weak self] _ in
                    self?.nowPlayingLog("remote play")
                    DispatchQueue.main.async { self?.owner?.playPlayback() }
                    return .success
                }
            )
        )
        remoteTargets.append(
            RemoteCommandTarget(
                command: center.pauseCommand,
                token: center.pauseCommand.addTarget { [weak self] _ in
                    self?.nowPlayingLog("remote pause")
                    DispatchQueue.main.async { self?.owner?.pausePlayback() }
                    return .success
                }
            )
        )
        remoteTargets.append(
            RemoteCommandTarget(
                command: center.togglePlayPauseCommand,
                token: center.togglePlayPauseCommand.addTarget { [weak self] _ in
                    self?.nowPlayingLog("remote togglePlayPause")
                    DispatchQueue.main.async {
                        guard let owner = self?.owner else { return }
                        if owner.isPlayerPlaying {
                            owner.pausePlayback()
                        } else {
                            owner.playPlayback()
                        }
                    }
                    return .success
                }
            )
        )
        remoteTargets.append(
            RemoteCommandTarget(
                command: center.skipForwardCommand,
                token: center.skipForwardCommand.addTarget { [weak self] event in
                    guard let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
                    self?.nowPlayingLog("remote skipForward interval=\(event.interval)")
                    DispatchQueue.main.async {
                        self?.owner?.seekByMs(Int64(event.interval * 1000.0))
                    }
                    return .success
                }
            )
        )
        remoteTargets.append(
            RemoteCommandTarget(
                command: center.skipBackwardCommand,
                token: center.skipBackwardCommand.addTarget { [weak self] event in
                    guard let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
                    self?.nowPlayingLog("remote skipBackward interval=\(event.interval)")
                    DispatchQueue.main.async {
                        self?.owner?.seekByMs(-Int64(event.interval * 1000.0))
                    }
                    return .success
                }
            )
        )
        remoteTargets.append(
            RemoteCommandTarget(
                command: center.nextTrackCommand,
                token: center.nextTrackCommand.addTarget { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.owner?.seekByMs(10_000)
                    }
                    return .success
                }
            )
        )
        remoteTargets.append(
            RemoteCommandTarget(
                command: center.previousTrackCommand,
                token: center.previousTrackCommand.addTarget { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.owner?.seekByMs(-10_000)
                    }
                    return .success
                }
            )
        )
        remoteTargets.append(
            RemoteCommandTarget(
                command: center.seekForwardCommand,
                token: center.seekForwardCommand.addTarget { [weak self] event in
                    guard let event = event as? MPSeekCommandEvent else { return .commandFailed }
                    if event.type == .beginSeeking {
                        DispatchQueue.main.async {
                            self?.owner?.seekByMs(10_000)
                        }
                    }
                    return .success
                }
            )
        )
        remoteTargets.append(
            RemoteCommandTarget(
                command: center.seekBackwardCommand,
                token: center.seekBackwardCommand.addTarget { [weak self] event in
                    guard let event = event as? MPSeekCommandEvent else { return .commandFailed }
                    if event.type == .beginSeeking {
                        DispatchQueue.main.async {
                            self?.owner?.seekByMs(-10_000)
                        }
                    }
                    return .success
                }
            )
        )
        remoteTargets.append(
            RemoteCommandTarget(
                command: center.changePlaybackPositionCommand,
                token: center.changePlaybackPositionCommand.addTarget { [weak self] event in
                    guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
                    self?.nowPlayingLog("remote changePlaybackPosition positionTime=\(event.positionTime)")
                    DispatchQueue.main.async {
                        self?.owner?.seekToMs(Int64(event.positionTime * 1000.0))
                    }
                    return .success
                }
            )
        )
    }

    private func removeRemoteCommandTargets() {
        guard !remoteTargets.isEmpty else { return }
        remoteTargets.forEach { target in
            target.command.removeTarget(target.token)
        }
        remoteTargets.removeAll(keepingCapacity: false)
    }
}
