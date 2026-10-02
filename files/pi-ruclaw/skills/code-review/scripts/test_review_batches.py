"""Regression tests: python3 -m unittest discover -s <scripts> -p 'test_*.py'."""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("review_batches.py")


class ReviewBatchesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.git("init", "-q")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Test")
        self.put("internal/store/deleted.go", "old\n")
        self.put("internal/tools/renamed.go", "rename\n")
        self.git("add", ".")
        self.git("commit", "-qm", "base")
        self.base = self.git("rev-parse", "HEAD").strip()
        (self.repo / "internal/store/deleted.go").unlink()
        (self.repo / "internal/tools/renamed.go").rename(self.repo / "internal/tools/new.go")
        for path in ("internal/userfront/surfaces.go", "internal/store/pg/user_front_surfaces.go",
                     "internal/tools/approval_preview.go", "internal/tools/show_ui.go",
                     "ui/user-front/src/features/a2ui/catalog/n1.ts",
                     "ui/user-front/src/features/a2ui/catalog/n2-cash-calendar.ts",
                     "ui/user-front/src/features/chat/file with spaces.ts"):
            self.put(path, "new\n")
        self.git("add", "-A")
        self.git("commit", "-qm", "head")
        self.head = self.git("rev-parse", "HEAD").strip()
        self.bundle = self.repo / "bundle"
        self.bundle.mkdir()
        (self.bundle / "metadata.txt").write_text(
            f"base_sha={self.base}\nhead_sha={self.head}\nmerge_base={self.base}\n")

    def put(self, path, text):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo).decode()

    def run_script(self, *args, ok=True):
        result = subprocess.run(["python3", str(SCRIPT), str(self.bundle), *args],
                                cwd=self.repo, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0 if ok else 1, result.stdout + result.stderr)
        return result

    def manifest(self):
        return json.loads((self.bundle / "coverage.json").read_text())

    def complete(self):
        results = json.loads((self.bundle / "results.template.json").read_text())
        for batch, result in results.items():
            result["status"] = "reviewed"
            report = self.bundle / result["report"]
            report.parent.mkdir(exist_ok=True)
            report.write_text(f"Inspected {batch}: invariant and negative-path analysis.\n")
        path = self.bundle / "results.json"
        path.write_text(json.dumps(results))
        return path, results

    def test_full_coverage_including_previous_blind_spots_spaces_deletion_and_rename(self):
        self.run_script()
        manifest = self.manifest()
        assigned = [p for b in manifest["batches"] for p in b["paths"]]
        self.assertEqual(len(assigned), len(set(assigned)))
        self.assertEqual(set(assigned), set(manifest["paths"]))
        self.assertIn("internal/store/deleted.go", assigned)
        self.assertIn("internal/tools/renamed.go", assigned)
        self.assertIn("internal/tools/new.go", assigned)
        self.assertTrue(any("file with spaces" in p for p in assigned))
        self.run_script("--validate")
        path, _ = self.complete()
        self.run_script("--validate", "--results", str(path))

    def test_unknown_path_blocks_then_custom_rules_recover(self):
        self.put("unknown.xyz", "new")
        self.git("add", "unknown.xyz")
        self.git("commit", "-qm", "unknown")
        head = self.git("rev-parse", "HEAD").strip()
        (self.bundle / "metadata.txt").write_text(
            f"base_sha={self.base}\nhead_sha={head}\nmerge_base={self.base}\n")
        self.run_script(ok=False)
        self.assertEqual((self.bundle / "unassigned.txt").read_text(), "unknown.xyz\n")
        self.assertFalse((self.bundle / "lanes").exists())
        rules = self.repo / "rules.json"
        rules.write_text(json.dumps([{"lane": "audited", "pattern": ".*", "brief": "Test-only exhaustive rule"}]))
        self.run_script("--rules", str(rules))
        self.run_script("--validate")

    def test_pending_gap_and_missing_reports_block_completion(self):
        self.run_script()
        self.run_script("--results", str(self.bundle / "results.template.json"), ok=False)
        path, results = self.complete()
        first = next(iter(results))
        results[first].update(status="gap", reason="Evidence inaccessible")
        path.write_text(json.dumps(results))
        self.assertIn("INCONCLUSIVE", self.run_script("--results", str(path), ok=False).stderr)
        results[first]["status"] = "reviewed"
        path.write_text(json.dumps(results))
        (self.bundle / results[first]["report"]).unlink()
        self.run_script("--results", str(path), ok=False)

    def test_duplicate_assignment_and_tampered_evidence_block(self):
        self.run_script()
        manifest = self.manifest()
        manifest["batches"].append(manifest["batches"][0])
        (self.bundle / "coverage.json").write_text(json.dumps(manifest))
        self.run_script("--validate", ok=False)
        manifest["batches"].pop()
        (self.bundle / "coverage.json").write_text(json.dumps(manifest))
        patch = self.bundle / "lanes" / manifest["batches"][0]["id"] / "diff.patch"
        patch.write_text("tampered")
        self.run_script("--validate", ok=False)

    def test_limits_oversized_and_no_stale_reruns(self):
        self.run_script("--max-files", "1", "--max-bytes", "1")
        self.assertTrue(all(len(b["paths"]) == 1 and b["oversized"] for b in self.manifest()["batches"]))
        self.run_script("--validate")
        self.run_script(ok=False)

    def test_bundle_helper_freezes_snapshot_and_refuses_reuse(self):
        helper = SCRIPT.with_name("prepare-review-bundle.sh")
        output = self.repo / "fresh bundle"
        command = ["bash", str(helper), self.base, self.head, str(output)]
        result = subprocess.run(command, cwd=self.repo, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        files = (output / "files.txt").read_text().splitlines()
        self.assertIn("internal/tools/renamed.go", files)
        self.assertIn("internal/tools/new.go", files)
        self.assertEqual(self.git("-C", str(output / "head-tree"), "rev-parse", "HEAD").strip(), self.head)
        metadata = (output / "metadata.txt").read_bytes()
        result = subprocess.run(command, cwd=self.repo, text=True, capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual((output / "metadata.txt").read_bytes(), metadata)

    def test_snapshot_mismatch_blocks(self):
        self.run_script()
        manifest = self.manifest()
        manifest["head"] = self.base
        (self.bundle / "coverage.json").write_text(json.dumps(manifest))
        self.run_script("--validate", ok=False)


if __name__ == "__main__":
    unittest.main()
