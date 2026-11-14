# Remaining model reliability gaps

The free Linux model workflow compiles the production Swift engine and runs the pinned Qwen3 1.7B Q4 model with the real reducer, scope checks and durable task records. It preserves every independent case result even when an earlier case fails. No failures were converted to skips or expected answers.

On 0a175898, all three workflow fixtures failed scope approval: two included the surrounding word conversation in their title, and pagination lost the requested title. A longer title-extraction instruction on 14739e7d still failed all three cases (including an incorrect search query). That unsuccessful prompt change was reverted; its logs remain in run 43651828898. An additional quoted-title holdout preserves a title containing the literal word conversation; it does not replace any prior test.

Vision: the frozen QualityV1 suite tested actual synthetic RGB pixels with the production-pinned SmolVLM2 2.2B Q4 plus its f16 projector. Hashes were verified. The existing Linux shared library hash is recorded, but its build-to-current-source provenance was not re-established; this is a diagnostic, not latest-source native acceptance. Eight of ten cases matched. case02 answered left instead of right; case08 counted five circles instead of four. All ten completed with zero reported live resources. No answer correction was applied. The smaller historical 500M pair also matched eight of ten, with different spatial failures; it was not substituted in the app.

General autonomy, broad vision reliability, automatic paired sync, latest-head native verification and physical-device acceptance remain incomplete. These failures prevent a complete-release claim.


The additional quoted-title holdout passed end to end with the restored production prompt in run https://github.com/R347H4CK3R/Orivyn/actions/runs/43652396865 : actual model search, exact authorized read, random verification-code answer, persistence and reopen. The title contains the literal word conversation. The three unquoted-title cases still failed, so this run is 1/4, not general autonomy acceptance. UI guidance now asks users to quote exact titles; no failed test was rewritten to follow that guidance.

A separate generic vision instruction-prefix experiment scored 7/10 versus the unchanged 8/10 baseline. It introduced an additional spatial failure and was rejected. Exact input prefix, outputs and reports are retained in QualityV1/RESULTS_INSTRUCTION_EXPERIMENT.json. No production vision prompt/model change was made.
