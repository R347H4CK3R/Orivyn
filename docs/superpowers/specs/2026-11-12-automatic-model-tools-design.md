# Automatic local models and actionable native tools

User request: choose and switch models from the typed request, download missing models, and do useful work instead of generic refusals. Keep Orivyn free, efficient and honest about actual capabilities. Later requests add installable plugins and a virtual computer; those require a separately permissioned real backend and are not simulated by this feature.

## Chosen design
A persisted, opt-in Automatic local mode preserves the existing manual provider choice. A deterministic bounded router classifies typed text as general or coding. It prefers an exact verified catalog match already installed and within RAM guidance; otherwise it downloads only the pinned Qwen2.5 0.5B general/coder Q4 target, at most 750 MB per operation. Experimental reasoning, imported models, Apple system and remote endpoints remain manual. There is no second model loaded merely to route, no retry/refusal loop, no automatic deletion, and only one shared inference engine.

The user sees the chosen model, reason, publisher download size, storage requirement, progress and Cancel. Automatic mode explicitly permits these downloads; unmetered Wi-Fi or Ethernet/non-expensive/non-constrained is the default, cellular is a separate opt-in. Unknown network or free storage blocks a download, not offline use of a compatible installed model. URLSession enforces network policy even if path state changes. All existing size/SHA/template/atomic-install safeguards remain.

Preparation belongs to an operation ticket containing conversation, composer and provider revisions. No message enters history and no draft is cleared until a verified provider is ready. Editing (even edit-and-revert), navigation, mode/manual provider changes, background, Cancel, voice or import invalidate ownership. A completed valid install may remain, but abandoned work cannot switch or send. Automatic preparation cannot piggyback or cancel another manual download.

Conservative direct requests show a native tool review card (Email, Calendar, Browser, Location or Reminder). No tool executes because a model, attachment or quoted text requested it. The user opens the real screen and retains the existing final system review/permission controls. No unreliable extraction of recipient/date or promise of email delivery. The model prompt emphasizes feasible help first and accurate directions to real tools, not fictional execution or universal capability.

## Alternatives rejected
- LLM-driven router and refusal retries: slow, unpredictable, unbounded memory/download cost.
- Silent multi-gigabyte downloads or remote fallback: surprising data/cost/privacy impact.
- Automatic native or remote execution from generated strings: lacks reliable capability validation and user approval.

## Boundaries
Typed text routing only initially; voice retains its currently configured provider and tested ownership. Model quality is not guaranteed. Images remain OCR text, not multimodal pixels. Hosted ChatGPT services, paid infrastructure, bank/password/Health access and a virtual computer do not appear merely from UI parity. Existing public build 4 remains live until an exact new source passes native/UI/device packaging gates.

Network transitions: URLSession enforces non-cellular/non-expensive access by default and always rejects constrained (Low Data Mode) access. Cellular opt-in necessarily permits expensive connections in URLSession; the path monitor additionally cancels only the owned automatic download when a disallowed hotspot/path is observed. Transition monitoring is best-effort, not a zero-byte guarantee. Installed-only preparation and manual downloads are not canceled by this automatic policy.
