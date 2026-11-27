import base64
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET


SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/generate-appcast.py'
NS = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
KEY = base64.b64encode(bytes(range(32))).decode()
SIGNATURE = base64.b64encode(bytes(range(64))).decode()


class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='sparkle-appcast-tests-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / '测试 & App.app'
        (self.app / 'Contents').mkdir(parents=True)
        self.info = {
            'CFBundleDisplayName': '测试 & App', 'CFBundleShortVersionString': '1.2.3',
            'CFBundleVersion': '42', 'LSMinimumSystemVersion': '13.0', 'SUPublicEDKey': KEY,
        }
        self.save_info()
        self.dmg = self.root / '测试 App & 1.2.3.dmg'
        self.dmg.write_bytes(b'final dmg bytes\x00')
        self.output = self.root / 'feed' / 'appcast.xml'
        self.signer = self.root / 'signer'
        self.verifier = self.root / 'verifier'
        self.make_signer()
        self.make_verifier()

    def save_info(self):
        (self.app / 'Contents' / 'Info.plist').write_bytes(plistlib.dumps(self.info))

    def executable(self, path, body):
        path.write_text(f'#!{sys.executable}\n' + body)
        path.chmod(0o755)

    def make_signer(self, sign_code=0, verify_code=0, signature=SIGNATURE):
        self.executable(self.signer, f'''
import sys
assert sys.argv[1:3] == ['--account', 'test-account']
if sys.argv[3] == '-p':
    assert len(sys.argv) == 5
    print({signature!r})
    sys.exit({sign_code})
assert sys.argv[3] == '--verify'
assert len(sys.argv) == 6 and sys.argv[5] == {signature!r}
sys.exit({verify_code})
''')

    def make_verifier(self, code=0):
        self.executable(self.verifier, f'''
import sys
from pathlib import Path
assert len(sys.argv) == 4
assert sys.argv[1] == {KEY!r} and sys.argv[2] == {SIGNATURE!r}
assert Path(sys.argv[3]).read_bytes() == b'final dmg bytes\\x00'
sys.exit({code})
''')

    def run_generator(self, extra=(), external=True):
        args = [sys.executable, str(SCRIPT), '--app', str(self.app), '--dmg', str(self.dmg),
                '--repo', 'Wentao-Zhao/TestApp', '--sign-tool', str(self.signer),
                '--key-account', 'test-account', '--output', str(self.output)]
        if external:
            args += ['--verify-tool', str(self.verifier)]
        return subprocess.run(args + list(extra), capture_output=True, text=True)

    def assert_failed_preserving_output(self):
        self.output.parent.mkdir(exist_ok=True)
        self.output.write_text('existing published feed')
        result = self.run_generator()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(self.output.read_text(), 'existing published feed')
        self.assertEqual(list(self.output.parent.glob('*.tmp')), [])

    def test_valid_feed_and_external_verifier_contract(self):
        result = self.run_generator()
        self.assertEqual(result.returncode, 0, result.stderr)
        item = ET.parse(self.output).find('./channel/item')
        self.assertEqual(item.findtext('title'), '测试 & App 1.2.3')
        self.assertEqual(item.findtext('sparkle:version', namespaces=NS), '42')
        self.assertEqual(item.findtext('sparkle:shortVersionString', namespaces=NS), '1.2.3')
        self.assertEqual(item.findtext('sparkle:minimumSystemVersion', namespaces=NS), '13.0')
        self.assertEqual(item.findtext('link'), 'https://github.com/Wentao-Zhao/TestApp/releases/tag/v1.2.3')
        enclosure = item.find('enclosure')
        self.assertEqual(enclosure.get('length'), str(self.dmg.stat().st_size))
        self.assertEqual(enclosure.get('type'), 'application/octet-stream')
        self.assertEqual(enclosure.get('{%s}edSignature' % NS['sparkle']), SIGNATURE)
        self.assertEqual(enclosure.get('url'), 'https://github.com/Wentao-Zhao/TestApp/releases/download/v1.2.3/%E6%B5%8B%E8%AF%95%20App%20%26%201.2.3.dmg')

    def test_signing_failure_preserves_feed(self):
        self.make_signer(sign_code=2)
        self.assert_failed_preserving_output()

    def test_signer_verification_failure_preserves_feed(self):
        self.make_signer(verify_code=3)
        self.assert_failed_preserving_output()

    def test_independent_verification_failure_preserves_feed(self):
        self.make_verifier(code=4)
        self.assert_failed_preserving_output()

    def test_malformed_metadata_rejected(self):
        for key, value in [('CFBundleShortVersionString', '1.02.3'),
                           ('CFBundleShortVersionString', '1.2.3-01'),
                           ('CFBundleVersion', '0'), ('CFBundleVersion', 3),
                           ('LSMinimumSystemVersion', '13'), ('SUPublicEDKey', 'bad')]:
            with self.subTest(key=key, value=value):
                original = self.info[key]
                self.info[key] = value
                self.save_info()
                self.assert_failed_preserving_output()
                self.info[key] = original
                self.save_info()

    def test_bad_signature_rejected(self):
        self.make_signer(signature=base64.b64encode(b'too short').decode())
        self.assert_failed_preserving_output()

    def test_wrong_repository_rejected(self):
        result = self.run_generator(extra=['--repo', 'OtherOwner/App'])
        self.assertEqual(result.returncode, 1)
        self.assertFalse(self.output.exists())

    def test_archive_changed_by_verifier_rejected(self):
        self.executable(self.verifier, 'import sys\nfrom pathlib import Path\nPath(sys.argv[3]).write_bytes(b"changed")\n')
        self.assert_failed_preserving_output()

    def test_real_crypto_checks_embedded_public_key(self):
        try:
            from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
            from cryptography.hazmat.primitives import serialization
        except ImportError:
            self.skipTest('Python cryptography unavailable')
        # Ephemeral test key remains in memory; only its public key/signature reach disk.
        key = Ed25519PrivateKey.generate()
        self.info['SUPublicEDKey'] = base64.b64encode(key.public_key().public_bytes(
            serialization.Encoding.Raw, serialization.PublicFormat.Raw)).decode()
        self.save_info()
        self.make_signer(signature=base64.b64encode(key.sign(self.dmg.read_bytes())).decode())
        result = self.run_generator(external=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.info['SUPublicEDKey'] = KEY
        self.save_info()
        result = self.run_generator(external=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn('embedded SUPublicEDKey', result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
