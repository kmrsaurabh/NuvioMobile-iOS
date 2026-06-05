package gotorrent

import (
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/anacrolix/torrent"
	"golang.org/x/time/rate"
)

var (
	client               *torrent.Client
	server               *http.Server
	port                 int
	mu                   sync.RWMutex
	persistentReaders    = make(map[string]torrent.Reader)
)

type SessionStatus struct {
	SessionId          string  `json:"sessionId"`
	InfoHash           string  `json:"infoHash"`
	MagnetUri          string  `json:"magnetUri"`
	FileIndex          int     `json:"fileIndex"`
	Status             string  `json:"status"`
	StreamUrl          string  `json:"streamUrl"`
	FileName           string  `json:"fileName"`
	TotalSizeBytes     int64   `json:"totalSizeBytes"`
	DownloadedBytes    int64   `json:"downloadedBytes"`
	DownloadRate       int64   `json:"downloadRate"`
	UploadRate         int64   `json:"uploadRate"`
	NumPeers           int     `json:"numPeers"`
	NumSeeds           int     `json:"numSeeds"`
	Progress           float64 `json:"progress"`
	IsMetadataResolved bool    `json:"isMetadataResolved"`
	IsStreaming        bool    `json:"isStreaming"`
	ErrorMessage       string  `json:"errorMessage,omitempty"`
}

type EngineConfig struct {
	HttpPort           int   `json:"httpPort"`
	MaxCacheSizeBytes  int64 `json:"maxCacheSizeBytes"`
	MaxDownloadRate    int64 `json:"maxDownloadRate"`
	MaxUploadRate      int64 `json:"maxUploadRate"`
	MaxPeerConnections int    `json:"maxPeerConnections"`
	EnableUpnp         bool   `json:"enableUpnp"`
	EnableDHT          bool   `json:"enableDHT"`
	ForceTcp           bool   `json:"forceTcp"`
	BatterySaver       bool   `json:"batterySaver"`
}

func StartEngine(dataDir string, configJson string) string {
	mu.Lock()
	defer mu.Unlock()

	if client != nil {
		return ""
	}

	var parsedCfg EngineConfig
	if configJson != "" {
		_ = json.Unmarshal([]byte(configJson), &parsedCfg)
	}

	cfg := torrent.NewDefaultClientConfig()
	cfg.DataDir = dataDir
	
	// Apply dynamic settings
	cfg.NoDefaultPortForwarding = !parsedCfg.EnableUpnp
	cfg.DisableUTP = parsedCfg.ForceTcp

	if parsedCfg.MaxPeerConnections > 0 {
		cfg.EstablishedConnsPerTorrent = parsedCfg.MaxPeerConnections
		cfg.HalfOpenConnsPerTorrent = parsedCfg.MaxPeerConnections / 2
	} else {
		// Mobile-appropriate defaults: each connection holds ~64KB of buffers,
		// so 80 conns ≈ 10MB overhead vs 250 conns ≈ 32MB.
		cfg.EstablishedConnsPerTorrent = 80
		cfg.HalfOpenConnsPerTorrent = 40
	}
	
	if parsedCfg.BatterySaver {
		if parsedCfg.MaxPeerConnections <= 0 || parsedCfg.MaxPeerConnections > 20 {
			cfg.EstablishedConnsPerTorrent = 20
			cfg.HalfOpenConnsPerTorrent = 10
		}
	}
	
	// Always enable DHT and PEX since custom trackers are gone
	cfg.NoDHT = false
	cfg.DisablePEX = false

	// Peer discovery water marks — controls how many peer addresses are kept
	// in memory for potential connection. Lower values save RAM.
	cfg.TorrentPeersHighWater = 200
	cfg.TorrentPeersLowWater = 50


	if parsedCfg.MaxUploadRate > 0 {
		cfg.UploadRateLimiter = rate.NewLimiter(rate.Limit(parsedCfg.MaxUploadRate), int(parsedCfg.MaxUploadRate))
	} else {
		cfg.UploadRateLimiter = rate.NewLimiter(rate.Limit(1), 1)
	}

	c, err := torrent.NewClient(cfg)
	if err != nil {
		return err.Error()
	}
	client = c

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return err.Error()
	}
	port = listener.Addr().(*net.TCPAddr).Port

	mux := http.NewServeMux()
	mux.HandleFunc("/stream/", handleStream)

	server = &http.Server{Handler: mux}
	go server.Serve(listener)

	return ""
}

