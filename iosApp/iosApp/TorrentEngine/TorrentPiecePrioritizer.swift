// TorrentPiecePrioritizer.swift
// NuvioMobile-iOS
//
// Manages piece priority for streaming-optimized torrent downloading.
// Ensures pieces near the current playback position are downloaded first,
// enabling smooth video streaming without waiting for the full file.

import Foundation

// MARK: - Piece Priority Levels

/// Priority levels matching libtorrent's piece_priority enum.
/// These values are passed directly to the libtorrent C API.
@objc public enum PiecePriority: Int32 {
    /// Do not download this piece at all.
    case dontDownload = 0
    /// Low priority — download only if bandwidth is available.
    case low = 1
    /// Normal priority — default download behavior.
    case normal = 4
    /// High priority — download as soon as possible.
    case high = 6
    /// Critical priority — download immediately, required for playback.
    case critical = 7
}

// MARK: - Priority Apply Callback

/// Callback type used to apply computed priorities to the libtorrent session.
/// - Parameters:
///   - pieceIndex: The zero-based index of the piece.
///   - priority: The priority level to set for this piece.
public typealias PiecePriorityApplier = (_ pieceIndex: Int, _ priority: PiecePriority) -> Void

// MARK: - TorrentPiecePrioritizer

/// Manages piece download priorities for streaming-optimized torrent playback.
///
/// The prioritizer divides pieces into zones relative to the current playback position:
/// 1. **Critical zone**: Pieces immediately needed for playback (first few pieces).
/// 2. **High-priority zone**: Pieces in the near-future buffer window.
/// 3. **Normal zone**: Pieces within the lookahead buffer.
/// 4. **Low-priority zone**: All remaining pieces.
///
/// When the user seeks, priorities are recalculated around the new position.
@objc public class TorrentPiecePrioritizer: NSObject {

    // MARK: - Configuration Constants

    /// Number of pieces immediately ahead of playback that get critical priority.
    private static let criticalWindowPieces = 8

    /// Number of pieces in the high-priority buffer zone (after critical).
    private static let highPriorityWindowPieces = 32

    /// Number of pieces in the normal-priority lookahead zone (after high).
    private static let normalWindowPieces = 64

    // MARK: - Properties

    /// Total number of pieces in the torrent.
    public let totalPieces: Int

    /// Size of each piece in bytes (last piece may be smaller).
    public let pieceLength: Int

    /// Total size of the file being streamed in bytes.
    public let totalSize: Int64

    /// The piece index around which priorities are currently centered.
    private(set) var currentPieceIndex: Int = 0

    /// Serial queue ensuring thread-safe priority updates.
    private let queue = DispatchQueue(label: "com.nuvio.torrent.prioritizer", qos: .userInitiated)

    /// Callback invoked to apply a priority to a specific piece.
    /// Set this before calling any prioritization methods.
    public var priorityApplier: PiecePriorityApplier?

    /// Tracks which pieces have been fully downloaded (bitfield).
    private var downloadedPieces: [Bool]

    /// Last time priorities were recalculated, used for debouncing.
    private var lastPrioritizationTime: TimeInterval = 0

    /// Minimum interval between priority recalculations (seconds).
    private static let debounceInterval: TimeInterval = 0.5

    // MARK: - Initialization

    /// Creates a new piece prioritizer.
    /// - Parameters:
    ///   - totalPieces: Total number of pieces in the torrent.
    ///   - pieceLength: Size of each piece in bytes.
    ///   - totalSize: Total size of the target file in bytes.
    @objc public init(totalPieces: Int, pieceLength: Int, totalSize: Int64) {
        self.totalPieces = max(totalPieces, 1)
        self.pieceLength = max(pieceLength, 1)
        self.totalSize = max(totalSize, 1)
        self.downloadedPieces = [Bool](repeating: false, count: max(totalPieces, 1))
        super.init()
    }

    // MARK: - Byte-to-Piece Mapping

    /// Converts a byte offset to the corresponding piece index.
    /// - Parameter byteOffset: The byte offset within the file.
    /// - Returns: The zero-based piece index containing this byte.
    public func pieceIndex(forByte byteOffset: Int64) -> Int {
        guard pieceLength > 0 else { return 0 }
        let index = Int(byteOffset / Int64(pieceLength))
        return min(max(index, 0), totalPieces - 1)
    }

    /// Returns the byte range covered by the given piece.
    /// - Parameter pieceIndex: The zero-based piece index.
    /// - Returns: A tuple of (startByte, endByte) for this piece, or nil if index is invalid.
    public func byteRange(forPiece pieceIndex: Int) -> (start: Int64, end: Int64)? {
        guard pieceIndex >= 0, pieceIndex < totalPieces else { return nil }
        let start = Int64(pieceIndex) * Int64(pieceLength)
        let end = min(start + Int64(pieceLength), totalSize) - 1
        return (start, end)
    }

    // MARK: - Piece Download Tracking

