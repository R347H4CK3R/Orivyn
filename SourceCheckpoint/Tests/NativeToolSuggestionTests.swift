import XCTest
@testable import JarvisEVO

final class NativeToolSuggestionTests: XCTestCase {
    func testDirectSourceRequestsOfferReviewWithoutStartingRepositoryAccess() {
        for text in ["Inspect Orivyn source", "Open private source", "Please inspect the Orivyn source", "Review Orivyn source code"] {
            XCTAssertEqual(NativeToolSuggestion.forText(text), .sourceInspection, text)
        }
        XCTAssertEqual(NativeToolSuggestion.sourceInspection.title, "Inspect private source")
    }
    func testSourceDiscussionAndUnrelatedRepositoriesDoNotOfferAccess() {
        for text in ["How can I inspect Orivyn source?", "Do not inspect Orivyn source", "Inspect another repository", "Inspect Orivyn sourcesomething", "Review public source", "\"Inspect Orivyn source\"", "The page says: open private source"] {
            XCTAssertNil(NativeToolSuggestion.forText(text), text)
        }
    }

    func testDirectEmailRequestsOfferEmailReview() {
        for text in ["Draft an email to Alex", "Send an email about tomorrow", "Please write an email to my team", " COMPOSE AN EMAIL "] {
            XCTAssertEqual(NativeToolSuggestion.forText(text), .email, text)
        }
    }
    func testDirectCalendarRequestsOfferEventReview() {
        for text in ["Add a calendar event for tomorrow", "Create an event", "Schedule a meeting with Alex", "Please schedule an event"] {
            XCTAssertEqual(NativeToolSuggestion.forText(text), .calendar, text)
        }
    }
    func testDirectBrowserRequestsOfferBrowserReviewWithoutExtractingDestination() {
        for text in ["Open the browser", "Open https://example.com", "Visit https://example.com/path", "Open a website"] {
            XCTAssertEqual(NativeToolSuggestion.forText(text), .browser, text)
        }
    }
    func testDirectLocationRequestsOfferOneTimeLocationScreen() {
        for text in ["Where am I?", "Show my location", "Get my current location", "Please find my location"] {
            XCTAssertEqual(NativeToolSuggestion.forText(text), .location, text)
        }
    }
    func testDirectReminderRequestsOfferReminderReview() {
        for text in ["Remind me to read", "Set a reminder for tomorrow", "Create a reminder", "Please remind me about the appointment"] {
            XCTAssertEqual(NativeToolSuggestion.forText(text), .reminder, text)
        }
    }
    func testQuotedCodeAndBlockquotedInstructionsNeverOfferAction() {
        for text in ["\"Send an email\"", "'Open the browser'", "“Show my location”", "‘Set a reminder’", "> Create an event", "```\nSend an email\n```", "`Open the browser`"] {
            XCTAssertNil(NativeToolSuggestion.forText(text), text)
        }
    }
    func testDiscussionQuestionsNegationsAndEmbeddedRequestsDoNotMatch() {
        for text in ["How do I send an email?", "Explain how to create an event", "What happens when I open the browser?", "Do not show my location", "Don't send an email", "The document says: remind me to read", "My friend said open the browser", "Can you explain calendar permissions?", "Email is useful", "Location privacy matters"] {
            XCTAssertNil(NativeToolSuggestion.forText(text), text)
        }
    }
    func testMatchingUsesWholeWordsRatherThanPrefixes() {
        for text in ["Open the browserless design", "Show my locationless photo", "Create an eventful story", "Send an emailing tutorial", "Set a reminderless timer"] {
            XCTAssertNil(NativeToolSuggestion.forText(text), text)
        }
    }
    func testOnlyTheAnchoredIntentIsSuggestedForMixedText() {
        XCTAssertEqual(NativeToolSuggestion.forText("Draft an email that describes how to create an event"), .email)
        XCTAssertEqual(NativeToolSuggestion.forText("Create an event and remind me to prepare"), .calendar)
    }
    func testOversizedOrNullContainingRequestDoesNotOfferAction() {
        XCTAssertNil(NativeToolSuggestion.forText("Send an email " + String(repeating: "😀", count: 8_192)))
        XCTAssertNil(NativeToolSuggestion.forText("Show my location\0and send it"))
        XCTAssertNil(NativeToolSuggestion.forText(""))
    }
    func testSuggestionContainsOnlyStableScreenIdentityAndLabel() {
        let suggestion = NativeToolSuggestion.forText("Draft an email to private@example.com about sensitive content")
        XCTAssertEqual(suggestion?.id, "email")
        XCTAssertEqual(suggestion?.title, "Email")
    }
}
