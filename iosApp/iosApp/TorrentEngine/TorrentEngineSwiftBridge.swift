import Foundation
import GoTorrent

@objc public class TorrentEngineSwiftBridge: NSObject {
    @objc public static let shared = TorrentEngineSwiftBridge()

    private var isStarted = false
    private var lastStartError: String = ""
    private let engineQueue = DispatchQueue(label: "com.nuvio.torrent.goengine", qos: .userInitiated)
    private var sessionCounter = 0

    private override init() {
        super.init()
    }

    @objc public func startEngine(_ configJson: String) {
        engineQueue.sync {
            guard !isStarted else { return }
            let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            let downloadPath = paths[0].appendingPathComponent("TorrentCache").path
            
            do {
                try FileManager.default.createDirectory(atPath: downloadPath, withIntermediateDirectories: true)
            } catch {
                print("[GoTorrent] Failed to create cache dir: \(error)")
                self.lastStartError = "Failed to create cache dir: \(error.localizedDescription)"
            }

            let errStr = GotorrentStartEngine(downloadPath, configJson)
            if !errStr.isEmpty {
                print("[GoTorrent] Failed to start engine: \(errStr)")
                self.lastStartError = errStr
                return
            }
            
            self.lastStartError = ""
            isStarted = true
            print("[GoTorrent] Engine started successfully at \(downloadPath)")
        }
    }

    @objc public func stopEngine() {
        engineQueue.sync {
            guard isStarted else { return }
            GotorrentStopEngine()
            isStarted = false
            self.lastStartError = ""
            print("[GoTorrent] Engine stopped")
        }
    }

    @objc public func isEngineRunning() -> Bool {
        return isStarted
    }

    @objc public func addTorrentSession(magnetUri: String, infoHash: String, fileIdx: Int32) -> String {
        var resultJson = "{}"
        engineQueue.sync {
            guard isStarted else {
                let errorMsg = self.lastStartError.isEmpty ? "Engine not started" : "Engine failed to start: \(self.lastStartError)"
                // Escape quotes in the error message for JSON
                let escapedMsg = errorMsg.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " ")
                resultJson = "{\"errorMessage\": \"\(escapedMsg)\"}"
                return
            }
            let res = GotorrentAddMagnet(magnetUri, Int(fileIdx))
            resultJson = res ?? "{}"
        }
        return resultJson
    }

    @objc public func removeTorrentSession(sessionId: String) {
        engineQueue.async {
            guard self.isStarted else { return }
            GotorrentRemoveTorrent(sessionId)
        }
    }

    @objc public func getSessionStatusJson(sessionId: String) -> String {
        var resultJson = "{}"
        engineQueue.sync {
            guard isStarted else { return }
            let res = GotorrentGetSessionStatus(sessionId, "", -1)
            resultJson = res ?? "{}"
        }
        return resultJson
    }

    @objc public func getEngineStatsJson() -> String {
        var resultJson = "{}"
        engineQueue.sync {
            guard isStarted else { return }
            resultJson = GotorrentGetEngineStatsJson() ?? "{}"
        }
        return resultJson
    }
    
    @objc public func destroyEngine() {
        stopEngine()
    }
}
