# Full-library saved-memory retrieval

The old first-500-note cutoff is removed for saved-memory tool reads and automatic chat context selection. These reads scan an immutable in-memory note snapshot on a detached task; cancellation propagates and ownership is rechecked before context/result use. No network or file upload is performed by retrieval.

Tool reads retain at most ten matches and count all literal substring matches; context selection retains at most eight ranked candidates while scanning, rather than sorting/materializing all candidates. Output stays at the existing 512/1024-byte chat context and tool JSON limits. All original notes remain unchanged. No semantic index or unlimited recall is claimed. Search is O(total text) and storage still loads saved notes into memory; this is not a disk-backed paginated database index.

The supported saved-note size (32,768 bytes) is fully scanned for context ranking. Malformed larger in-memory notes are still prefix-bounded, with truncation disclosed. Query length and excerpt caps remain enforced. Historical bounded-search records remain readable without being relabeled as full-library results.

## Validation

- Red tests reproduced the 500-note omission.
- Foundation suite tests cover a match in note 10,000 and bounded output; a generous ten-second host regression ceiling is not an iPhone performance guarantee.
- Exact production dispatcher host smoke covers async search, note 10,000, and cancellation; no Apple UI/runtime claim.
- Swift/JS completion result validators accept full-snapshot counts and still reject unsafe integers/inconsistent counts.
- Actual iPhone, selected-folder import, native model behavior, and native UI remain separate verification gates.
