import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class ChatTaskAccessibilityTests(unittest.TestCase):
    def test_identifiers_are_on_disclosure_labels_not_ancestor_containers(self):
        source = (ROOT / "JarvisEVO/UI/ChatLocalTasksView.swift").read_text()
        self.assertNotIn('}.accessibilityIdentifier("chat.task.list")', source)
        self.assertNotIn('}.accessibilityIdentifier("chat.task.card.', source)
        self.assertIn('Text("Local tasks in this conversation (\\(records.count))")', source)
        self.assertIn('Text("\\(event.name): \\(event.outcome)")', source)
        self.assertIn('.accessibilityIdentifier("chat.task.records")', source)
        self.assertIn('.accessibilityIdentifier("chat.task.inspect.', source)
        self.assertIn('.accessibilityIdentifier("chat.task.evidence.', source)

if __name__ == "__main__": unittest.main()
