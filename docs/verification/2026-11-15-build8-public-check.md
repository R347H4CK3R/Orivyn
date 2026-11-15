# Independent public preview verification — 2026-11-15 03:46 UTC

Downloaded Orivyn-0.1.1-build8-unsigned.ipa directly from the public Orivyn release, not the older Distribution repository. Publication date2026-11-15 03:12:33 UTC (November14 9:12pm America/Chicago). Ran scripts/verify_ipa.py:exit0. Result accompanies this report:ARM64,minOS26.0,version0.1.1 build8,bundle app.jarvisevo.ios,37,072,679 bytes,SHA25604c2bd77eb6f807eb17c24bce6ff0a8cf88cae5d74e0e43955cba9230d01723d. Required resources/notices and fixture exclusions passed.

Release source:a6c696a89a2e5a6224e220b6772b62614d30b4df. No exact-package native unit/UI or physical-device result is claimed. Release remains an incomplete preview; the later peer changes are absent.

https://github.com/R347H4CK3R/Orivyn/releases/tag/orivyn-v0.1.1-build8

README still advertised build4 and private source. Updated the install section to the actual build8 URL, identity and limits; retained historical tests as historical evidence. Diff whitespace check passed.

At inspected source7dfb58ab7196eb95a4666cc19a3a586224fcc2f1, independently ran208 Python tests:207 passed,one real-tokenizer skip;134 JavaScript agent tests passed; catalog check passed. These tests predate this documentation-only correction and are not native iOS tests.

Observed actual workflow status:peer app compile43672467858 succeeded; sender cancellation43668453673 succeeded; native transcript diagnostic43672816771 succeeded. Repository evidence reports4/4 diagnostic read selections at4096 context, versus0/4 flat baseline; production2048 follow-up remains pending. This is not complete workflow execution or a production repair. Photos cancellation regression remains unresolved.

No new publication/signing/network sync activation in this check. Next: validate production-budget agent behavior and picker repair, then current-head app/device acceptance. Periodic work is not continuous execution.
