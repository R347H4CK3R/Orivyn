"""Structural UX contracts only; no claim of SwiftUI rendering/device testing."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class ReviewedPlanDiscoveryTests(unittest.TestCase):
    def test_recommended_reviewed_path_is_primary(self):
        ui=(ROOT/'JarvisEVO/UI/LocalAgentView.swift').read_text()
        self.assertIn('Section("Recommended: reviewed conversation task")',ui)
        self.assertIn('Button("Draft plan for review") { session?.prepareReadPlan(goal: goal, kind: planKind) }',ui)
        self.assertIn('.buttonStyle(.borderedProminent)',ui)
        self.assertLess(ui.index('agent.plan.draft'),ui.index('DisclosureGroup {'))
    def test_generic_creation_is_explicit_not_silent_routing(self):
        ui=(ROOT/'JarvisEVO/UI/LocalAgentView.swift').read_text()
        group=ui[ui.index('DisclosureGroup {'):ui.index('if let setupError')]
        self.assertIn('session?.create(goal: goal)',group)
        self.assertIn('answer after a search without reading the message',group)
        self.assertIn('agent.create',group)
        self.assertNotIn('prepareReadPlan',group)
    def test_disclosure_identifier_is_on_label_not_ancestor(self):
        ui=(ROOT/'JarvisEVO/UI/LocalAgentView.swift').read_text()
        self.assertNotIn('}.accessibilityIdentifier("agent.experimental.options")',ui)
        self.assertIn('} label: {\n                    Text("Other local tasks · experimental")\n                        .accessibilityIdentifier("agent.experimental.options")',ui)
        test=(ROOT/'UITests/LocalAgentIntegrationUITests.swift').read_text()
        self.assertLess(test.index('XCTAttachment(string: app.debugDescription)'),test.index('let create ='))
    def test_saved_generic_records_keep_visible_limitation(self):
        ui=(ROOT/'JarvisEVO/UI/LocalAgentView.swift').read_text()
        warning=ui.index('This experimental task has no approved completion checklist.')
        self.assertLess(warning,ui.index('LabeledContent("State"'))
        self.assertIn('agent.unreviewedWarning',ui)
        self.assertIn('Draft a new reviewed plan above',ui)
    def test_saved_task_ui_regression_opens_disclosure_before_create(self):
        test=(ROOT/'UITests/LocalAgentIntegrationUITests.swift').read_text()
        self.assertLess(test.index('experimental.tap()'),test.index('let create ='))
        self.assertIn('agent.experimental.options',test)
        self.assertIn('agent.unreviewedWarning',test)
        self.assertIn('Resume is explicit',test)
    def test_existing_generic_real_model_gate_remains_distinct(self):
        test=(ROOT/'Tests/ProductionLocalAgentSessionTests.swift').read_text()
        self.assertIn('session.create(goal: goal)',test)
        self.assertIn('search_conversations',test)
        self.assertIn('read_conversation',test)
        self.assertIn('Answer must copy the unpredictable stored marker',test)
        self.assertNotIn('prepareReadPlan',test)
