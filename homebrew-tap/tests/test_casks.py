import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("update_casks", Path(__file__).resolve().parents[1] / "scripts/update_casks.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CaskTests(unittest.TestCase):
    def manifest(self, token):
        name, _, minimum = module.APPS[token]
        return dict(version="0.4.0", build=71, architecture="arm64", minimum_macos=minimum,
                    archive=f"{name}-0.4.0-71-arm64.zip", sha256="a" * 64, bytes=123)

    def test_both_platforms_and_builds_are_pinned(self):
        for token in module.APPS:
            output = module.render(token, self.manifest(token))
            self.assertIn('version "0.4.0,71"', output)
            self.assertIn('sha256 "' + "a" * 64 + '"', output)
            self.assertIn('depends_on arch: :arm64', output)
            self.assertIn('auto_updates true', output)
            self.assertIn('ENV["HOMEBREW_MULTI_APPS_ALLOW_UNNOTARIZED"] == "1"', output)
            self.assertIn('/usr/bin/codesign', output)
            self.assertIn('/usr/bin/xattr', output)
            self.assertNotIn('zap ', output)

    def test_rejects_injected_and_mismatched_manifest_fields(self):
        for field, value in [("version", '1.0.0";system("bad")'), ("build", True),
                             ("archive", "../evil.zip"), ("sha256", "x" * 64),
                             ("architecture", "x86_64"), ("minimum_macos", "12.0"),
                             ("bytes", -1)]:
            manifest = self.manifest("multishift")
            manifest[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                module.render("multishift", manifest)


if __name__ == "__main__":
    unittest.main()
