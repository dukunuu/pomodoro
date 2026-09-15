import Foundation

/// One entry from OpenRouter's public model catalogue, reduced to what a
/// person choosing a classifier needs: who makes it, what it costs, and
/// whether it honours JSON mode.
struct AIModel: Identifiable, Hashable {
    let id: String
    let name: String
    /// US dollars per million tokens; nil when the price is variable.
    let promptPrice: Double?
    let completionPrice: Double?
    let contextLength: Int
    let supportsJSON: Bool

    var provider: String { String(id.split(separator: "/").first ?? "") }

    /// "$0.15 / $0.60 per 1M tokens", or "Free".
    var priceLabel: String {
        guard let promptPrice, let completionPrice else { return "Variable pricing" }
        if promptPrice == 0 && completionPrice == 0 { return "Free" }
        return "\(Self.dollars(promptPrice)) in · \(Self.dollars(completionPrice)) out per 1M"
    }

    var contextLabel: String {
        contextLength >= 1000 ? "\(contextLength / 1000)K context" : "\(contextLength) context"
    }

    private static func dollars(_ value: Double) -> String {
        value < 0.1 ? String(format: "$%.3f", value) : String(format: "$%.2f", value)
    }
}

enum OpenRouterModels {
    /// Picked for this job — short prompts, strict JSON, many calls a month —
    /// so the list opens on sensible choices rather than on 300 names.
    static let recommended = [
        "openai/gpt-4o-mini",
        "google/gemini-2.5-flash",
        "anthropic/claude-haiku-4.5",
        "openai/gpt-4.1-mini",
        "deepseek/deepseek-chat-v3.1"
    ]

    /// The catalogue is public, so this works before a key is stored.
    static func fetch() async throws -> [AIModel] {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WhistlerAuth.Failure("OpenRouter did not return its model list.")
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            throw WhistlerAuth.Failure("OpenRouter returned an unreadable model list.")
        }
        return items.compactMap(parse).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func parse(_ item: [String: Any]) -> AIModel? {
        guard let id = item["id"] as? String, !id.isEmpty else { return nil }
        let pricing = item["pricing"] as? [String: Any] ?? [:]
        let parameters = item["supported_parameters"] as? [String] ?? []
        return AIModel(
            id: id,
            name: (item["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id,
            promptPrice: perMillion(pricing["prompt"]),
            completionPrice: perMillion(pricing["completion"]),
            contextLength: (item["context_length"] as? NSNumber)?.intValue ?? 0,
            supportsJSON: parameters.contains("response_format") || parameters.contains("structured_outputs"))
    }

    /// Prices arrive as per-token decimal strings; a negative one marks a
    /// router whose price depends on where the request lands.
    private static func perMillion(_ value: Any?) -> Double? {
        let number: Double?
        switch value {
        case let text as String: number = Double(text)
        case let value as NSNumber: number = value.doubleValue
        default: number = nil
        }
        guard let number, number >= 0 else { return nil }
        return number * 1_000_000
    }
}
