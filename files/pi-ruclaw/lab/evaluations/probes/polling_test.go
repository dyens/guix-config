package a2abroker

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"ruclaw/internal/credbroker/testinfra"
)

// The second physical poll is gated. Its start is an ordering barrier, not a
// latency guess: the first working snapshot must already have been delivered.
func TestQualityPollingProgressBeforeRelease(t *testing.T) {
	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	defer cancel()
	release := make(chan struct{})
	var once sync.Once
	unblock := func() { once.Do(func() { close(release) }) }
	defer unblock()
	secondStarted, working, done := make(chan struct{}), make(chan struct{}), make(chan error, 1)
	var polls atomic.Int32
	var workingOnce sync.Once
	var origin string
	origin, roots, _ := testinfra.PrivateTLS(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/card" {
			_ = json.NewEncoder(w).Encode(wireCard(origin, JSONRPC))
			return
		}
		if r.URL.Path != "/rpc" {
			t.Error("unexpected endpoint")
			return
		}
		var request struct {
			ID     json.RawMessage `json:"id"`
			Method string          `json:"method"`
		}
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			t.Error(err)
			return
		}
		if request.Method != "GetTask" {
			t.Errorf("poll mutated partner: %s", request.Method)
			return
		}
		n := polls.Add(1)
		state := "TASK_STATE_WORKING"
		if n >= 2 {
			if n == 2 {
				close(secondStarted)
			}
			select {
			case <-release:
			case <-r.Context().Done():
				return
			}
			state = "TASK_STATE_COMPLETED"
		}
		_, _ = fmt.Fprintf(w, `{"jsonrpc":"2.0","id":%s,"result":{"id":"task","contextId":"context","status":{"state":%q}}}`, request.ID, state)
	}))
	st := &runtimeStore{reg: Registration{ID: "reg", Policy: Policy{CardURL: origin + "/card", EndpointURL: origin + "/rpc", Binding: JSONRPC, Protocol: "1.0", ServiceIdentity: "quality"}}, token: "runtime", bearer: "SECRET"}
	broker := New(st, roots)
	go func() {
		completed := false
		for event, err := range broker.WaitStream(ctx, "reg", "runtime", waitRequest(5000)) {
			if err != nil {
				done <- err
				return
			}
			if event.Task != nil && event.Task.State == "working" {
				workingOnce.Do(func() { close(working) })
			}
			if event.Task != nil && event.Task.State == "completed" {
				completed = true
			}
		}
		if !completed {
			done <- fmt.Errorf("no completed snapshot")
			return
		}
		done <- nil
	}()
	// Join before testinfra's server cleanup: cancellation must release active GET.
	defer func() {
		cancel()
		unblock()
		select {
		case <-done:
		case <-time.After(3 * time.Second):
			t.Error("poll iterator did not settle")
		}
	}()
	select {
	case <-working:
	case <-secondStarted:
		select {
		case <-working:
		default:
			t.Error("first working snapshot withheld while second physical poll is blocked")
		}
	case err := <-done:
		// Put back for the deferred join.
		done <- err
		t.Fatalf("iterator ended before gated progress: %v", err)
	case <-ctx.Done():
		t.Fatal("gated poll not reached")
	}
	unblock()
	select {
	case err := <-done:
		done <- err
		if err != nil {
			t.Fatal(err)
		}
	case <-ctx.Done():
		t.Fatal("iterator did not complete after release")
	}
	if polls.Load() != 2 {
		t.Fatalf("physical polls=%d want=2", polls.Load())
	}
}