    /// Marks a piece as downloaded. Called when libtorrent signals piece completion.
    /// - Parameter pieceIndex: The index of the completed piece.
    @objc public func markPieceDownloaded(_ pieceIndex: Int) {
        queue.async { [weak self] in
            guard let self = self, pieceIndex >= 0, pieceIndex < self.totalPieces else { return }
            self.downloadedPieces[pieceIndex] = true
        }
    }

    /// Checks if a specific piece has been downloaded.
    /// - Parameter pieceIndex: The piece index to check.
    /// - Returns: True if the piece is downloaded.
    public func isPieceDownloaded(_ pieceIndex: Int) -> Bool {
        var result = false
        queue.sync {
            guard pieceIndex >= 0, pieceIndex < totalPieces else { return }
            result = downloadedPieces[pieceIndex]
        }
        return result
    }

    /// Returns the count of downloaded pieces.
    public var downloadedPieceCount: Int {
        var count = 0
        queue.sync {
            count = downloadedPieces.filter { $0 }.count
        }
        return count
    }

    // MARK: - Priority Calculation

    /// Sets piece priorities optimized for streaming from the given byte position.
    ///
    /// This is the primary method called during normal playback. It calculates
    /// priorities based on the current playback position and applies them via
    /// the `priorityApplier` callback.
    ///
    /// - Parameter currentByte: The current playback byte offset in the file.
    @objc public func prioritizeForStreaming(currentByte: Int64) {
        queue.async { [weak self] in
            guard let self = self else { return }

            // Debounce rapid calls
            let now = ProcessInfo.processInfo.systemUptime
            guard now - self.lastPrioritizationTime >= Self.debounceInterval else { return }
            self.lastPrioritizationTime = now

            let startPiece = self.pieceIndex(forByte: currentByte)
            self.currentPieceIndex = startPiece
            self.applyPriorities(centeredAt: startPiece)
        }
    }

    /// Re-prioritizes pieces around a new seek position.
    ///
    /// Called when the user seeks to a new position in the video. Unlike
    /// `prioritizeForStreaming`, this method does NOT debounce — seek
    /// responsiveness is critical for user experience.
    ///
    /// - Parameter toByte: The byte offset being seeked to.
    @objc public func onSeek(toByte: Int64) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let seekPiece = self.pieceIndex(forByte: toByte)
            self.currentPieceIndex = seekPiece

            // Reset debounce so next streaming call also applies
            self.lastPrioritizationTime = 0
            self.applyPriorities(centeredAt: seekPiece)
        }
    }

    // MARK: - Internal Priority Application

    /// Applies priorities to all pieces based on their distance from the center piece.
    /// - Parameter centerPiece: The piece index to center priorities around.
    private func applyPriorities(centeredAt centerPiece: Int) {
        guard let applier = priorityApplier else {
            print("[TorrentPrioritizer] Warning: No priorityApplier set, skipping prioritization")
            return
        }

        let criticalEnd = min(centerPiece + Self.criticalWindowPieces, totalPieces)
        let highEnd = min(centerPiece + Self.criticalWindowPieces + Self.highPriorityWindowPieces, totalPieces)
        let normalEnd = min(centerPiece + Self.criticalWindowPieces + Self.highPriorityWindowPieces + Self.normalWindowPieces, totalPieces)

        for i in 0..<totalPieces {
            // Skip already-downloaded pieces — no need to change their priority
            if downloadedPieces[i] { continue }

            let priority: PiecePriority
            if i >= centerPiece && i < criticalEnd {
                priority = .critical
            } else if i >= centerPiece && i < highEnd {
                priority = .high
            } else if i >= centerPiece && i < normalEnd {
                priority = .normal
            } else if i < centerPiece {
                // Pieces behind the playback head — low priority
                priority = .low
            } else {
                // Pieces far ahead — low priority
                priority = .low
            }

            applier(i, priority)
        }

        // Always ensure the very first and last few pieces are at least normal priority.
        // First pieces contain file headers needed for codec detection.
        // Last pieces may contain index/metadata (e.g., moov atom in MP4).
        let headerPieces = min(4, totalPieces)
        for i in 0..<headerPieces {
            if !downloadedPieces[i] {
                applier(i, .critical)
            }
        }

        let trailerStart = max(totalPieces - 2, 0)
        for i in trailerStart..<totalPieces {
            if !downloadedPieces[i] {
                applier(i, .high)
            }
        }
    }

    // MARK: - Status

    /// Returns a summary of the current prioritization state for debugging.
    @objc public func statusDescription() -> String {
        var desc = ""
        queue.sync {
            let downloaded = downloadedPieces.filter { $0 }.count
            let pct = totalPieces > 0 ? Double(downloaded) / Double(totalPieces) * 100.0 : 0
            desc = """
            [Prioritizer] pieces: \(downloaded)/\(totalPieces) (\(String(format: "%.1f", pct))%), \
            center: \(currentPieceIndex), pieceLen: \(pieceLength)
            """
        }
        return desc
    }
}
