import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("release_manifest", Path(__file__).parents[2] / "scripts/release_manifest.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class AcceptanceTests(unittest.TestCase):
    def test_acceptance_is_invalid_after_artifact_replacement(self):
        with tempfile.TemporaryDirectory() as root:
            artifact = Path(root) / "app.dmg"
            artifact.write_bytes(b"candidate A")
            manifest = m.create("MultiShift", "0.3.0", "65", "a" * 40, "beta", "14.0", artifact)
            acceptance = dict(candidate_id=manifest["candidate_id"], reviewer="owner", reviewed_at="2026-11-01", checks={key: "passed" for key in m.REQUIRED})
            m.verify(manifest, artifact, acceptance)
            artifact.write_bytes(b"candidate B")
            with self.assertRaises(ValueError):
                m.verify(manifest, artifact, acceptance)

    def test_missing_real_update_check_blocks_publication(self):
        with tempfile.TemporaryDirectory() as root:
            artifact = Path(root) / "app.dmg"
            artifact.write_bytes(b"candidate")
            manifest = m.create("MultiShift", "0.3.0", "65", "a" * 40, "beta", "14.0", artifact)
            acceptance = dict(candidate_id=manifest["candidate_id"], reviewer="owner", reviewed_at="2026-11-01", checks={key: "passed" for key in m.REQUIRED - {"update_a_to_b"}})
            with self.assertRaises(ValueError):
                m.verify(manifest, artifact, acceptance)

if __name__ == "__main__":
    unittest.main()
