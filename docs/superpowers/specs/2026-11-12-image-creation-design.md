# Native image creation: bounded iOS 26 path

## Outcome and limits

Create a real image through Apple's user-controlled Image Playground sheet. The scoped path requires OS major version 26 and the live `supportsImagePlayground` environment value. It offers only animation, illustration and sketch, never `.all` or `.externalProvider`. Unsupported devices, simulators without support and iOS 27+ retain browsing/import with an honest unavailable explanation. The always-visible entry opens a truthful capability/form view even when unavailable. Stable accessibility identifiers are image.creation.title, image.creation.prompt, image.creation.generate, image.creation.unavailable and image.creation.cancel. No fake generation, AIProvider fallback, subscription, API key, automatic photo input or automatic prompt submission.

Apple's newer iOS 27 Image Playground uses Private Cloud Compute with usage limits. The iOS 26 restriction is therefore intentional: excluding ChatGPT alone does not establish on-device execution on newer systems. Physical-device offline acceptance remains required before claiming tested offline generation.

## Interfaces and ownership

`GeneratedImageStaging(directory: URL) throws` owns a private staging directory outside the attachment directory. `stage(from: URL) throws -> URL` synchronously copies an accepted local regular file into a random direct-child filename, preserving an allowed image extension. It rejects non-file URLs, final-component symlinks, nonregular files, empty files, oversized files and unsupported extensions. Read from an opened descriptor with no-follow/nonblocking flags, recheck file type and size on that descriptor, and bound reads to the existing 10 MiB limit plus one sentinel byte. A failed copy must leave no destination or partial file. Apply iOS file protection and exclude staging from backup. This step does not replace later image decoding, pixel/dimension limits or provenance validation.

`discard(_ stagedURL: URL) throws` removes only validated direct children of this directory, never arbitrary callback paths. Do not automatically sweep staging on each initializer: in-flight owners may still use it. The integration owner must reclaim abandoned files at a controlled startup point and cancel/clean up accepted jobs on history deletion.

`ImageCreationAvailability.isAvailable(supportsImagePlayground: Bool, osMajorVersion: Int) -> Bool` is a pure policy check.

`ImageCreationView(stager: GeneratedImageStaging, onAccepted: @escaping (URL, String) -> Void)` owns the editable concept and sheet presentation. Create is an explicit tap. Cancellation preserves the concept and never calls the acceptance closure. The completion callback stages the returned file synchronously before returning, then transfers cleanup responsibility for the owned URL to `onAccepted` with the exact user-entered concept. The callback synchronously registers ownership before asynchronous processing. Concepts must contain nonwhitespace text, at most 1,024 UTF-8 bytes and no NUL. Invalid concepts disable generation. If staging fails, show a clear error and keep the concept for retry. No detached task may retain the system temporary URL instead of first making the owned copy.

## Integration contract (separate owner)

The main AppModel imports the owned staged URL asynchronously through AttachmentService, persists a dedicated image-result conversation in SQLite, then publishes it to the existing Images/Space list. It does not submit a chat request or mutate the active composer. Existing attachment limits remain 10 MiB, 40 million pixels and 16,384 maximum dimension. The owner protects imports against unreferenced-file cleanup, checks operation ownership after awaits, deletes imported bytes on failed persistence and always discards staging once import no longer needs it. No persistent record stores the temporary absolute URL.

WorkspaceStore is not an image store. Current Images are derived from conversation attachments, so a persistent dedicated conversation avoids an independent gallery index. Existing original metadata/share warnings remain in force.

## Verification before implementation

The integration owner supplies a genuine missing-image UI RED from the existing app. Test source is prepared separately until that run completes so unresolved new types cannot contaminate the baseline. Then add staging/policy tests before production implementation. Cover real temporary files, retained bytes after source deletion and stager recreation, repeated unique copies, boundary sizes, rejected URLs/symlinks/directories, failed destination creation without orphans, scoped cleanup and policy rejection on unsupported/27+ systems.

Physical iPhone 16 Plus/iOS 26 gate: actual system sheet, restricted style picker, benign generated image acceptance, saved preview, relaunch persistence, cancellation preservation and offline repeat after Apple model readiness. Fixture imports and unavailable simulator branches prove plumbing only, not image generation.

## Official references

- Sheet and temporary output ownership: https://developer.apple.com/documentation/swiftui/view/imageplaygroundsheet(ispresented:concept:sourceimage:oncompletion:oncancellation:)
- Explicit style allowlist: https://developer.apple.com/documentation/swiftui/view/imageplaygroundgenerationstyle(_:in:)
- External provider style: https://developer.apple.com/documentation/imageplayground/imageplaygroundstyle/externalprovider
- Original picker privacy: https://developer.apple.com/videos/play/wwdc2024/10123/
- Newer cloud behavior and usage limits: https://developer.apple.com/videos/play/wwdc2026/375/
- ImageCreator discontinuation: https://developer.apple.com/news/?id=dz9wvq0r
