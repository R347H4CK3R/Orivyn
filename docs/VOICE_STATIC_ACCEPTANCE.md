# Executed foreground voice-controller lifecycle

The new run_voice_smoke.py compiles exact production VoiceConversationController with official Swift6.1.3 static Observation libraries. It does not replace the controller or emulate Apple APIs. Test-only VoiceConversationAudio and sendText/cancelResponse boundaries are explicitly controlled doubles.

Seven async scenarios passed twice: stopping before listening task entry; final-only submission/duplicate-final suppression/complete-response playback; stopping before response task entry; stale callbacks/results after stop and restart; background stop without automatic foreground restart; failed-response suppression; and empty-final rejection. Evidence is voice-smoke-1 and voice-smoke-2 under the validation directory. These are separate executable smoke scenarios, not additional XCTest cases.

VoiceError was moved unchanged from VoiceService into Core/VoiceError.swift to avoid pulling Apple audio frameworks into the controller test. Extraction hash74e2b832ff745a3688a80691b17908fe7d05447f32ae738c5502d5b31412611d and single-definition checks pass. No error wording or production controller behavior changed. Initial missing-type/cache-path errors and the static Foundation linker warning are retained; they are not represented as app runtime regressions.

This does NOT verify the microphone, speech recognition, synthesis, actual model/provider responses, VoiceService/AppModel integration, iOS permissions or an iPhone build. Original native XCTest and device gates still apply.134Python tests pass. No paid build or public release changed.
