import XCTest

/// Real network weights, real SHA-256 installation and real shared llama engine.
/// No provider fixtures or alternate production paths. Run in the bounded real gate.
@MainActor
final class AutomaticRealInferenceUITests: XCTestCase {
    func testActualGeneralCoderDownloadSwitchAndRelaunch() {
        continueAfterFailure = false
        executionTimeAllowance = 600
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-test-storage"]
        app.launch()
        let input = app.textViews["composer.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        app.buttons["model.choose"].tap()
        let automatic = app.switches["model.automatic"]
        XCTAssertTrue(automatic.switches.firstMatch.exists)
        automatic.switches.firstMatch.tap()
        XCTAssertEqual(automatic.value as? String, "1")
        XCTAssertEqual(app.switches["model.automatic.cellular"].value as? String, "0")
        app.buttons["model.done"].tap()

        send("What is the capital of France? Answer in one short sentence.", app: app)
        let general = finishedResponse(app: app, timeout: 210)
        XCTAssertTrue(general.lowercased().contains("paris"), "The downloaded general model must produce a genuine useful reply.")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Automatic: Qwen 2.5 · 0.5B")).firstMatch.exists)
        capture("Automatic real general-model response", app: app)

        newConversation(app: app)
        send("Write a Python statement that prints 2 + 2. Return only the code.", app: app)
        let coder = finishedResponse(app: app, timeout: 210)
        capture("Automatic coder output before quality assertion", app: app)
        let output = XCTAttachment(string: coder); output.name = "Actual coder response"; output.lifetime = .keepAlways; add(output)
        XCTAssertTrue(coder.lowercased().contains("print"), "The downloaded coder must actually generate Python code.")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Automatic: Qwen 2.5 Coder · 1.5B")).firstMatch.exists)
        capture("Automatic real coder-model response", app: app)

        app.terminate(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "assistant.response").firstMatch.waitForExistence(timeout: 10))
        app.buttons["model.choose"].tap()
        XCTAssertEqual(app.switches["model.automatic"].value as? String, "1")
        let list = app.descendants(matching: .any).matching(identifier: "model.list").firstMatch
        for id in ["qwen2.5-0.5b-instruct-q4_k_m", "qwen2.5-coder-1.5b-instruct-q4_k_m"] {
            reveal(app.staticTexts["model.catalog.name.\(id)"], in: list)
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "model.installed.\(id)").firstMatch.exists)
        }
        app.buttons["model.done"].tap()
        newConversation(app: app)
        send("What is the capital of France? Answer in one short sentence.", app: app)
        let switchedBack = finishedResponse(app: app, timeout: 90)
        XCTAssertTrue(switchedBack.lowercased().contains("paris"))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Automatic: Qwen 2.5 · 0.5B")).firstMatch.exists)
        capture("Automatic installed-model switch after relaunch", app: app)
    }

    private func newConversation(app: XCUIApplication) {
        app.buttons["conversation.new"].tap()
        let response = app.descendants(matching: .any).matching(identifier: "assistant.response").firstMatch
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: response)
        let result = XCTWaiter.wait(for: [cleared], timeout: 10)
        captureState("New conversation transition", app: app)
        XCTAssertEqual(result, .completed, "The previous response must disappear before typing the next turn.")
        let input = app.textViews["composer.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "")
    }

    private func send(_ text: String, app: XCUIApplication) {
        let input = app.textViews["composer.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText(text)
        let send = app.buttons["composer.send"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: send)
        let result = XCTWaiter.wait(for: [ready], timeout: 10)
        captureState("Send admission readiness", app: app)
        XCTAssertEqual(result, .completed, "Send must be enabled before submitting the actual prompt.")
        send.tap()
    }
    private func finishedResponse(app: XCUIApplication, timeout: TimeInterval) -> String {
        let response = app.descendants(matching: .any).matching(identifier: "assistant.response").firstMatch
        let appeared = response.waitForExistence(timeout: timeout)
        captureState("Actual response arrival before assertions", app: app)
        XCTAssertTrue(appeared, "Actual automatic preparation and inference must finish, not show a placeholder.")
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["composer.stop"])
        let completion = XCTWaiter.wait(for: [finished], timeout: 60)
        captureState("Actual response completion before assertions", app: app)
        XCTAssertEqual(completion, .completed)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.buttons["model.automatic.cancel"].exists)
        XCTAssertEqual(app.textViews["composer.input"].value as? String, "")
        // Selectable code may be a text view. Do not mistake its language label
        // for the whole response through SwiftUI identifier inheritance.
        let roots = app.descendants(matching: .any).matching(identifier: "assistant.response").allElementsBoundByIndex
            + app.descendants(matching: .any).matching(identifier: "markdown.code.content").allElementsBoundByIndex
        let text = roots.flatMap { root in
            ([root] + root.descendants(matching: .staticText).allElementsBoundByIndex
                + root.descendants(matching: .textView).allElementsBoundByIndex)
                .flatMap { [$0.label, $0.value as? String ?? ""] }
        }.joined(separator: " ")
        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        return text
    }
    private func captureState(_ name: String, app: XCUIApplication) {
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + " accessibility tree"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        capture(name, app: app)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
