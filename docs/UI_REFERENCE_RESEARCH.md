# iPhone reference research and acceptance

Research date: November 11, 2026. This document separates directly observed reference evidence from approximation. The application is independent Jarvis-EVO software, not an OpenAI product.

## Primary sources

1. [Official ChatGPT App Store listing](https://apps.apple.com/us/app/chatgpt/id6448311069). Retrieved listing reported version **1.2026.307**, released **November 10, 2026**. Six iPhone promotional screenshots were downloaded from Apple's image CDN and their actual pixels inspected. Screenshot capture dates are unspecified; listing release date does not prove that every image depicts that release.
2. [Official mobile FAQ](https://help.openai.com/en/articles/8142208-chatgpt-ios-and-android-app-faq). Retrieved article reported updated 18 days earlier. Describes sidebar history and profile-to-settings navigation.
3. [Official release notes](https://help.openai.com/en/articles/6825453-chatgpt-release-notes). March 26, 2026 entry describes horizontal shortcuts above chats/projects in the iOS/Android sidebar.

The App Store source assets are reference material only. They are not included as Jarvis-EVO artwork or bundled in the app.

## Observed reference and changes

| Area | Directly observed reference | Previous candidate | Correction |
|---|---|---|---|
| Toolbar | Monochrome menu left; new-chat and more controls grouped right | Green sidebar/settings controls | Neutral menu, new chat and more; existing model picker retained with independent name |
| Composer | Compact floating single-line capsule, plus left, dictation/action right | Two-row, 93.67pt composer | One-row 52pt minimum container, grows for multiline input |
| User replies | Right aligned, pale blue background, blue text | Gray bubble | Adaptive pale blue bubble and blue text |
| Assistant replies | Plain text without recurring name/logo header | Logo/name before every reply | Removed repeated header; retained real progress/failure indicators |
| Message actions | Small neutral icons below content | Fewer actions with extra identity chrome | Copy, read aloud, regenerate, share, more, all wired to existing operations |
| History | Sidebar described in official documentation | Bottom modal sheet with large title | Left drawer with search, horizontal supported shortcuts, chat list and bottom settings |
| Empty state | Not present in retrieved current promotional images | Giant left-aligned title, slogan, large cards, model panel | Restrained centered heading and compact functional prompt chips; explicitly an approximation |

No fake thumbs-up/down controls, voice-call button, account, subscription, external tools, or cloud services were added. Empty Send is disabled; the adjacent mic performs actual on-device dictation. This is a deliberate functional difference from the reference's live-voice button.

## Measured visual RED

Previous native iPhone 16 Plus capture: 1290×2796 pixels, simulator scale 3×. Composer manually bounded at x≈42–1248, y≈2341–2622. Height **281/3 = 93.67pt**. Acceptance assertion **height ≤66pt** failed on that real artifact before implementation.

App Store screenshot 3 is 600×1300 promotional artwork with phone interior approximately x80–520. The composer is approximately x115–485, y1114–1168. Normalizing its 54px height by 440px phone width to the candidate's 430pt width gives **52.8pt**. This is an approximate relative-geometry measurement, not a claim of native source pixels or identical devices. The native target is 52pt at standard text size, with tolerance to 66pt for screenshot/OS layout variation.

Native baseline UI tests were not run before implementation: the available macOS lane was already executing a separate regression run. The visual RED above was executed against the real prior screenshot. Native tests in `JarvisEVOVisualUITests` must run in the combined full gate; their existence is not a passing result.

## Remaining fidelity limits

No owner-provided screenshots/recordings or signed-in reference app session were supplied. Exact empty-state layout, sidebar pixel spacing, account-specific controls, dark palette, keyboard animation timing and behavior cannot be established from these promotional assets alone. System gestures, keyboard, sheets and glass toolbar use native SwiftUI/iOS behavior, with reduced-motion handling. Those choices are documented approximations, not an exact-match acceptance claim.

UI tests are configured to capture the actual simulator empty light/dark app, sidebar, settings and multiline composer. A separate 240-second UI test downloads and verifies the pinned Qwen model through the real model-management screen, selects it, sends a short prompt, waits for completion, captures the genuine local response, and checks conversation/model persistence after relaunch. Until that test runs, none of those captures or outcomes are claimed. A fabricated assistant response is not accepted as evidence of inference.

## Pre-native review corrections

The independent UI source review found that a drawer dismiss gesture could compete with row archive/delete swipes, and that a screenshot labeled light did not force light appearance. Dismissal is now recognized only on the backdrop, and a native regression test exercises actual row archive actions without closing the drawer. Visual test setup explicitly selects Light through Settings; the dark capture explicitly selects Dark. These fixes and tests await the combined native run, rather than being described as already passing.
