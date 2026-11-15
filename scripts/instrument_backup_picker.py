#!/usr/bin/env python3
"""Add opt-in DEBUG diagnostics to disposable simulator comparison checkouts only."""
from pathlib import Path
import argparse


def instrument(root):
    path = root / 'JarvisEVO/UI/SettingsView.swift'
    source = path.read_text()
    start = source.index('private struct HistoryImportView: View {')
    end = source.index('\nstruct HistoryDocument:', start)
    body = source[start:end]
    assert 'pickerTrace' not in body, 'Never apply instrumentation twice'
    helper = '''
    private func pickerTrace(_ event: String) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["ORIVYN_PICKER_TRACE"] == "1" {
            print("ORIVYN_PICKER_TRACE event=\\(event) presented=\\(importingHistory) policy=\\(importPolicy)")
        }
        #endif
    }
'''
    body = body.replace('    var body: some View {', helper + '\n    var body: some View {', 1)
    if 'confirmation.beginSelection' in body:
        body = body.replace('guard confirmation.beginSelection(policy: importPolicy) != nil else { return }',
                            'pickerTrace("choose.before")\n                    guard confirmation.beginSelection(policy: importPolicy) != nil else { pickerTrace("choose.rejected"); return }')
        body = body.replace('guard let selectionID, let policy = confirmation.finishSelection(selectionID) else { return }',
                            'pickerTrace("callback.received")\n            guard let selectionID, let policy = confirmation.finishSelection(selectionID) else { pickerTrace("callback.stale"); return }\n            pickerTrace("callback.accepted")')
        body = body.replace('.onAppear { confirmation.activate() }', '.onAppear { pickerTrace("appear"); confirmation.activate() }')
        body = body.replace('.onDisappear {\n            confirmation.invalidate()', '.onDisappear {\n            pickerTrace("disappear")\n            confirmation.invalidate()')
    else:
        assert 'Button("Choose backup file…") { importingHistory = true }' in body
        body = body.replace('Button("Choose backup file…") { importingHistory = true }',
                            'Button("Choose backup file…") { pickerTrace("choose.before"); importingHistory = true; pickerTrace("choose.after") }')
        body = body.replace('            switch result {', '            pickerTrace("callback.received")\n            switch result {', 1)
        marker = '\n    }\n}'
        assert body.count(marker) == 1
        body = body.replace(marker, '\n        .onAppear { pickerTrace("appear") }\n        .onDisappear { pickerTrace("disappear") }' + marker)
    body = body.replace('.navigationTitle("Import backup")', '.onChange(of: importingHistory) { _, _ in pickerTrace("binding.changed") }\n        .navigationTitle("Import backup")')
    path.write_text(source[:start] + body + source[end:])
    test = root / 'UITests/JarvisEVOUITests.swift'
    source = test.read_text()
    assert 'ORIVYN_PICKER_TRACE' not in source
    source = source.replace('        app.launch()\n', '        app.launchEnvironment["ORIVYN_PICKER_TRACE"] = "1"\n        app.launch()\n', 1)
    marker = '    private func launchUnavailableProviderFixture() {'
    source = source.replace(marker, '''    override func tearDown() async throws {
        print("ORIVYN_PICKER_AX_END\\n" + app.debugDescription)
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Picker comparison final screen"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

''' + marker, 1)
    test.write_text(source)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    instrument(parser.parse_args().root)
