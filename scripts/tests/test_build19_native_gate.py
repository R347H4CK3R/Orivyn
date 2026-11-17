"""Exact native gate composition contract; not evidence that XCTest ran."""
import ast
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]

class Build19NativeGateTests(unittest.TestCase):
    def test_gate_requires_all_299_selected_tests_without_failures_or_skips(self):
        script = (ROOT / 'scripts/ci_archive_restore.sh').read_text()
        expected = ast.literal_eval(re.search(r'^expected=(\{[^\n]+\})$', script, re.M).group(1))
        self.assertEqual(expected, {'totalTestCount': 299, 'passedTests': 299, 'failedTests': 0, 'skippedTests': 0})
        selectors = re.findall(r'-only-testing:([\w/]+)', script)
        self.assertEqual(len(selectors), len(set(selectors)))
        total = 0
        for selector in selectors:
            parts = selector.split('/')
            directory = ROOT / ('UITests' if parts[0] == 'JarvisEVOUITests' else 'Tests')
            matches = []
            for path in directory.glob('*.swift'):
                text = path.read_text()
                classes = list(re.finditer(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', text))
                for index, match in enumerate(classes):
                    if match.group(1) == parts[1]:
                        end = classes[index + 1].start() if index + 1 < len(classes) else len(text)
                        methods = re.findall(r'\bfunc\s+(test\w*)\s*\(', text[match.end():end])
                        matches.append(methods)
            self.assertEqual(len(matches), 1, selector)
            if len(parts) == 3:
                self.assertIn(parts[2], matches[0])
                total += 1
            else:
                total += len(matches[0])
        self.assertEqual(total, 299)
        self.assertIn('assert type(s.get(k)) is int and s[k]==v', script)
        self.assertNotIn('-skip-testing:', script)

    def test_post_read_probe_distinguishes_rejection_from_answering(self):
        source = (ROOT / 'Tests/ProductionNormalChatLocalAgentTests.swift').read_text()
        self.assertIn('if let infoError { throw infoError }', source)
        self.assertIn('XCTAssertEqual(infoEvidence.reads.count, 1', source)
        self.assertIn('XCTAssertEqual(infoEvidence.requests.count, 1', source)
