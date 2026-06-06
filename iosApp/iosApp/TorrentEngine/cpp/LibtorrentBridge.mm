//
//  LibtorrentBridge.mm
//  iosApp (Nuvio++)
//
//  Objective-C++ implementation file (.mm = Objective-C + C++).
//  This is where Swift-callable ObjC methods call into the raw C++ libtorrent API.
//

#import "LibtorrentBridge.h"
#import <Foundation/Foundation.h>
#import <Network/Network.h>

// ── libtorrent C++ includes ──────────────────────────────────────────────────
#include "libtorrent/session.hpp"
#include "libtorrent/session_params.hpp"
#include "libtorrent/settings_pack.hpp"
#include "libtorrent/torrent_handle.hpp"
#include "libtorrent/torrent_info.hpp"
#include "libtorrent/magnet_uri.hpp"
#include "libtorrent/alert_types.hpp"
#include "libtorrent/extensions/ut_metadata.hpp"
#include "libtorrent/extensions/ut_pex.hpp"
#include "libtorrent/extensions/smart_ban.hpp"

#include <string>
#include <mutex>
#include <map>
#include <thread>
#include <sstream>

// ── Default tracker list (always injected into every magnet) ─────────────────
static const std::vector<std::string> kDefaultTrackers = {
    "udp://open.stealth.si:80/announce",
    "udp://tracker.opentrackr.org:1337/announce",
    "udp://tracker.openbittorrent.com:6969/announce",
    "udp://exodus.desync.com:6969/announce",
    "udp://tracker.torrent.eu.org:451/announce",
    "udp://tracker.tiny-vps.com:6969/announce",
    "udp://tracker.dler.org:6969/announce",
    "https://tracker.tamersunion.org:443/announce"
};

// ── Internal C++ session state ───────────────────────────────────────────────
namespace {
    lt::session *gSession = nullptr;
    std::mutex   gMutex;
    // Map infoHash (hex string) → torrent_handle
    std::map<std::string, lt::torrent_handle> gTorrents;
    // Alert pump thread
    std::thread  gAlertThread;
    bool         gRunning = false;
}

// ── Objective-C++ Implementation ─────────────────────────────────────────────

@implementation LTSessionStatus
@end

@implementation LTEngineConfig
- (instancetype)init {
    self = [super init];
    if (self) {
        _enableDHT         = YES;
        _maxPeerConnections = 900;
    }
    return self;
}
@end

@implementation LibtorrentBridge {
    BOOL _isRunning;
}

+ (instancetype)shared {
    static LibtorrentBridge *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[LibtorrentBridge alloc] init];
    });
    return instance;
}

static NSString *gDataDir = nil;

