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

    def test_form_task_buttons_do_not_share_automatic_row_action(self):
        source = (ROOT / "JarvisEVO/UI/LocalAgentView.swift").read_text()
        controls = source.split('Button(task.status == "interrupted" ? "Resume" : "Run")', 1)[1].split('Button("Archive task")', 1)[0]
        self.assertIn('.buttonStyle(.borderless)', controls)
        self.assertIn('session.stop(cancelTask: true)', controls)
        self.assertIn('session.stop(cancelTask: false)', controls)

if __name__ == "__main__": unittest.main()
