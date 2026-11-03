"""Offline release-builder guards; no game libraries are loaded."""
import importlib.util, json, tempfile, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('builder', ROOT/'tools/build_release.py')
b = importlib.util.module_from_spec(spec); spec.loader.exec_module(b)

class BuildGuards(unittest.TestCase):
    def test_token_edits_preserve_line_boundaries(self):
        source = 'define void @main() {\n  %1 = fadd float 1.0, 2.0\n}\n'
        tok = b.tokens(source)
        self.assertEqual(''.join(tok), source)
        self.assertEqual(sum((b.tokens(l) for l in source.splitlines(keepends=True)), []), tok)
        at = tok.index('fadd')
        self.assertEqual(b.edits(tok, [[at,at+1,'fmul']], False), source.replace('fadd','fmul'))

    def test_reject_overlapping_edits(self):
        with self.assertRaises(RuntimeError): b.edits(b'abcdef', [[2,4,'00'],[3,5,'00']])

    def test_verify_rejects_changed_and_extra_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); f = root/'sample'; f.write_bytes(b'expected')
            lock = {'files': {'sample': {'size':8,'sha256':b.sha(b'expected')}}}
            b.verify(root,lock)
            f.write_bytes(b'unwanted')
            with self.assertRaises(RuntimeError): b.verify(root,lock)
            f.write_bytes(b'expected'); (root/'probe.log').write_text('extra')
            with self.assertRaises(RuntimeError): b.verify(root,lock)

    def test_release_manifest_and_recipes_agree(self):
        lock = json.loads((ROOT/'release/1.0.2.json').read_text())
        mr = json.loads((ROOT/'release/material-recipes.json').read_text())
        br = json.loads((ROOT/'release/bundle-recipes.json').read_text())
        rows = mr['materials'] + br['bundles']
        self.assertEqual(len(rows),392); self.assertEqual(len(lock['files']),410)
        self.assertEqual(len({r['path'] for r in rows}),392)
        for r in rows: self.assertEqual(r['sha256'], lock['files'][r['path']]['sha256'])

if __name__ == '__main__': unittest.main()
