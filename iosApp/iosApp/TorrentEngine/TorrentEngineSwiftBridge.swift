import Foundation
import Foundation

@objc public class TorrentEngineSwiftBridge: NSObject {
    @objc public static let shared = TorrentEngineSwiftBridge()

    private var isStarted = false
    private let engineQueue = DispatchQueue(label: "com.nuvio.torrent.cppengine", qos: .userInitiated)

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
                print("[LibtorrentBridge] Failed to create cache dir: \(error)")
            }

            // Start HTTP Server
            let port = LibtorrentHTTPServer.shared.start(downloadPath: downloadPath)
            if port == 0 {
                print("[LibtorrentBridge] Failed to start HTTP server.")
                return
            }
            
            // Setup C++ Engine Config
            let config = LTEngineConfig()
            if let data = configJson.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                config.batterySaver = json["batterySaver"] as? Bool ?? false
                config.enableDHT = json["enableDHT"] as? Bool ?? true
                config.forceTcp = json["forceTcp"] as? Bool ?? false
                config.maxPeerConnections = Int32(json["maxPeerConnections"] as? Int ?? 250)
                config.maxUploadRateBps = Int64(json["maxUploadRateBps"] as? Int ?? 0)
                config.maxCacheSizeBytes = Int64(json["maxCacheSizeBytes"] as? Int ?? (2 * 1024 * 1024 * 1024))
            }

            // Start C++ Engine
            let errStr = LibtorrentBridge.shared().startEngine(withDataDir: downloadPath, config: config)
            if let err = errStr, !err.isEmpty {
                print("[LibtorrentBridge] Failed to start engine: \(err)")
                LibtorrentHTTPServer.shared.stop()
                return
            }
            
            isStarted = true
            print("[LibtorrentBridge] Engine started successfully at \(downloadPath)")
        }
    }

    @objc public func stopEngine() {
        engineQueue.sync {
            guard isStarted else { return }
            LibtorrentBridge.shared().stopEngine()
            LibtorrentHTTPServer.shared.stop()
            isStarted = false
            print("[LibtorrentBridge] Engine stopped")
        }
    }

    @objc public func isEngineRunning() -> Bool {
        return isStarted
    }

    @objc public func addTorrentSession(magnetUri: String, infoHash: String, fileIdx: Int32) -> String {
        var resultJson = "{}"
        engineQueue.sync {
            guard isStarted else {
                resultJson = "{\"errorMessage\": \"Engine not started\"}"
                return
            }
            resultJson = LibtorrentBridge.shared().addMagnet(magnetUri, fileIndex: fileIdx)
            
            // Override the port in the result JSON to point to our Swift HTTP Server
            if let data = resultJson.data(using: .utf8),
               var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let oldStreamUrl = obj["streamUrl"] as? String {
                let httpPort = LibtorrentHTTPServer.shared.port
                obj["streamUrl"] = "http://127.0.0.1:\(httpPort)/stream/\(infoHash)?fileIdx=\(fileIdx)"
                if let newData = try? JSONSerialization.data(withJSONObject: obj),
                   let newStr = String(data: newData, encoding: .utf8) {
                    resultJson = newStr
                }
            }
        }
        return resultJson
    }

    @objc public func removeTorrentSession(sessionId: String) {
        engineQueue.async {
            guard self.isStarted else { return }
            LibtorrentBridge.shared().removeTorrent(withHash: sessionId)
        }
    }

    @objc public func getSessionStatusJson(sessionId: String) -> String {
        var resultJson = "{}"
        engineQueue.sync {
            guard isStarted else { return }
            resultJson = LibtorrentBridge.shared().getStatusForHash(sessionId, magnetUri: "", fileIndex: Int32(-1))
            
            // Override the port in the result JSON to point to our Swift HTTP Server
            if let data = resultJson.data(using: .utf8),
               var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let oldStreamUrl = obj["streamUrl"] as? String {
                let httpPort = LibtorrentHTTPServer.shared.port
                obj["streamUrl"] = "http://127.0.0.1:\(httpPort)/stream/\(sessionId)?fileIdx=-1" // fileIdx is ignored on GET
                if let newData = try? JSONSerialization.data(withJSONObject: obj),
                   let newStr = String(data: newData, encoding: .utf8) {
                    resultJson = newStr
                }
            }
        }
        return resultJson
    }

    @objc public func getEngineStatsJson() -> String {
        // We can wire this up to get global libtorrent stats later if needed
        return "{}" 
    }
    
    @objc public func destroyEngine() {
        stopEngine()
    }
}
