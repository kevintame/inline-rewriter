import Foundation

/// OpenAI model selector.
/// Expand as needed.
enum OpenAIModel: String, CaseIterable, Identifiable {
    case gpt4oMini = "gpt-4o-mini"
    case gpt4o = "gpt-4o"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .gpt4oMini: return "GPT-4o mini"
        case .gpt4o: return "GPT-4o"
        }
    }
}
