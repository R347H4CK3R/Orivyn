# Picker transition investigation

Run 43669084680 at 56c80f1 executed two picker and two checkpoint tests. Checkpoint relaunch/restore passed twice with handler admission and matching-owner callbacks. Picker passed once and failed once before the Files action could be found.

In the failed picker run, logs contain photos.make but no photos.complete and no files.make. The final UI hierarchy is still in Photos, with its Sort/Filter/View Options menu open. In the successful run, photos.complete empty=true precedes files.make and files.dismantle. Cumulative exports are not separate repetitions.

The existing test waited only for Cancel existence, tapped, read a composer value behind the sheet, then continued without proving dismissal. The next isolated test waits for Cancel to be hittable with stable geometry, taps once, and requires the native Cancel to disappear before opening the app menu. No retries, skipped assertions, longer deadlines or production picker changes. Three repetitions are required; checkpoint tests are not duplicated.

This tightens test action preconditions; it does not establish the original blank UIDocumentPicker root cause or prove production navigation fixed. Preserve the original failure and new outcomes.
