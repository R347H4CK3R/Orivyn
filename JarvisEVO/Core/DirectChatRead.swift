import Foundation

/// Direct-read inventory for chat policy, parity-tested against the typed-request router.
/// Adding a tool here requires adding its explicit request parser and tests.
enum DirectChatRead: String, CaseIterable {
    case listModels = "list_models"
    case getAppInfo = "get_app_info"
    case searchMemory = "search_memory"

    var description: String {
        switch self {
        case .listModels: return "list installed models (also: what models do I have?): list models installed in Orivyn"
        case .getAppInfo: return "show app information (also: what can Orivyn do?): read bundled Orivyn app capability metadata"
        case .searchMemory: return "search saved memory for QUERY (also: find QUERY in my saved memories): search saved Orivyn memory notes"
        }
    }
    static var promptInventory: String {
        "DIRECT LOCAL READS (complete list):\n" + allCases.map { "- \($0.rawValue): \($0.description)" }.joined(separator: "\n")
        + "\nThese are the ONLY direct reads. Not general filesystem access or device/user information. Do not replace this inventory with imagined tools."
    }
}
