"""Structural guard only; exact native accessibility acceptance is still required."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class PrecisionLocator(unittest.TestCase):
 def test_existing_disclosure_is_preserved(self):
  s=(ROOT/'JarvisEVO/UI/ModelManagerView.swift').read_text()
  self.assertIn('DisclosureGroup {',s)
  self.assertIn('} label: {\n                                    Text("More download options")\n                                        .accessibilityIdentifier("model.variants.\\(first.id)")\n                                }',s)
  self.assertIn('ForEach(Array(group.entries.dropFirst()))',s)
 def test_actual_q5_action_and_precision_are_required_after_expand(self):
  s=(ROOT/'UITests/ModelCatalogUITests.swift').read_text()
  self.assertIn('app.buttons["model.download.qwen2.5-0.5b-instruct-q5_k_m"]',s)
  self.assertIn('XCTAssertTrue(variant.isHittable)',s)
  self.assertIn('XCTAssertTrue(precision.isHittable)',s)
  self.assertIn('Q5_K_M',s)
  self.assertIn('XCTAssertFalse(variant.exists',s)
 def test_online_refresh_is_revealed_without_network_action(self):
  s=(ROOT/'UITests/ModelCatalogUITests.swift').read_text()
  self.assertIn('reveal(refresh, in: app.collectionViews.firstMatch)',s)
  self.assertIn('XCTAssertTrue(refresh.isHittable)',s)
  self.assertNotIn('refresh.tap()',s)
if __name__=='__main__': unittest.main()
