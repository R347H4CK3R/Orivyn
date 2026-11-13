# Actual guest-shell readiness
The maintained xterm child emits ORIVYN_DESKTOP_SHELL_READY_v1 over the local emulated UART before exec of its shell. Native acceptance waits up to 120 seconds, rather than sending input after a fixed 35 seconds. This signal is not proof of file save, checkpoint or restoration; the independent fresh-file assertions remain mandatory.

Incremental host build and actual graphical edit/save/fresh-engine checkpoint restoration passed (35.8s). 29 JS, 3 materializer, 8 guest source-config tests and 15 asset pins pass. Native verification of this revision remains pending. The prior e8 native run passed 23 unit tests but failed real desktop file result; diagnostic guest-console commands did execute successfully.

Source image change is retained in guest-source/root.xinitrc. Complete corresponding-source package and its 722-file checksums were updated locally; final distribution, clean rebuild, firmware reproducibility, vulnerability review and physical device resource tests remain blocked release gates. No 1.0 IPA is published by this diagnostic workflow.
