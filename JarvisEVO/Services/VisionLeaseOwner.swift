// AppModel already implements the awaitable text-release and heavy-work lease
// contract. Native runtime activation remains gated on model/device acceptance.
extension AppModel: VisionLeaseOwner {}
