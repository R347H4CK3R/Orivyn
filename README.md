# Orivyn

Orivyn is a local-first iPhone assistant for iOS 26 and later. Jarvis is the assistant inside the app. This project began as Jarvis-EVO and remains in development.

## Orivyn 0.1.8 · build 24 preview

- **Offline Auto** chooses among installed models, with an available Apple or installed general model as a fallback. Auto does not download a model or send text online by itself. You can choose a model manually.
- **Free Online** is an optional, separate composer with an explicit disclosure. It requires internet access and your own OpenRouter key. Auto chooses an eligible free model for the new message; you can also pick one manually. The route does not send saved chats and does not fall back to a paid model. Provider rate limits still apply.
- **Web** lets you review an address or search before opening it in a Safari view. You can request Reader where supported, save local bookmarks, copy links with known trackers removed, or ask an installed model about a passage you paste. Cleaned links can still contain private information.

### Install

Use this single shared source in SideStore or Strata. You do not need to add an Orivyn-only source as well.

```text
https://raw.githubusercontent.com/R347H4CK3R/OmniForge/main/unified-source.json
```

[Download the unsigned IPA](https://github.com/R347H4CK3R/Orivyn/releases/download/orivyn-v0.1.8-build24-shared-preview/Orivyn-0.1.8-build24-unsigned.ipa) · [Release notes and SHA-256 checksums](https://github.com/R347H4CK3R/Orivyn/releases/tag/orivyn-v0.1.8-build24-shared-preview)

The 38,434,379-byte package is ARM64 and must be signed by your sideloading setup. Back up your data before updating and keep the same signing identity and bundle ID (`app.jarvisevo.ios`). Models download separately.

IPA SHA-256: `f6263390bd9e5626d7d4f66f47590a291b76889861b51eb2fa6a095ceda6e9c5`.

### Screenshots

Actual iPhone 16 Plus Simulator captures from the [verified build run](https://github.com/R347H4CK3R/Orivyn/actions/runs/44697888500), using synthetic data.

<div>
  <img src="https://github.com/R347H4CK3R/Orivyn/releases/download/orivyn-v0.1.8-build24-shared-preview/01-chat-auto.png" alt="Orivyn chat with Offline Auto and a Web entry" width="215">
  <img src="https://github.com/R347H4CK3R/Orivyn/releases/download/orivyn-v0.1.8-build24-shared-preview/02-choose-ai.png" alt="Choose an AI with installed-only Auto and offline choices" width="215">
  <img src="https://github.com/R347H4CK3R/Orivyn/releases/download/orivyn-v0.1.8-build24-shared-preview/03-free-online.png" alt="Free Online disclosure and optional model selection" width="215">
  <img src="https://github.com/R347H4CK3R/Orivyn/releases/download/orivyn-v0.1.8-build24-shared-preview/04-web.png" alt="Orivyn Web screen with address and search controls" width="215">
</div>

This is a prerelease, not 1.0. Simulator tests and unsigned-package verification do not establish physical iPhone operation or signing and refresh through a sideloading app.

[All releases](https://github.com/R347H4CK3R/Orivyn/releases)
