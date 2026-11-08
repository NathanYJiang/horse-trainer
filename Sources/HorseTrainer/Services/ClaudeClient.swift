import Foundation
import PokerCore

enum ClaudeError: LocalizedError {
    case noKey
    case http(Int, String)
    case refusal(String)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .noKey: "No Anthropic API key. Add one in Settings, or set ANTHROPIC_API_KEY."
        case .http(let code, let body): "HTTP \(code): \(body.prefix(400))"
        case .refusal(let why): "Claude declined this request\(why.isEmpty ? "" : " (\(why))")."
        case .api(let msg): msg
        }
    }
}

/// Minimal Messages API client (raw HTTP; there is no official Swift SDK). Streams text deltas.
struct ClaudeClient: Sendable {
    static let models = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]
    static let fallbackModels: Set<String> = ["claude-opus-5-5", "claude-sonnet-5-5"]

    let apiKey: String
    let model: String
    let effort: String

    static func resolveKey(_ stored: String) -> String? {
        if !stored.isEmpty { return stored }
        if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty { return env }
        return nil
    }

    func stream(system: String, prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    req.httpMethod = "POST"
                    req.timeoutInterval = 600
                    req.setValue("application/json", forHTTPHeaderField: "content-type")
                    req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
                    var body: [String: Any] = [
                        "model": model,
                        "max_tokens": 16000,
                        "stream": true,
                        "system": system,
                        "output_config": ["effort": effort],
                        "messages": [["role": "user", "content": prompt]],
                    ]
                    if Self.fallbackModels.contains(model) {
                        // Server-side refusal fallback: retries a declined request on the recommended model.
                        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
                        body["fallbacks"] = "default"
                    }
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if code != 200 {
                        var text = ""
                        for try await line in bytes.lines { text += line }
                        throw ClaudeError.http(code, text)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: "), let data = line.dropFirst(6).data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = obj["type"] as? String else { continue }
                        switch type {
                        case "content_block_delta":
                            if let delta = obj["delta"] as? [String: Any], delta["type"] as? String == "text_delta", let t = delta["text"] as? String {
                                continuation.yield(t)
                            }
                        case "message_delta":
                            if let delta = obj["delta"] as? [String: Any], delta["stop_reason"] as? String == "refusal" {
                                let details = delta["stop_details"] as? [String: Any]
                                throw ClaudeError.refusal(details?["category"] as? String ?? "")
                            }
                        case "error":
                            let err = obj["error"] as? [String: Any]
                            throw ClaudeError.api(err?["message"] as? String ?? "Unknown API error")
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static var systemPrompt: String {
        var s = """
        You are a live poker coach for $1/$2 No-Limit Hold'em cash games. Your style follows the exploitative, player-type-driven school \
        (Hungry Horse Poker, Sao Costa, and similar live-focused coaches): classify the opponent, then pick the exploit. \
        Ignore GTO solver jargon unless it helps. Be concrete about sizes in dollars and as a percent of the pot. \
        Use "the inverse question" when it fits: if villain had X here, how would they have played or bet it? Then do the same for the hero's own range. \
        Write in short sections with markdown headings and bullets. Keep it under about 350 words unless asked for more. \
        Be direct. If the hero played well, say so. If the rule-based coach's grade is debatable, say why.

        PLAYER TYPES
        """
        for t in PlayerType.allCases {
            let pb = TypePlaybook.of(t)
            s += "\n- \(t.name): \(t.oneLiner) Exploits: \(pb.exploits.joined(separator: "; "))."
        }
        s += "\n\nPRINCIPLES\n"
        for p in Principle.allCases {
            s += "- \(p.title): \(p.summary)\n"
        }
        return s
    }
}
