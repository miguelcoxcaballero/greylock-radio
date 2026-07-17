import lzma
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


WRITER = Path(__file__).resolve().parents[1] / "tools" / "write_image.py"


class ImageWriterTestCase(unittest.TestCase):
    def test_deferred_header_produces_an_identical_image(self):
        payload = bytes(range(256)) * 65536
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            compressed = root / "test.img.xz"
            destination = root / "target.img"
            with lzma.open(compressed, "wb") as handle:
                handle.write(payload)
            destination.write_bytes(b"\0" * len(payload))

            subprocess.run(
                [sys.executable, str(WRITER), str(compressed), str(destination), "--defer-header", "4194304"],
                check=True,
                capture_output=True,
                text=True,
            )

            self.assertEqual(destination.read_bytes(), payload)


if __name__ == "__main__":
    unittest.main()
