package agent

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"ruclaw/internal/guardrail"
	"ruclaw/internal/providers"
	"ruclaw/internal/store"
	"ruclaw/internal/tools"
)

// Consumer regression shared by both candidates, using their common document_ids
// API. This is not an A2A ingestion or deployed User Front delivery test.
type qualitySelectionGuard struct {
	*recordingGuardrailEngine
	deny      bool
	decisions int
}

func (g *qualitySelectionGuard) Evaluate(ctx context.Context, hook guardrail.HookPoint, in *guardrail.GuardrailInput) (*guardrail.GuardrailDecision, error) {
	if hook == guardrail.HookAfterTool && in.ToolName == "finalize_attachments" {
		g.decisions++
		if g.deny {
			return &guardrail.GuardrailDecision{Blocked: true, BlockMessage: "quality probe deny"}, nil
		}
	}
	return g.recordingGuardrailEngine.Evaluate(ctx, hook, in)
}
func TestQualityFinalSelectionAfterTool(t *testing.T) {
	for _, mode := range []string{"allow", "deny", "intermediate"} {
		t.Run(mode, func(t *testing.T) {
			agentID, ownerID, tenantID, docID := uuid.New(), uuid.New(), uuid.New(), uuid.New()
			owner := ownerID.String()
			docs := &captureFinalArtifactStore{docs: map[string]*store.Document{docID.String(): {ID: docID.String(), AgentID: agentID.String(), UserID: &owner, Filename: "report.pdf", Format: store.FormatPDF, CurrentRev: 1, SizeBytes: 10}}}
			provider := &scriptedProvider{}
			if mode != "intermediate" {
				provider.responses = append(provider.responses, &providers.ChatResponse{ToolCalls: []providers.ToolCall{{ID: "select-file", Name: "finalize_attachments", Arguments: map[string]any{"document_ids": []any{docID.String()}}}}})
			}
			provider.responses = append(provider.responses, finalResponse("Done."))
			loop := NewLoop(LoopConfig{ID: "default", AgentUUID: agentID, Provider: provider, Model: "test-model", Tools: tools.NewRegistry(), Sessions: newMemNoticeSessionStore(), Workspace: t.TempDir(), InjectionAction: StaticInjectionAction("off"), DocStore: docs})
			guard := &qualitySelectionGuard{recordingGuardrailEngine: newRecordingGuardrailEngine(), deny: mode == "deny"}
			loop.guardrailEngine = guard
			result, err := loop.Run(t.Context(), RunRequest{SessionKey: "quality-final-selection", Message: "return report", RunID: uuid.NewString(), UserID: owner, IAMUserID: ownerID, TenantID: &tenantID, ExternalTerminalCommit: true, FinalAttachments: NewFinalAttachmentCollector()})
			wantDecisions := 1
			if mode == "intermediate" {
				wantDecisions = 0
			}
			if guard.decisions != wantDecisions {
				t.Fatalf("acceptance boundary not exercised: decisions=%d want=%d err=%v", guard.decisions, wantDecisions, err)
			}
			if err != nil {
				t.Fatalf("unexpected run failure: %v", err)
			}
			if result == nil {
				t.Fatal("missing result")
			}
			if mode == "allow" {
				if len(result.FinalAttachmentIDs) != 1 || result.FinalAttachmentIDs[0] != docID {
					t.Fatalf("allowed selection missing: %v", result.FinalAttachmentIDs)
				}
			} else if len(result.FinalAttachmentIDs) != 0 {
				t.Fatalf("%s kept forbidden/unselected final attachment IDs: %v", mode, result.FinalAttachmentIDs)
			}
		})
	}
}