- (nullable NSString *)startEngineWithDataDir:(NSString *)dataDir
                                       config:(LTEngineConfig *)config {
    std::lock_guard<std::mutex> lock(gMutex);
    if (gSession != nullptr) return nil; // Already running
    
    gDataDir = dataDir;

    @try {
        // ── 1. Build settings_pack ───────────────────────────────────────────
        lt::settings_pack pack;

        // Core peer limits
        int maxConns = (config.maxPeerConnections > 0) ? config.maxPeerConnections : 250;
        pack.set_int(lt::settings_pack::connections_limit, maxConns);
        pack.set_int(lt::settings_pack::peer_tos, 0);

        // High/low water marks for peer churn
        pack.set_int(lt::settings_pack::peer_connect_timeout, 10);
        pack.set_int(lt::settings_pack::connect_seed_every_n_download, 3);
        
        // Fast streaming connection bursting (Aggressive swarm)
        pack.set_int(lt::settings_pack::connection_speed, 500);

        // 128MB "Shock Absorber" Cache
        pack.set_int(lt::settings_pack::cache_size, 8192);

        // DHT
        if (!config.enableDHT) {
            pack.set_bool(lt::settings_pack::enable_dht, false);
        } else {
            pack.set_bool(lt::settings_pack::enable_dht, true);
            pack.set_str(lt::settings_pack::dht_bootstrap_nodes,
                         "router.bittorrent.com:6881,"
                         "router.utorrent.com:6881,"
                         "dht.transmissionbt.com:6881,"
                         "dht.aelitis.com:6881");
        }

        // PEX and LSD
        pack.set_bool(lt::settings_pack::enable_lsd, !config.batterySaver);

        // UTP vs TCP
        if (config.forceTcp) {
            pack.set_bool(lt::settings_pack::enable_incoming_utp, false);
            pack.set_bool(lt::settings_pack::enable_outgoing_utp, false);
        } else {
            pack.set_bool(lt::settings_pack::enable_incoming_utp, true);
            pack.set_bool(lt::settings_pack::enable_outgoing_utp, true);
        }

        // Upload limiting — Zero throttling for maximum performance
        if (config.enableUpload && config.maxUploadRateBps > 0) {
            pack.set_int(lt::settings_pack::upload_rate_limit, (int)config.maxUploadRateBps);
        } else {
            pack.set_int(lt::settings_pack::upload_rate_limit, 0); // 0 means unlimited
        }
        
        // Advanced Engine Optimizations
        pack.set_int(lt::settings_pack::tick_interval, 100); // 100ms reactor tick for faster response

        // Download limiting
        if (config.maxDownloadRateBps > 0) {
            pack.set_int(lt::settings_pack::download_rate_limit, (int)config.maxDownloadRateBps);
        } else {
            pack.set_int(lt::settings_pack::download_rate_limit, 0);
        }

        // UPnP and NAT-PMP
        if (config.enableUpnp) {
            pack.set_bool(lt::settings_pack::enable_upnp, true);
            pack.set_bool(lt::settings_pack::enable_natpmp, true);
        } else {
            pack.set_bool(lt::settings_pack::enable_upnp, false);
            pack.set_bool(lt::settings_pack::enable_natpmp, false);
        }

        // Listen interfaces
        if (config.listenPort > 0) {
            NSString *interfaces = [NSString stringWithFormat:@"0.0.0.0:%d,[::]:%d", config.listenPort, config.listenPort];
            pack.set_str(lt::settings_pack::listen_interfaces, interfaces.UTF8String);
        } else {
            pack.set_str(lt::settings_pack::listen_interfaces, "0.0.0.0:6881,[::]:6881");
        }

        // Battery saver mode (disabled for maximum performance)
        if (config.batterySaver) {
            // Disabled: we want aggressive peering at all times
        }

        // Disk I/O — use async disk I/O for iOS
        pack.set_int(lt::settings_pack::disk_io_write_mode, lt::settings_pack::enable_os_cache);
        pack.set_int(lt::settings_pack::disk_io_read_mode,  lt::settings_pack::enable_os_cache);

        // Save path for downloaded pieces
        pack.set_str(lt::settings_pack::user_agent, "Nuvio/1.0");

        // ── 2. Create session ────────────────────────────────────────────────
        lt::session_params params(pack);
        gSession = new lt::session(std::move(params));

        // ── 3. Install plugins ───────────────────────────────────────────────
        gSession->add_extension(&lt::create_ut_metadata_plugin);  // magnet metadata
        gSession->add_extension(&lt::create_ut_pex_plugin);       // peer exchange
        gSession->add_extension(&lt::create_smart_ban_plugin);    // ban malicious peers
        
        // ── 4. Start alert pump thread ───────────────────────────────────────
        gRunning = true;
        gAlertThread = std::thread([](){
            while (gRunning) {
                std::vector<lt::alert *> alerts;
                {
                    std::lock_guard<std::mutex> lk(gMutex);
                    if (gSession) gSession->pop_alerts(&alerts);
                }
                // Process alerts — mostly for logging/debugging in this phase
                for (auto *a : alerts) {
                    if (lt::torrent_error_alert *err = lt::alert_cast<lt::torrent_error_alert>(a)) {
                        NSLog(@"[LibtorrentBridge] Torrent error: %s", err->message().c_str());
                    }
                }
                std::this_thread::sleep_for(std::chrono::milliseconds(500));
            }
        });

        _isRunning = YES;
        NSLog(@"[LibtorrentBridge] Session started successfully.");
        return nil;

    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"Exception starting libtorrent: %@", e.reason];
    }
}

- (void)stopEngine {
    {
        std::lock_guard<std::mutex> lock(gMutex);
        gRunning = false;
        if (gSession) {
            delete gSession;
            gSession = nullptr;
        }
        gTorrents.clear();
    }
    if (gAlertThread.joinable()) gAlertThread.join();
    _isRunning = NO;
    NSLog(@"[LibtorrentBridge] Session stopped.");
}

- (NSString *)addMagnet:(NSString *)magnetUri fileIndex:(int)fileIdx {
    std::lock_guard<std::mutex> lock(gMutex);
    if (!gSession) {
        return @"{\"errorMessage\": \"Engine not started\"}";
    }

    lt::error_code ec;
    lt::add_torrent_params p = lt::parse_magnet_uri(magnetUri.UTF8String, ec);
    if (ec) {
        return [NSString stringWithFormat:@"{\"errorMessage\": \"Invalid magnet: %s\"}", ec.message().c_str()];
    }

    // Inject high-quality default trackers to ensure we find peers even if magnet trackers are dead
    for (const auto &tr : kDefaultTrackers) {
        p.trackers.push_back(tr);
    }

    p.flags |= lt::torrent_flags::sequential_download; // Start sequential immediately
    p.save_path = gDataDir ? gDataDir.UTF8String : ""; // Pieces go here

    lt::torrent_handle h = gSession->add_torrent(std::move(p), ec);
    if (ec) {
        return [NSString stringWithFormat:@"{\"errorMessage\": \"Add torrent failed: %s\"}", ec.message().c_str()];
    }

    // Instant Warmup & Preloading: Aggressively request first 50 pieces immediately
    for (int i = 0; i < 50; ++i) {
        h.set_piece_deadline(lt::piece_index_t(i), 500, lt::torrent_handle::alert_when_available);
    }

    std::stringstream ss;
    ss << h.info_hash();
    std::string hash = ss.str();
    gTorrents[hash] = h;

    return [self _statusJsonForHandle:h hash:hash uri:magnetUri fileIndex:fileIdx];
}

