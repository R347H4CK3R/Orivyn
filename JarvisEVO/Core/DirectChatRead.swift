import Foundation

/// Direct-read inventory for chat policy, parity-tested against the typed-request router.
/// Adding a tool here requires adding its explicit request parser and tests.
enum DirectChatRead: String, CaseIterable {
    case listModels = "list_models"
    case getAppInfo = "get_app_info"
    case searchMemory = "search_memory"

    var description: String {
        switch self {
        case .listModels: return "list installed models in Orivyn"
        case .getAppInfo: return "show app information: bundled capability metadata"
        case .searchMemory: return "search saved memory: Orivyn notes"
        }
    }
    static var promptInventory: String {
        "DIRECT LOCAL READS (complete list):\n" + allCases.map { "- \($0.rawValue): \($0.description)" }.joined(separator: "\n")
        + "\nNot general filesystem access or device/user information."
    }
}
