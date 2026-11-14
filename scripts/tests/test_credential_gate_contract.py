import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class CredentialGateContractTests(unittest.TestCase):
    def test_native_gate_selects_credential_intent_suite(self):
        self.assertIn('-only-testing:JarvisEVOTests/RemoteCredentialIntentTests', (ROOT/'scripts/run_virtual_desktop_gate.sh').read_text())

    def test_native_gate_selects_credential_draft_lifecycle(self):
        self.assertIn('-only-testing:JarvisEVOUITests/RemoteCredentialDraftUITests', (ROOT/'scripts/run_virtual_desktop_gate.sh').read_text())

    def test_settings_never_preloads_saved_secret_and_observes_byte_identity(self):
        source = (ROOT/'JarvisEVO/UI/SettingsView.swift').read_text().split('struct RemoteSettingsView: View {',1)[1].split('struct MemoryView:',1)[0]
        self.assertNotIn('KeychainService.read', source)
        self.assertIn('.onChange(of: Data(RemoteCredentialIntent.normalizedEndpoint(baseURL).utf8))', source)
        self.assertIn('Binding(get: { baseURL }, set: { value in', source)
        self.assertIn('if !RemoteCredentialIntent.sameEndpoint(baseURL, value)', source)