- (void)setPieceDeadline:(int)pieceIndex forHash:(NSString *)hash deadlineMs:(int)ms {
    std::lock_guard<std::mutex> lock(gMutex);
    auto it = gTorrents.find(hash.UTF8String);
    if (it != gTorrents.end() && it->second.is_valid()) {
        it->second.set_piece_deadline(lt::piece_index_t(pieceIndex), ms, lt::torrent_handle::alert_when_available);
    }
}

- (BOOL)hasPiece:(int)pieceIndex forHash:(NSString *)hash {
    std::lock_guard<std::mutex> lock(gMutex);
    auto it = gTorrents.find(hash.UTF8String);
    if (it != gTorrents.end() && it->second.is_valid()) {
        return it->second.have_piece(lt::piece_index_t(pieceIndex));
    }
    return NO;
}

- (int)pieceLengthForHash:(NSString *)hash {
    std::lock_guard<std::mutex> lock(gMutex);
    auto it = gTorrents.find(hash.UTF8String);
    if (it != gTorrents.end() && it->second.is_valid()) {
        auto tf = it->second.torrent_file();
        if (tf) return tf->piece_length();
    }
    return 0; // Default or error
}

- (NSString *)getStatusForHash:(NSString *)hash
                      magnetUri:(NSString *)uri
                      fileIndex:(int)fileIdx {
    std::lock_guard<std::mutex> lock(gMutex);
    auto it = gTorrents.find(hash.UTF8String);
    if (it == gTorrents.end()) {
        return @"{\"errorMessage\": \"Torrent not found\"}";
    }
    return [self _statusJsonForHandle:it->second
                                 hash:hash.UTF8String
                                  uri:uri
                            fileIndex:fileIdx];
}

- (void)removeTorrentWithHash:(NSString *)hash {
    std::lock_guard<std::mutex> lock(gMutex);
    auto it = gTorrents.find(hash.UTF8String);
    if (it != gTorrents.end()) {
        if (gSession) gSession->remove_torrent(it->second);
        gTorrents.erase(it);
    }
}

- (int)streamingPort {
    return 0; // Handled by Swift LibtorrentHTTPServer
}

// ── Private helper ────────────────────────────────────────────────────────────

- (NSString *)_statusJsonForHandle:(lt::torrent_handle)h
                              hash:(const std::string &)hashStr
                               uri:(NSString *)uri
                         fileIndex:(int)fileIdx {
    lt::torrent_status s = h.status();
    bool metaReady = (bool)h.torrent_file();

    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"sessionId"]          = @(hashStr.c_str());
    d[@"infoHash"]           = @(hashStr.c_str());
    d[@"magnetUri"]          = uri;
    d[@"fileIndex"]          = @(fileIdx);
    d[@"numPeers"]           = @(s.num_peers);
    d[@"numSeeds"]           = @(s.num_seeds);
    d[@"downloadRate"]       = @(s.download_rate);
    d[@"uploadRate"]         = @(s.upload_rate);
    d[@"isMetadataResolved"] = @(metaReady);
    d[@"isStreaming"]        = @(NO);

    if (!metaReady) {
        d[@"status"]   = @"resolvingmetadata";
        d[@"progress"] = @(0.0);
    } else {
        auto tf = h.torrent_file();
        lt::file_index_t targetIdx;
        int64_t fileSize = 0;

        // Find correct file
        if (fileIdx >= 0 && fileIdx < tf->num_files()) {
            targetIdx = lt::file_index_t(fileIdx);
        } else {
            // Pick the largest file
            int64_t largest = 0;
            for (int i = 0; i < tf->num_files(); ++i) {
                lt::file_index_t idx(i);
                if (tf->files().file_size(idx) > largest) {
                    largest = tf->files().file_size(idx);
                    targetIdx = idx;
                }
            }
        }

        fileSize = tf->files().file_size(targetIdx);
        std::string fileName = tf->files().file_path(targetIdx);

        int64_t downloaded = (int64_t)(s.progress_ppm / 1000000.0 * fileSize);
        double progress = s.progress;

        d[@"fileName"]        = @(fileName.c_str());
        d[@"fileOffset"]      = @(tf->files().file_offset(targetIdx));
        d[@"totalSizeBytes"]  = @(fileSize);
        d[@"downloadedBytes"] = @(downloaded);
        d[@"progress"]        = @(progress);

        if (progress >= 1.0) {
            d[@"status"] = @"completed";
        } else if (progress > 0) {
            d[@"status"]      = @"streaming";
            d[@"isStreaming"] = @(YES);
        } else {
            d[@"status"] = @"downloading";
        }

        // Stream URL served by our local HTTP server
        d[@"streamUrl"] = [NSString stringWithFormat:@"http://127.0.0.1:%d/stream/%s?fileIdx=%d",
                           0, hashStr.c_str(), (int)targetIdx];
    }

    NSError *err;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:d options:0 error:&err];
    if (!jsonData) return @"{\"errorMessage\": \"JSON serialization failed\"}";
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

@end
