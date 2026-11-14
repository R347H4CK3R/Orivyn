# OCR/document processing candidate

Implemented source, native Apple Vision/PDFKit execution remains unverified.

Images retain primary recognized text, actual recognizer score and optional second candidate. Scores are explicitly not calibrated correctness probabilities; low-scored text is labeled rather than silently discarded or replaced. Alternatives are labeled as alternatives, never automatic corrections. Empty/failed recognition remains unknown content, not proof of blank pixels. Existing character/observation bounds remain enforced.

PDF import now extracts selectable text with page provenance. Pages without selectable text use bounded on-device raster OCR, up to20 attempts,500 inspected pages and60000 total output characters. Summary states inspected/omitted pages, embedded-text pages, OCR attempts, skipped OCR and output truncation. Original files remain available, including valid PDFs without recognized text. Locked/malformed PDFs still fail; failed imports clean up their private copy.

Rendering bounds output pixels to1600 longest edge, validates geometry and handles page rotation. Cancellation checks surround native operations. These bounds do not preempt a single PDF drawing/OCR call or bound the complexity of malicious compressed/vector PDF content. Runtime, memory and orientation acceptance require native tests.

Authored tests cover confidence formatting, mixed embedded/raster provenance, page/OCR/output limits, rotation, cancellation and real rendered-word OCR. They are unrun. The prior blank-PDF rejection expectation changed deliberately: valid unknown-content PDFs are retained with an explicit OCR diagnostic; no fabricated text is substituted.

Independent Linux Tesseract on the same eight frozen vision holdouts recognized no nonwhitespace text, missing all three difficult text fixtures. A whitespace-only row scored95. No images/retries/settings were altered to hide failures. This is Linux engine evidence, not Apple Vision validation, and reinforces that empty output and high scores cannot establish content/accuracy.

No image-pixel understanding is claimed for text chat. No paid CI, authenticated upload or publication occurred.
