import hashlib, importlib.util, pathlib, tempfile, unittest
P = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('verify_pair', P/'verify_pair.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
class PairTests(unittest.TestCase):
    def test_regular_exact_bytes(self):
        with tempfile.TemporaryDirectory() as d:
            p=pathlib.Path(d)/'model'; p.write_bytes(b'abc')
            module.verify_file(p, 3, hashlib.sha256(b'abc').hexdigest())
    def test_corruption_and_size(self):
        with tempfile.TemporaryDirectory() as d:
            p=pathlib.Path(d)/'model'; p.write_bytes(b'abc')
            for size, digest in [(2, hashlib.sha256(b'abc').hexdigest()), (3, '0'*64)]:
                with self.assertRaises(ValueError): module.verify_file(p,size,digest)
    def test_symlink_refused(self):
        with tempfile.TemporaryDirectory() as d:
            p=pathlib.Path(d)/'model'; p.write_bytes(b'abc'); link=pathlib.Path(d)/'link'; link.symlink_to(p)
            with self.assertRaises((ValueError, OSError)): module.verify_file(link,3,hashlib.sha256(b'abc').hexdigest())
if __name__=='__main__': unittest.main()
