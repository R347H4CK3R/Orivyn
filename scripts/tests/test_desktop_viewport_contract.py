"""Structural regression guard; native UI geometry remains the runtime gate."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class DesktopViewportContract(unittest.TestCase):
    def test_viewport_has_compact_height_floor_in_scrollable_workspace(self):
        source = (ROOT / "JarvisEVO/UI/VirtualDesktopView.swift").read_text()
        self.assertIn("GeometryReader { geometry in", source)
        self.assertIn("max(180, availableHeight * 0.45)", source)
        self.assertIn(".frame(height: viewportHeight(in: geometry.size))", source)
        self.assertIn('accessibilityIdentifier("desktop.controls")', source)

    def test_input_focus_is_explicit_and_dismissible(self):
        source = (ROOT / "JarvisEVO/UI/VirtualDesktopView.swift").read_text()
        self.assertIn("@FocusState private var inputFocused: Bool", source)
        self.assertIn(".focused($inputFocused)", source)
        self.assertIn('Button("Hide keyboard")', source)
        self.assertIn("inputFocused = false", source)
