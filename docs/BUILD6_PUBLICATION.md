# Orivyn build 6 publication receipt

Published November 14, 2026 after the owner authorized a free Mac runner for packaging and publication. The prior no-Mac instruction remained in force for optional verification. Appcircle secure sign-in was unavailable; the existing authenticated CircleCI Free account completed packaging in 64 seconds, using 215 credits. No signup, paid plan or billing change occurred.

The exact new IPA was downloaded from CircleCI and checked independently with `scripts/verify_ipa.py` and the existing OmniForge catalog inspector. CRC, identity, version, platform, minimum OS, notices and required resources passed. `SourceRepairDraft.js` in the IPA matches the tested source byte-for-byte. After uploading the public prerelease, the catalog downloaded it without credentials and verified its SHA-256 before activation. Other catalog apps were preserved. Both raw public feeds were fetched and confirmed to serve version 0.1.1 build 6, 35,042,297 bytes.

General autonomous orchestration, broad vision and automatic cross-device sync remain incomplete. Native unit/UI tests, physical iPhone acceptance and SideStore installation/refresh were not performed for this exact build. Earlier native results apply only to their earlier source commits. The source repository remains private and PR4 was not merged or modified by this work.

```json
{
  "app": "Orivyn",
  "version": "0.1.1",
  "build": "6",
  "source_commit": "319d6aed0a4e7543d23f96bb2de882cf68616348",
  "sha256": "86adf180469d44b927cfc078adb5fcf315c5a4da9a1078f613788771640db79e",
  "size": 35042297,
  "release": "https://github.com/R347H4CK3R/Orivyn-Distribution/releases/tag/orivyn-v0.1.1-build6",
  "shared_source": "https://raw.githubusercontent.com/R347H4CK3R/OmniForge/main/unified-source.json",
  "app_source": "https://raw.githubusercontent.com/R347H4CK3R/Orivyn-Distribution/main/source.json",
  "catalog_commit": "8b35edf67821e6822de2e0b8ebc082dae4463b04",
  "distribution_commit": "83f9d73c26c97bf78b512d326f0cdb072b965b02",
  "circleci": {
    "pipeline": 21,
    "job": 28,
    "job_id": "82612b64-7b46-4eb1-a06a-5083ec64ee93",
    "free_credits_used": 215,
    "free_credits_remaining": 944
  },
  "verification": {
    "foundation": 400,
    "agent_js": 104,
    "vm_js": 39,
    "python_passed": 158,
    "python_skipped": 1,
    "device_release_compile": "passed",
    "download_hash_and_structure": "passed",
    "both_live_feeds": "verified",
    "native_tests": "not_run_for_this_build",
    "physical_device": "not_run",
    "finished_1_0": false
  }
}
```
