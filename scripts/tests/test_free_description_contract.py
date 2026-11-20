"""Editorial contract only; native provider suite remains required."""
import pathlib,re,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class DescriptionContract(unittest.TestCase):
 def test_reviewed_profiles_distinct_and_unknown_explicitly_unreviewed(self):
  s=(ROOT/'JarvisEVO/Providers/OpenRouterFreeProvider.swift').read_text()
  profile=s.split('private var profile: Profile {')[1].split('var suggestedUses:')[0]
  notes=re.findall(r'note: "([^"]*)"',profile)
  self.assertEqual(len(notes),13)
  self.assertEqual(len(set(notes[:12])),12)
  self.assertIn('not reviewed',notes[-1])
  self.assertIn('uses: [.everyday, .writing]',profile.split('default:')[1])
 def test_hostile_marketing_uses_reviewed_coding_fixture_and_unknown_slug_stays_general(self):
  s=(ROOT/'Tests/OpenRouterFreeProviderTests.swift').read_text().split('func testDisplayCopyDoesNotTrustProviderDescription()')[1].split('func testCompletion')[0]
  self.assertIn('row("particle-ai/particle-1:free")',s)
  self.assertIn('row("example/coder:free")',s)
  self.assertIn('XCTAssertFalse(unknown.suggestedUses.contains(.coding))',s)
  self.assertIn('XCTAssertFalse(model.shortDescription.contains("evil"))',s)
if __name__=='__main__': unittest.main()
