import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class UIFailureFixtureContract(unittest.TestCase):
    def test_unavailable_cases_are_explicit_not_environment_dependent(self):
        fixture=(ROOT/'JarvisEVO/UI/RootViewRegressionFixtures.swift').read_text()
        tests=(ROOT/'UITests/JarvisEVOUITests.swift').read_text()
        self.assertIn('mode == "unavailable-provider"',fixture)
        self.assertIn('provider: nil',fixture)
        self.assertIn('launchUnavailableProviderFixture()',tests)
        self.assertNotIn('throw XCTSkip',tests)
    def test_import_selects_policy_then_cancels_real_picker(self):
        tests=(ROOT/'UITests/JarvisEVOUITests.swift').read_text()
        self.assertIn('app.buttons["Add missing only (keep local)"]',tests)
        self.assertIn('reveal(importButton',tests)
        self.assertIn('NSPredicate(format: "exists == false")', tests)
        self.assertIn('app.navigationBars.matching(NSPredicate(', tests)
        self.assertIn('pickerNavigation.buttons["Cancel"]', tests)
        self.assertIn('XCTAssertTrue(app.buttons["settings.done"].isHittable)', tests)
    def test_catalog_scrolls_to_lazy_search_and_back_to_active_cancel(self):
        tests=(ROOT/'UITests/ModelCatalogUITests.swift').read_text()
        self.assertIn('reveal(search, in:',tests)
        self.assertIn('reveal(cancel, in:',tests)
