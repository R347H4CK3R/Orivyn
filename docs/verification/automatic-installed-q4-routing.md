# Installed Q4 general-chat routing repair

Observed source behavior: Automatic considered only catalog entries labeled General chat or Coding. The pinned Qwen3 1.7B Q4 entry is labeled Reasoning, so a machine with that model installed ignored it and attempted the small default download. The regression test failed with `storageUnknown` under an offline/no-storage-information fixture instead of using the installed model.

The repair admits only the exact independently pinned Qwen3 1.7B Q4 model as an installed General-chat candidate, using ID, SHA, filename, size and existing RAM guidance. This model passed the native conversational probes in run 43825291078; that evidence is not a guarantee of arbitrary model quality. Other experimental Reasoning models remain excluded. Coding selection and both automatic-download choices are unchanged. Inference still verifies file bytes through LocalModelStore.

Tests cover offline installed use, RAM exclusion, Coding separation and mismatched metadata rejection. The new real Automatic normal-chat model test must still run to establish end-to-end selection and dispatch. No runtime success is claimed by deterministic router tests alone.
