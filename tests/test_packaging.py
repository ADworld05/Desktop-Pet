"""Packaging boundary tests; no compiler, Godot, registry or live data required."""
from pathlib import Path
import shutil
import re
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from build_windows import check_distribution, prepare_release, publish_local, distribution_names, GUIDES


class PackagingTests(unittest.TestCase):
    def setUp(self):
        build = ROOT / ".build"
        build.mkdir(exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix="packaging-test-", dir=build))

    def tearDown(self):
        if not self.root.resolve().is_relative_to((ROOT / ".build").resolve()):
            raise RuntimeError("Refusing cleanup outside the owned test directory")
        shutil.rmtree(self.root)

    def test_existing_release_is_preserved(self):
        release = self.root / "dist/test"
        release.mkdir(parents=True)
        note = release / "unrelated-note.txt"
        note.write_text("SYNTHETIC keep this", encoding="utf-8")
        with self.assertRaises(FileExistsError):
            prepare_release(self.root, "test")
        self.assertEqual(note.read_text(encoding="utf-8"), "SYNTHETIC keep this")

    def test_every_build_gets_a_fresh_stage(self):
        first, _ = prepare_release(self.root, "test")
        (first / "unrelated-note.txt").write_text("SYNTHETIC", encoding="utf-8")
        second, _ = prepare_release(self.root, "test")
        self.assertNotEqual(first, second)
        self.assertEqual(list(second.iterdir()), [])

    def test_stray_distribution_file_is_rejected(self):
        folder = self.root / "app"
        folder.mkdir()
        (folder / "runtime.txt").write_text("SYNTHETIC", encoding="utf-8")
        (folder / "unrelated-note.txt").write_text("SYNTHETIC", encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "unrelated-note"):
            check_distribution(folder, {"runtime.txt"})

    def test_missing_distribution_file_is_rejected(self):
        with self.assertRaises(RuntimeError):
            check_distribution(self.root, {"required.txt"})

    def test_complete_stage_is_published_without_merging(self):
        stage, destination = prepare_release(self.root, "test")
        (stage / "marker.txt").write_text("SYNTHETIC", encoding="utf-8")
        publish_local(stage, destination, self.root)
        self.assertFalse(stage.exists())
        self.assertTrue((destination / "marker.txt").is_file())

    def test_publish_refuses_existing_destination(self):
        stage, destination = prepare_release(self.root, "test")
        destination.mkdir(parents=True)
        with self.assertRaises(FileExistsError):
            publish_local(stage, destination, self.root)
        self.assertTrue(stage.exists())

    def test_publish_refuses_unowned_stage(self):
        with self.assertRaises(ValueError):
            publish_local(self.root, self.root / "dist/test", self.root)

    def test_packaged_guides_keep_their_relative_links(self):
        expected = distribution_names()
        for name in GUIDES:
            if not name.endswith('.md'):
                continue
            text = (ROOT / name).read_text(encoding='utf-8')
            targets = re.findall(r'!?\[[^\]]*\]\(([^)]+)\)', text)
            targets += re.findall(r'<img[^>]+src="([^"]+)"', text)
            for target in targets:
                target = target.split('#', 1)[0]
                if not target or re.match(r'\w+://', target):
                    continue
                with self.subTest(guide=name, target=target):
                    self.assertIn((Path(name).parent / target).as_posix(), expected)


if __name__ == "__main__":
    unittest.main()
