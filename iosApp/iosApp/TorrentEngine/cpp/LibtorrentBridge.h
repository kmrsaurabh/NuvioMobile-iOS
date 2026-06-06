//
//  LibtorrentBridge.h
//  iosApp (Nuvio++)
//
//  Objective-C header exposing libtorrent-rasterbar C++ engine to Swift.
//  This is the ONLY file Swift sees — all C++ is hidden behind this interface.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Status snapshot for a single active torrent session.
@interface LTSessionStatus : NSObject
@property (nonatomic, copy) NSString *sessionId;
@property (nonatomic, copy) NSString *infoHash;
@property (nonatomic, copy) NSString *status;       // "resolvingmetadata" | "downloading" | "streaming" | "completed"
@property (nonatomic, copy) NSString *streamUrl;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, assign) long long totalSizeBytes;
@property (nonatomic, assign) long long downloadedBytes;
@property (nonatomic, assign) long long downloadRateBps;
@property (nonatomic, assign) long long uploadRateBps;
@property (nonatomic, assign) long long preloadedBytes;
@property (nonatomic, assign) int numPeers;
@property (nonatomic, assign) int numSeeds;
@property (nonatomic, assign) double progress;
@property (nonatomic, assign) BOOL isMetadataResolved;
@property (nonatomic, assign) BOOL isStreaming;
@property (nonatomic, nullable, copy) NSString *errorMessage;
@end

/// Configuration mirroring TorrentStreamingSettings on the Kotlin side.
@interface LTEngineConfig : NSObject
@property (nonatomic, assign) BOOL batterySaver;
@property (nonatomic, assign) BOOL forceTcp;
@property (nonatomic, assign) BOOL enableDHT;
@property (nonatomic, assign) BOOL enableUpload;
@property (nonatomic, assign) int  maxPeerConnections;   // 0 = use default (250)
@property (nonatomic, assign) long long maxUploadRateBps; // 0 = block upload (1 byte/s)
@property (nonatomic, assign) BOOL enableUpnp;
@property (nonatomic, assign) int  listenPort;
@property (nonatomic, assign) long long maxDownloadRateBps;
@end

/// The main singleton engine bridge. All Swift code talks through this.
@interface LibtorrentBridge : NSObject

+ (instancetype)shared;

/// Start the libtorrent session and internal HTTP streaming server.
/// Returns nil on success, or an error string on failure.
- (nullable NSString *)startEngineWithDataDir:(NSString *)dataDir
                                       config:(LTEngineConfig *)config;

/// Stop all torrents and shut down the session.
- (void)stopEngine;

/// Add a magnet link. Returns JSON-encoded LTSessionStatus.
- (NSString *)addMagnet:(NSString *)magnetUri fileIndex:(int)fileIdx;

/// Streaming primitive: Tell C++ engine that MPV urgently needs this piece index within deadlineMs.
- (void)setPieceDeadline:(int)pieceIndex forHash:(NSString *)hash deadlineMs:(int)ms;

/// Streaming primitive: Check if a piece is fully downloaded.
- (BOOL)hasPiece:(int)pieceIndex forHash:(NSString *)hash;

/// Streaming primitive: Get piece size for a given torrent.
- (int)pieceLengthForHash:(NSString *)hash;

/// Poll status for a known info-hash. Returns JSON-encoded LTSessionStatus.
- (NSString *)getStatusForHash:(NSString *)hash
                       magnetUri:(NSString *)uri
                       fileIndex:(int)fileIdx;

/// Remove a torrent from the session.
- (void)removeTorrentWithHash:(NSString *)hash;

/// The localhost port the HTTP streaming server is listening on.
- (int)streamingPort;

@end

NS_ASSUME_NONNULL_END
