# Voice lifecycle review and native gate

Existing implementation already supports foreground-only on-device dictation, final-transcript submission, exact-ticket response cancellation, completed-response speech, and audio interruption/media-reset recovery. No claim of acoustic barge-in or background microphone service.

Independent review found idle headphone removal or media reset could report a false “Dictation was interrupted” message after standalone dictation ended. Both handlers now snapshot recording/starting/finishing/speaking state before teardown and only notify an interrupted active operation. Idle media resets still recreate the engine and synthesizer; they never start audio.

Two native regression tests cover idle interruption/headphone removal and idle reset resource replacement. They are authored but **not compiled or run** here. Existing active-permission and playing-reset tests remain. The explicit manual native gate now selects VoiceServiceTests, VoiceConversationControllerTests, VoiceConversationSessionTests, VoiceAppModelTests and RootViewOwnershipUITests. This does not start CI or enable billing.

Portable structural tests observed missing guards/selectors fail before changes, then pass. Full portable suite: 103 Python, 60 agent/router/diff JavaScript, 39 VM JavaScript tests passed. These do not test Apple speech hardware or Swift compilation. Simulator/device microphone, real speech recognition, audible playback, route changes, and media-service reset acceptance remain required. No IPA/version/catalog publication changed.
