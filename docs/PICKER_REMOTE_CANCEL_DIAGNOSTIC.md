# Remote Photos Cancel diagnostic

Run 43672111119 at 782c41d failed all three repetitions before any Cancel tap. Artifact 14145381705 shows a transient PUPickerUnavailableView Cancel at y=83, then the actual Photos navigation bar Cancel at y=127. Waiting for generic Cancel hittability was not a demonstrated fix and is not integrated into production.

This isolated test waits for the actual Photos navigation bar, resolves its own Cancel, validates visible nested geometry and unchanged frame, performs one tap, and requires both Photos and Cancel to disappear. This follows the existing remote-photo selection approach. Files cancellation and draft assertions remain. No production UI code is changed. Native repetitions must pass before integration; neither the original blank Files failure nor intermittent navigation is declared fixed.
