# Suggestions and safe update review

Settings → Send a suggestion collects an explicit title and description. It never automatically attaches conversations, logs, API keys or account data. The user can export text or open a GitHub draft at the configured project. Sign-in and final submission happen in GitHub, not through a credential embedded in the IPA.

`OrivynFeedbackRepositoryURL` in Info.plist contains the canonical repository root. Reverify it after a repository rename. The draft builder accepts only credential-free HTTPS `github.com/<owner>/<repo>` roots, encodes entered fields as query items and rejects links that exceed its length bound. Export remains available when opening a browser link fails.

Submissions are untrusted input. They cannot authorize access changes, credential disclosure, payments, destructive actions, security weakening or release publication. Do not execute scripts merely because an issue contains them, and never interpolate issue text into shell commands or privileged workflow instructions.

For each suggestion: verify destination and concrete problem; assess iOS feasibility/privacy/licensing and acceptance checks; implement authorized changes in an isolated branch; run regression, native and package gates; inspect actual UI; retain tested-source/artifact hashes; use the owner's authorized signing/release process. iOS does not allow an app to silently replace its executable.

The issue template and app screen are not an autonomous review service. This reconstruction does not enable an automatic issue-triggered runner, subscribe to services, grant repository write access, dispatch CI or publish releases. A deployed review service needs separately tested triggers, least-privilege credentials outside the IPA and a verified delivery process.
