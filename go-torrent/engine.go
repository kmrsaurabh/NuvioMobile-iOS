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
	"github.com/anacrolix/torrent/metainfo"
	"golang.org/x/time/rate"
)

var (
	client               *torrent.Client
	server               *http.Server
	port                 int
	mu                   sync.RWMutex
	globalCustomTrackers []string
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
	CustomTrackers     string `json:"customTrackers"`
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

	globalCustomTrackers = nil
	if parsedCfg.CustomTrackers != "" {
		parts := strings.FieldsFunc(parsedCfg.CustomTrackers, func(c rune) bool {
			return c == ',' || c == '\n' || c == '\r'
		})
		for _, p := range parts {
			if p != "" {
				globalCustomTrackers = append(globalCustomTrackers, strings.TrimSpace(p))
			}
		}
	}
	
	if parsedCfg.MaxPeerConnections > 0 {
		cfg.EstablishedConnsPerTorrent = parsedCfg.MaxPeerConnections
		cfg.HalfOpenConnsPerTorrent = 250 // Aggressive handshaking
	} else {
		cfg.EstablishedConnsPerTorrent = 250
		cfg.HalfOpenConnsPerTorrent = 250 // Aggressive handshaking
	}
	
	if parsedCfg.BatterySaver {
		cfg.NoDHT = true
		cfg.DisablePEX = true
		if parsedCfg.MaxPeerConnections <= 0 || parsedCfg.MaxPeerConnections > 20 {
			cfg.EstablishedConnsPerTorrent = 20
			cfg.HalfOpenConnsPerTorrent = 10
		}
	} else {
		cfg.NoDHT = !parsedCfg.EnableDHT
	}

	cfg.TorrentPeersHighWater = 500
	cfg.TorrentPeersLowWater = 150

	if parsedCfg.MaxUploadRate > 0 {
		cfg.UploadRateLimiter = rate.NewLimiter(rate.Limit(parsedCfg.MaxUploadRate), int(parsedCfg.MaxUploadRate))
	} else {
		cfg.UploadRateLimiter = rate.NewLimiter(rate.Limit(10*1024), 10*1024)
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

	if len(globalCustomTrackers) > 0 {
		if mag, err := metainfo.ParseMagnetUri(uri); err == nil {
			for _, tr := range globalCustomTrackers {
				mag.Trackers = append(mag.Trackers, tr)
			}
			uri = mag.String()
		}
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
	mu.RLock()
	defer mu.RUnlock()
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

			targetFile.Download()
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

	select {
	case <-t.GotInfo():
	case <-r.Context().Done():
		return
	}

	fileIdx := -1
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

	targetFile.Download()
	reader := targetFile.NewReader()
	defer reader.Close()

	reader.SetResponsive()
	
	// Adaptive readahead: 10% of file size, between 5MB and 50MB
	readahead := targetFile.Length() / 10
	if readahead < 5*1024*1024 {
		readahead = 5 * 1024 * 1024
	} else if readahead > 50*1024*1024 {
		readahead = 50 * 1024 * 1024
	}
	reader.SetReadahead(readahead)

	// Wait for at least some data to be downloaded before returning HTTP 200 OK.
	// If we return 200 OK with 0 bytes available, ffmpeg/mpv might throw
	// "stream ends prematurely at 0" and fail to probe the container format.
	if r.Method == "GET" {
		for {
			if targetFile.Length() > 0 && targetFile.BytesCompleted() > 0 {
				break
			}
			select {
			case <-time.After(10 * time.Millisecond):
				continue
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
