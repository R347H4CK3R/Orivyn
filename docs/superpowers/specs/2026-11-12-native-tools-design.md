# Real native tools after the second iPhone recording

Chris's 72-second recording deliberately opens Email, Calendar, Passwords, Health, Finances, Browser and Location in Orivyn0.1.0; he asks that these be implemented in the next IPA. It also shows nine model choices and an installed Qwen Coder model. Opening these screens is not verification of their operation, answer quality or all-device performance.

## Chosen scope and architecture
Builder's choice under the user's request to proceed autonomously: extend the existing SwiftUI/iOS26 app using free system frameworks, with explicit human review and no backend. Keep app.jarvisevo.ios, app data and all source privacy. Alternatives considered: broad account OAuth/backend connections introduce service setup, credentials and potential costs; a private WKWebView/browser agent exposes more account data than needed. Do not silently enable either.

- Email: a local draft form opens Apple's MFMailComposeViewController only when canSendMail is true. The user reviews recipients/content and presses Send in Apple's UI. A sent callback means queued, not delivered. No inbox access or copied credentials. If Mail isn't configured, preserve text and explain the limitation without pretending an account is connected.
- Calendar: bounded title/notes/date draft opens EKEventEditViewController. iOS17+ permits this without full or write-only calendar permission. The user chooses the calendar and Add; cancel does not save. Never enumerate existing events or silently save.
- Browser: validate an explicit HTTPS URL, no embedded credentials/control characters/oversized strings. Present SFSafariViewController modally. The destination receives normal browsing requests; Orivyn cannot read website data, passwords or history and does not pass page content to models. Done returns to the unchanged draft. No autonomous browsing claim.
- Location: one-shot CLLocationManager initiated only by explicit request; When In Use permission only, no background mode, no geocoder/server. Show timestamp and accuracy, do not overstate precision. Reject invalid/stale results. Serialize requests, cancel and clear on leaving/background; ignore late callbacks. Coordinates stay in memory unless the user explicitly copies them. No silent Maps transmission.

Passwords, Health and Finances remain explicit capability/account limitations, not renamed dummy features: generic iCloud Passwords reading is not offered by public APIs; HealthKit requires its supported capability and a compatible signing setup; bank sync requires separately authorized providers. Do not add unsupported entitlements to the free-side-loading package or invent secure-vault/finance services as substitutes.

## Verification and boundaries
First add native UI tests against the existing screens and record missing-control failures. Then unit-test URL/calendar/mail limits and location ownership/permission/timeout/cancellation with injected hardware boundary. Native tests exercise real UIKit editors and cancellation, real simulator location API with declared simulated coordinates where available, and no configured Mail account fallback. Never send a real test email or save a real user's calendar event. A final full native/UI/real-model/ARM64 package run and screenshot inspection precede catalog activation. Physical iPhone permission behavior, delivery and free signing refresh remain user-device gates.

## Official API evidence
- https://developer.apple.com/documentation/technotes/tn3152-migrating-to-the-latest-calendar-access-levels
- https://developer.apple.com/documentation/messageui/mfmailcomposeviewcontroller
- https://developer.apple.com/documentation/safariservices/sfsafariviewcontroller
- https://developer.apple.com/documentation/corelocation/cllocationmanager
- https://developer.apple.com/documentation/corelocation/cllocationmanager/requestlocation()
- https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
