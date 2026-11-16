# Plugin proposal answer-channel boundary

An isolated correction allows thinking-model output to produce a reviewed plugin
proposal from its visible JSON answer. It uses the same bounded leading-reasoning
filter as ordinary chat, then the unchanged strict live-catalog/schema parser.
Hidden reasoning is never a proposed call; an unclosed reasoning-only response
fails. All received bytes, including discarded reasoning, count against 16 KiB.
This creates no execution permission and does not relax exact-call review.

The visible-answer fixture failed before the correction; 534 integrated portable
Foundation tests pass afterward, including three added proposal regressions. The
previously documented unsupported Linux URLProtocol redirect fixture is excluded.
These are synthetic provider tests, not a claim that any external plugin or actual
model proposal has been verified. Native CI source remains unchanged while its
existing gate runs; this candidate is not a new release.
