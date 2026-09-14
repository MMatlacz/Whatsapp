import importlib.util
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("validate_json_files", ROOT / "scripts" / "validate_json_files.py")
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class ValidateJsonFilesTests(unittest.TestCase):
    def test_validates_every_supplied_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            first = root / "first.json"
            second = root / "second.json"
            third = root / "third.json"
            first.write_text('{"ok": true}', encoding="utf-8")
            second.write_text('{"also": [1, 2, 3]}', encoding="utf-8")
            third.write_text('{"broken":', encoding="utf-8")

            self.assertEqual(MODULE.validate([str(first), str(second)]), 0)
            self.assertEqual(MODULE.validate([str(first), str(second), str(third)]), 1)

    def test_validation_never_treats_later_path_as_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            first = root / "first.json"
            second = root / "second.json"
            first.write_text('{"first": 1}', encoding="utf-8")
            second_contents = '{"second": 2}'
            second.write_text(second_contents, encoding="utf-8")

            self.assertEqual(MODULE.validate([str(first), str(second)]), 0)
            self.assertEqual(second.read_text(encoding="utf-8"), second_contents)

    def test_missing_or_invalid_file_fails_but_other_inputs_are_still_read(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            valid = root / "valid.json"
            invalid = root / "invalid.json"
            valid.write_text('{"ok": true}', encoding="utf-8")
            invalid.write_text('not-json', encoding="utf-8")

            self.assertEqual(MODULE.validate([str(invalid), str(root / "missing.json"), str(valid)]), 1)


if __name__ == "__main__":
    unittest.main()
