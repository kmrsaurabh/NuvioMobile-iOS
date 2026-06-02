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
)

var (
	client *torrent.Client
	server *http.Server
	port   int
	mu     sync.RWMutex
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

func StartEngine(dataDir string) string {
	mu.Lock()
	defer mu.Unlock()

	if client != nil {
		return ""
	}

	cfg := torrent.NewDefaultClientConfig()
	cfg.DataDir = dataDir
	cfg.NoDefaultPortForwarding = true

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

	<-t.GotInfo()

	fileIdx := -1
	fmt.Sscanf(r.URL.Query().Get("fileIdx"), "%d", &fileIdx)

	info := t.Info()
	if info == nil {
		http.Error(w, "Metadata not ready", 500)
		return
	}

	files := t.Files()
	var targetFile *torrent.File
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

	if targetFile == nil {
		http.Error(w, "File not found", 404)
		return
	}

	targetFile.Download()
	reader := targetFile.NewReader()
	defer reader.Close()

	reader.SetResponsive()

	w.Header().Set("Content-Disposition", "attachment; filename=\""+filepath.Base(targetFile.DisplayPath())+"\"")
	http.ServeContent(w, r, filepath.Base(targetFile.DisplayPath()), time.Time{}, reader)
}