func StopEngine() {
	mu.Lock()
	defer mu.Unlock()
	
	for _, r := range persistentReaders {
		r.Close()
	}
	persistentReaders = make(map[string]torrent.Reader)

	if server != nil {
		server.Close()
		server = nil
	}
	if client != nil {
		client.Close()
		client = nil
	}
}

func AddMagnet(uri string, fileIdx int) string {
	mu.Lock()
	defer mu.Unlock()

	if client == nil {
		return `{"errorMessage": "Engine not started"}`
	}

	t, err := client.AddMagnet(uri)
	if err != nil {
		return fmt.Sprintf(`{"errorMessage": "%s"}`, err.Error())
	}

	hash := t.InfoHash().HexString()
	return getSessionStatusJson(hash, uri, fileIdx, t)
}

func GetSessionStatus(hash string, uri string, fileIdx int) string {
	mu.RLock()
	defer mu.RUnlock()

	if client == nil {
		return `{"errorMessage": "Engine not started"}`
	}

	var t *torrent.Torrent
	for _, tt := range client.Torrents() {
		if tt.InfoHash().HexString() == hash {
			t = tt
			break
		}
	}
	
	if t == nil {
		return `{"errorMessage": "Torrent not found"}`
	}

	return getSessionStatusJson(hash, uri, fileIdx, t)
}

func RemoveTorrent(hash string) {
	mu.Lock()
	defer mu.Unlock()
	
	if r, ok := persistentReaders[hash]; ok {
		r.Close()
		delete(persistentReaders, hash)
	}
	
	if client != nil {
		for _, t := range client.Torrents() {
			if t.InfoHash().HexString() == hash {
				t.Drop()
				break
			}
		}
	}
}

func GetEngineStatsJson() string {
	return `{"activeSessions": 1, "totalDownloadRate": 0, "totalUploadRate": 0}`
}

func getSessionStatusJson(hash, uri string, fileIdx int, t *torrent.Torrent) string {
	info := t.Info()

	status := "resolvingmetadata"
	if info != nil {
		status = "downloading"
	}

	s := SessionStatus{
		SessionId:          hash,
		InfoHash:           hash,
		MagnetUri:          uri,
		FileIndex:          fileIdx,
		Status:             status,
		NumPeers:           len(t.PeerConns()),
		IsMetadataResolved: info != nil,
	}

	if info != nil {
		var targetFile *torrent.File
		files := t.Files()
		if fileIdx >= 0 && fileIdx < len(files) {
			targetFile = files[fileIdx]
		} else {
			var largestSize int64
			for _, f := range files {
				if f.Length() > largestSize {
					largestSize = f.Length()
					targetFile = f
				}
			}
		}

		if targetFile != nil {
			s.FileName = targetFile.DisplayPath()
			s.TotalSizeBytes = targetFile.Length()
			s.DownloadedBytes = targetFile.BytesCompleted()
			if targetFile.Length() > 0 {
				s.Progress = float64(targetFile.BytesCompleted()) / float64(targetFile.Length())
			}
			if s.Progress >= 1.0 {
				s.Status = "completed"
			} else if s.Progress > 0 {
				s.Status = "streaming"
				s.IsStreaming = true
			}

			mu.Lock()
			if _, exists := persistentReaders[hash]; !exists {
				reader := targetFile.NewReader()
				reader.SetResponsive()
				readahead := targetFile.Length() / 20
				if readahead < 5*1024*1024 {
					readahead = 5 * 1024 * 1024
				} else if readahead > 50*1024*1024 {
					readahead = 50 * 1024 * 1024
				}
				reader.SetReadahead(readahead)
				persistentReaders[hash] = reader

				// Kickstart the reader so the piece picker actually starts fetching
				// the initial pieces immediately, rather than waiting for the HTTP
				// handler to send headers and block on Read().
				go func(r torrent.Reader) {
					b := make([]byte, 1)
					r.Read(b)
				}(reader)
			}
			mu.Unlock()
		}

		s.StreamUrl = fmt.Sprintf("http://127.0.0.1:%d/stream/%s?fileIdx=%d", port, hash, fileIdx)
	}

	b, _ := json.Marshal(s)
	return string(b)
}

