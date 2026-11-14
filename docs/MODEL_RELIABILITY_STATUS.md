# Remaining model reliability gaps

The free Linux model workflow compiles the production Swift engine and runs the pinned Qwen3 1.7B Q4 model with the real reducer, scope checks and durable task records. It preserves every independent case result even when an earlier case fails. No failures were converted to skips or expected answers.

On 0a175898, all three workflow fixtures failed scope approval: two included the surrounding word conversation in their title, and pagination lost the requested title. A longer title-extraction instruction on 14739e7d still failed all three cases (including an incorrect search query). That unsuccessful prompt change was reverted; its logs remain in run 43651828898. An additional quoted-title holdout preserves a title containing the literal word conversation; it does not replace any prior test.

Vision: the frozen QualityV1 suite tested actual synthetic RGB pixels with the production-pinned SmolVLM2 2.2B Q4 plus its f16 projector. Hashes were verified. The existing Linux shared library hash is recorded, but its build-to-current-source provenance was not re-established; this is a diagnostic, not latest-source native acceptance. Eight of ten cases matched. case02 answered left instead of right; case08 counted five circles instead of four. All ten completed with zero reported live resources. No answer correction was applied. The smaller historical 500M pair also matched eight of ten, with different spatial failures; it was not substituted in the app.

General autonomy, broad vision reliability, automatic paired sync, latest-head native verification and physical-device acceptance remain incomplete. These failures prevent a complete-release claim.
