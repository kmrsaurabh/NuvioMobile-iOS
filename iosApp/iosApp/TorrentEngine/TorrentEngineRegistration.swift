// TorrentEngineRegistration.swift
// NuvioMobile-iOS
//
// Registers the Swift TorrentEngineSwiftBridge with the Kotlin
// TorrentEngineBridgeFactory so that Kotlin can create and use
// the native torrent engine via the bridge adapter.

import Foundation
import ComposeApp

// MARK: - Swift → Kotlin Bridge Adapter

/// Implements the Kotlin `SwiftTorrentBridge` protocol by delegating
/// to the Swift `TorrentEngineSwiftBridge` singleton.
final class SwiftTorrentBridgeImpl: NSObject, SwiftTorrentBridge {
    private let engine = TorrentEngineSwiftBridge.shared

    func startEngine(configJson: String) {
        engine.startEngine(configJson)
    }

    func stopEngine() {
        engine.stopEngine()
    }

    func isEngineRunning() -> Bool {
        return engine.isEngineRunning()
    }

    func addTorrentSession(magnetUri: String, infoHash: String, fileIdx: Int32) -> String {
        return engine.addTorrentSession(magnetUri: magnetUri, infoHash: infoHash, fileIdx: fileIdx)
    }

    func removeTorrentSession(sessionId: String) {
        engine.removeTorrentSession(sessionId: sessionId)
    }

    func getSessionStatusJson(sessionId: String) -> String {
        return engine.getSessionStatusJson(sessionId: sessionId)
    }

    func getEngineStatsJson() -> String {
        return engine.getEngineStatsJson()
    }

    func destroyEngine() {
        engine.destroyEngine()
    }
}

// MARK: - Bridge Creator (implements Kotlin protocol)

/// Creates a `TorrentEngineBridge` instance by wrapping the Swift bridge
/// in the Kotlin `TorrentEngineBridgeAdapter`.
final class TorrentEngineBridgeCreatorImpl: NSObject, TorrentEngineBridgeCreator {
    func createBridge() -> any TorrentEngineBridge {
        let swiftBridge = SwiftTorrentBridgeImpl()
        return TorrentEngineBridgeAdapter(swiftBridge: swiftBridge)
    }
}

// MARK: - Registration (called from Swift app startup)

enum NuvioTorrentRegistration {
    static func register() {
        TorrentEngineBridgeFactory.shared.registerFactory(creator: TorrentEngineBridgeCreatorImpl())
        print("[TorrentEngine] Bridge registered with Kotlin factory")
    }
}
