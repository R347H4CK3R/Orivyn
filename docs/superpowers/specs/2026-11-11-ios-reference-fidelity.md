# Jarvis-EVO iPhone reference fidelity

The owner requested faithful ChatGPT iPhone layout and interaction, while retaining independent Jarvis-EVO branding and original assets. The owner explicitly asked us to research and proceed rather than wait for their screenshots. Continue the existing native SwiftUI app, persistence and inference implementation.

## Evidence

- Official App Store listing: https://apps.apple.com/us/app/chatgpt/id6448311069, retrieved November 11, 2026. Current listing version 1.2026.307, released November 10. Six actual iPhone marketing screenshots viewed, not just text descriptions. Their illustration/UI capture dates are not stated and may differ from release date.
- Official app FAQ: https://help.openai.com/en/articles/8142208-chatgpt-ios-and-android-app-faq. Sidebar opens history; profile in sidebar opens settings. Updated 18 days before retrieval.
- Official release notes: https://help.openai.com/en/articles/6825453-chatgpt-release-notes. March 26, 2026 describes horizontal experience shortcuts above chats/projects in mobile sidebar.
- Screenshots show monochrome controls, an approximately 50pt single-row floating composer at rest, top-left two-line menu, top-right grouped compose/more controls, light-blue user bubbles, no assistant name/logo repeated above replies, small response actions, and generous white space.

## Scope and choices

Remove the oversized left-aligned welcome branding, explanatory slogan, large stacked suggestions, green chrome, two-row idle composer, repeated assistant identity, and sheet-style history. Use a compact centered empty state with concise functional suggestion chips, monochrome native controls, one-line growing composer, sliding left history drawer with search and bottom settings, plain assistant replies and blue user bubbles. Keep a small Jarvis-EVO title/model control; no copied OpenAI logo or official identity. Keep disabled Send when empty rather than displaying an unsupported voice-conversation control. Dictation remains the real microphone action. No invented tools, feedback buttons, cloud products, account, or subscription controls.

Rejected approaches: another original aesthetic does not satisfy the correction; copying app branding or unavailable functional controls violates the brief. A static screenshot shell would not preserve actual functionality.

No owner-provided empty-state, sidebar, dark-mode, animation, or account-specific captures exist. Those areas are high-confidence structural approximations from public evidence, not measured pixel matches. Native screenshot comparison must distinguish measured geometry from inferred states. Public marketing pixels never become application artwork.

## Acceptance

Compact composer is under 66pt at rest with controls on one horizontal row; native send/attachments/dictation retain real actions. Sidebar is a left drawer narrower than the screen, opens from menu and edge gesture, dismisses by backdrop or swipe, and retains selection/search/archive/rename/delete/share. Settings remains reachable from sidebar/profile and more menu. Text and controls remain readable in dark mode and accessibility sizes. Empty state no longer scrolls a giant hero past a clipped setup card. Full native tests, real local-model integration and unsigned-device-package gates remain mandatory.
