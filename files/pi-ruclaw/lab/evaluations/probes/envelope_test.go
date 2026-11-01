package server

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strconv"
	"sync/atomic"
	"testing"

	"ruclaw/internal/credbroker/a2abroker"
	c "ruclaw/internal/credbroker/a2abroker/contract"
	"ruclaw/internal/credbroker/client"
	"ruclaw/internal/credbroker/testinfra"
)

// Same real private HTTP writer/client and credential-free TLS download on both
// candidates. ALL sizes send the actual body, including overflow cases: truncating
// the body would test unexpected EOF instead of the encoded-envelope boundary.
func TestQualityContextlessHTTPEnvelope(t *testing.T) {
	for _, mode := range []string{"direct", "fallback", "sse"} {
		for _, size := range []int{16, 750 << 10, 1 << 20} {
			t.Run(fmt.Sprintf("%s/%d", mode, size), func(t *testing.T) {
				stream, partnerStream := mode != "direct", mode == "sse"
				wantFileError := stream && size == 1<<20
				payload := bytes.Repeat([]byte("p"), size)
				var origin string
				var sends, downloads atomic.Int32
				origin, roots, _ := testinfra.PrivateTLS(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					switch r.URL.Path {
					case "/card":
						_ = json.NewEncoder(w).Encode(map[string]any{"name": "quality", "capabilities": map[string]any{"streaming": partnerStream}, "supportedInterfaces": []any{map[string]any{"url": origin + "/rpc", "protocolBinding": "JSONRPC", "protocolVersion": "1.0"}}, "securitySchemes": map[string]any{"b": map[string]any{"http": map[string]any{"scheme": "Bearer"}}}, "securityRequirements": []any{map[string]any{"schemes": map[string]any{"b": []string{}}}}})
					case "/file":
						downloads.Add(1)
						if r.Header.Get("Authorization") != "" || r.Header.Get("Cookie") != "" || len(r.TLS.PeerCertificates) != 0 {
							t.Error("file download delegated credentials")
						}
						w.Header().Set("Content-Length", strconv.Itoa(len(payload)))
						_, _ = w.Write(payload)
					case "/rpc":
						sends.Add(1)
						var request struct {
							ID json.RawMessage `json:"id"`
						}
						if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
							t.Error(err)
							return
						}
						frame := map[string]any{"jsonrpc": "2.0", "id": request.ID, "result": map[string]any{"message": map[string]any{"messageId": "reply", "role": "ROLE_AGENT", "parts": []any{map[string]any{"text": "completed report"}, map[string]any{"url": origin + "/file", "filename": "report.pdf", "mediaType": "application/pdf"}}}}}
						if partnerStream {
							w.Header().Set("Content-Type", "text/event-stream")
							raw, _ := json.Marshal(frame)
							_, _ = fmt.Fprintf(w, "data: %s\n\n", raw)
						} else {
							_ = json.NewEncoder(w).Encode(frame)
						}
					default:
						t.Errorf("unexpected partner path: %s", r.URL.Path)
					}
				}))
				st := &a2aDownloadStore{reg: c.Registration{ID: "11d712c6-2533-4c32-ae71-8c34b94379e7", Enabled: true, Incarnation: 1, Policy: c.Policy{CardURL: origin + "/card", EndpointURL: origin + "/rpc", Binding: c.JSONRPC, Protocol: "1.0", ServiceIdentity: "quality"}}}
				srv, _ := newTestCredBrokerServer(t, testAdminToken)
				srv.ConfigureA2A(st, a2abroker.New(st, roots))
				endpoint := httptest.NewServer(srv.Handler())
				defer endpoint.Close()
				runtime := client.NewA2ARuntime(endpoint.URL, "a2at_test_file_grant")
				in := c.SendRequest{Parts: []c.Part{{Kind: "text", Text: "report"}}}
				var message *c.Message
				if stream {
					ended := false
					for event, err := range runtime.SendStream(t.Context(), st.reg.ID, in) {
						if err != nil || event.Kind == "error" {
							t.Fatalf("lost whole Message instead of bounded file result: kind=%s code=%s err=%v", event.Kind, event.Code, err)
						}
						if event.Message != nil {
							message = event.Message
						}
						if event.Kind == "end" {
							ended = true
						}
					}
					if !ended {
						t.Fatal("stream missing end")
					}
				} else {
					result, err := runtime.Send(t.Context(), st.reg.ID, in)
					if err != nil {
						t.Fatal("lost direct Message", err)
					}
					message = result.Message
				}
				if message == nil || message.FileError != wantFileError || message.TaskID != "" || message.ContextID != "" || len(message.Parts) == 0 || message.Parts[0].Text != "completed report" {
					t.Fatalf("Message/text/error/correlation not preserved: %+v", message)
				}
				if wantFileError {
					if len(message.Parts) != 1 {
						t.Fatal("oversized file retained")
					}
				} else if len(message.Parts) != 2 || !bytes.Equal(message.Parts[1].Raw, payload) || message.Parts[1].Download != "" || message.Parts[1].FileURL != "" {
					t.Fatal("file bytes or authority changed")
				}
				if sends.Load() != 1 || downloads.Load() != 1 {
					t.Fatalf("send/download replay: %d/%d", sends.Load(), downloads.Load())
				}
			})
		}
	}
}