func handleStream(w http.ResponseWriter, r *http.Request) {
	mu.RLock()
	c := client
	mu.RUnlock()

	if c == nil {
		http.Error(w, "Engine not started", 500)
		return
	}

	parts := strings.Split(r.URL.Path, "/")
	if len(parts) < 3 {
		http.Error(w, "Invalid path", 400)
		return
	}
	hash := parts[2]

	var t *torrent.Torrent
	for _, tt := range c.Torrents() {
		if tt.InfoHash().HexString() == hash {
			t = tt
			break
		}
	}
	
	if t == nil {
		http.Error(w, "Torrent not found", 404)
		return
	}

	metadataWaitDeadline := time.After(300 * time.Second)
	for t.Info() == nil {
		select {
		case <-time.After(200 * time.Millisecond):
		case <-metadataWaitDeadline:
			http.Error(w, "Timeout waiting for metadata", 504)
			return
		case <-r.Context().Done():
			return
		}
	}

	var fileIdx int = -1
	fmt.Sscanf(r.URL.Query().Get("fileIdx"), "%d", &fileIdx)

	info := t.Info()
	if info == nil {
		http.Error(w, "Metadata not ready", 500)
		return
	}

	filenameHint := r.URL.Query().Get("filename")

	files := t.Files()
	var targetFile *torrent.File
	if fileIdx >= 0 && fileIdx < len(files) {
		targetFile = files[fileIdx]
	} else if filenameHint != "" {
		for _, f := range files {
			if strings.Contains(strings.ToLower(f.DisplayPath()), strings.ToLower(filenameHint)) {
				targetFile = f
				break
			}
		}
	}
	
	if targetFile == nil {
		var largestSize int64
		for _, f := range files {
			if f.Length() > largestSize {
				largestSize = f.Length()
				targetFile = f
			}
		}
	}

	if targetFile == nil {
		http.Error(w, "File not found", 404)
		return
	}

	// Do NOT call targetFile.Download() here — it queues the ENTIRE file for
	// download using the default piece picker, which competes with the reader's
	// sequential requests and slows streaming significantly.

	reader := targetFile.NewReader()
	defer reader.Close()

	// SetResponsive makes the piece picker prioritise pieces the reader needs
	// NOW over any queued ahead-of-time requests.
	reader.SetResponsive()
	
	// Conservative readahead: 5% of file size, clamped between 5MB and 50MB.
	// Large readahead on mobile saturates the connection and increases memory
	// pressure without benefit for real-time streaming.
	readahead := targetFile.Length() / 20
	if readahead < 5*1024*1024 {
		readahead = 5 * 1024 * 1024
	} else if readahead > 50*1024*1024 {
		readahead = 50 * 1024 * 1024
	}
	reader.SetReadahead(readahead)

	// Wait until at least some initial data is available before handing off
	// to http.ServeContent.  Without this, ffmpeg/MPV gets a valid HTTP
	// response header (with Content-Length) but zero body bytes, causing
	// "[ffmpeg] http: stream ends prematurely at 0".
	userAgent := r.Header.Get("User-Agent")
	isMPV := strings.Contains(userAgent, "mpv") || strings.Contains(userAgent, "Lavf") || strings.Contains(userAgent, "AppleCoreMedia")

	if r.Method != http.MethodHead && isMPV {
		waitDeadline := time.After(120 * time.Second)
		for targetFile.BytesCompleted() == 0 {
			select {
			case <-time.After(200 * time.Millisecond):
			case <-waitDeadline:
				http.Error(w, "Timeout waiting for initial data", 504)
				return
			case <-r.Context().Done():
				return
			}
		}
	}

	// Set Content-Type based on file extension so MPV/ffmpeg recognises the
	// container format immediately instead of guessing.
	fileName := filepath.Base(targetFile.DisplayPath())
	contentType := inferContentType(fileName)
	w.Header().Set("Content-Type", contentType)

	http.ServeContent(w, r, fileName, time.Time{}, reader)
}

func inferContentType(filename string) string {
	ext := strings.ToLower(filepath.Ext(filename))
	switch ext {
	case ".mp4", ".m4v":
		return "video/mp4"
	case ".mkv":
		return "video/x-matroska"
	case ".avi":
		return "video/x-msvideo"
	case ".webm":
		return "video/webm"
	case ".ts":
		return "video/mp2t"
	case ".mov":
		return "video/quicktime"
	case ".flv":
		return "video/x-flv"
	case ".wmv":
		return "video/x-ms-wmv"
	default:
		return "application/octet-stream"
	}
}

