# History import presentation investigation

Source failure: native run 43673278573, job 132687803054, source ebf810d88be3702e3149707058d101a59a746afb. Artifact 14146127443 SHA-256 0cc44fca0e00ede02552e4efed48d25dbb59e4921e8edae653fe8be22b780307.

The history import test failed at line 141 after the policy button disappeared. Artifact screenshots/82B1F757-794B-4D00-83B2-FD9E1942314B.txt records a separate presented view with only empty Other descendants above Settings, and no Files navigation, browsing tabs or search. Video 9645910F-53C4-444C-8669-2CD3F231147F.mp4 visibly ends on a blank white sheet over dimmed Settings. This is evidence of blank presentation, not evidence of successful Files display or a selector-only failure.

The later 16-test passing summary is the remainder after the XCTest runner restarted. The failing history test was not repeated.

The old production action simultaneously opened fileImporter while confirmationDialog dismissed. The candidate removes that transition: a stable Import backup navigation page offers the same three import policies, with preserve-local default, warning text and an explicit Choose backup file button. No import occurs until a URL is selected. The cause attribution remains a presentation-transition hypothesis until targeted repetitions and broader regression checks pass.

The targeted test retains Files-specific navigation/tab/search assertions, cancels through the actual Files navigation button, verifies return through Import backup and Settings, unchanged conversation-list labels and composer text. Three independent executions are required, with no retry-until-pass. This is not physical-device or full native acceptance. Repository-wide native gates remain separate.
