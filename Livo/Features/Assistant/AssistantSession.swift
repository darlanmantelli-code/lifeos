import Foundation
import SwiftData

struct TurnResponse: Decodable, Sendable {
    let content: [JSONValue]
    let stop_reason: String?
    let model: String
}

enum AssistantError: LocalizedError {
    case notConfigured, server(String), invalidResponse
    var errorDescription: String? {
        switch self {
        case .notConfigured: "Configure o endereço e o token do servidor do livo IA."
        case .server(let m): m
        case .invalidResponse: "Resposta inválida do servidor."
        }
    }
}

/// POSTs the whole conversation to the livo IA backend and returns one assistant turn.
struct AssistantClient: Sendable {
    let baseURL: URL
    let token: String

    static let urlKey = "ai.url"
    static let tokenKey = "ai.token"

    static func configured() -> AssistantClient? {
        guard let raw = UserDefaults.standard.string(forKey: urlKey), let url = URL(string: raw),
              url.scheme == "https" || url.host() == "localhost",
              let token = Keychain.get(tokenKey), !token.isEmpty else { return nil }
        return AssistantClient(baseURL: url, token: token)
    }

    func turn(_ messages: [JSONValue]) async throws -> TurnResponse {
        var req = URLRequest(url: baseURL.appending(path: "v1/assistant/turn"))
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(["messages": messages])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AssistantError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(JSONValue.self, from: data))?["detail"]?.string
            throw AssistantError.server(detail ?? "Erro do servidor (\(http.statusCode)).")
        }
        return try JSONDecoder().decode(TurnResponse.self, from: data)
    }
}

struct ChatItem: Identifiable, Equatable {
    enum Kind: Equatable { case user, assistant, tool, notice }
    let id = UUID()
    let kind: Kind
    let text: String
}

struct PendingAction: Identifiable, Equatable {
    let id: String
    let tool: String
    let summary: String
}

/// Runs the tool loop: the model asks for tools, the app runs them locally (writes only after the
/// user confirms), sends the results back, until the model answers. Assistant content is stored
/// exactly as received so it can be echoed back unchanged.
@MainActor
@Observable
final class AssistantSession {
    typealias Transport = @Sendable ([JSONValue]) async throws -> TurnResponse

    private(set) var transcript: [ChatItem] = []
    private(set) var messages: [JSONValue] = []
    private(set) var pending: PendingAction?
    private(set) var isWorking = false
    var error: String?

    @ObservationIgnored private var confirmation: CheckedContinuation<Bool, Never>?
    static let maxRounds = 8

    func reset() {
        resolve(false)
        transcript = []
        messages = []
        error = nil
    }

    func resolve(_ approved: Bool) {
        let c = confirmation
        confirmation = nil
        pending = nil
        c?.resume(returning: approved)
    }

    func send(_ text: String, in ctx: ModelContext, transport: Transport? = nil, now: Date = .now) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isWorking else { return }
        let turn: Transport
        if let transport {
            turn = transport
        } else if let client = AssistantClient.configured() {
            turn = { try await client.turn($0) }
        } else {
            error = AssistantError.notConfigured.errorDescription
            return
        }
        error = nil
        let stamp = now.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().hour().minute().locale(.ptBR))
        messages.append(["role": "user", "content": .string("\(stamp)\n\(trimmed)")])
        transcript.append(ChatItem(kind: .user, text: trimmed))
        isWorking = true
        defer { isWorking = false }

        do {
            for _ in 0..<Self.maxRounds {
                let response = try await turn(messages)
                messages.append(["role": "assistant", "content": .array(response.content)])
                for block in response.content where block["type"]?.string == "text" {
                    if let t = block["text"]?.string, !t.isEmpty { transcript.append(ChatItem(kind: .assistant, text: t)) }
                }
                switch response.stop_reason {
                case "tool_use":
                    messages.append(["role": "user", "content": .array(await runTools(response.content, ctx))])
                case "pause_turn":
                    continue
                case "refusal":
                    transcript.append(ChatItem(kind: .notice, text: "O assistente não pôde atender a este pedido."))
                    return
                case "max_tokens":
                    transcript.append(ChatItem(kind: .notice, text: "Resposta interrompida por tamanho."))
                    return
                default:
                    return
                }
            }
            transcript.append(ChatItem(kind: .notice, text: "Parei após \(Self.maxRounds) etapas. Reformule o pedido se precisar."))
        } catch {
            // Drop the dangling user turn so the conversation stays valid for the next request.
            if case .object(let o)? = messages.last, o["role"]?.string == "user" { messages.removeLast() }
            self.error = error.localizedDescription
        }
    }

    /// All tool results for one assistant turn go back in a single user message.
    private func runTools(_ content: [JSONValue], _ ctx: ModelContext) async -> [JSONValue] {
        var results: [JSONValue] = []
        for block in content where block["type"]?.string == "tool_use" {
            let id = block["id"]?.string ?? ""
            let name = block["name"]?.string ?? ""
            let input = block["input"] ?? [:]
            let summary = AssistantTools.describe(name, input)

            if AssistantTools.needsConfirmation(name) {
                let approved = await withCheckedContinuation { c in
                    confirmation = c
                    pending = PendingAction(id: id, tool: name, summary: summary)
                }
                guard approved else {
                    log(name, summary, "recusada", ctx)
                    transcript.append(ChatItem(kind: .tool, text: "Recusado: \(summary)"))
                    results.append(["type": "tool_result", "tool_use_id": .string(id),
                                    "content": "O usuário recusou esta ação. Não tente novamente sem um novo pedido."])
                    continue
                }
            }
            do {
                let output = try AssistantTools.run(name, input, in: ctx)
                log(name, summary, "executada", ctx)
                if AssistantTools.needsConfirmation(name) { transcript.append(ChatItem(kind: .tool, text: "Feito: \(summary)")) }
                results.append(["type": "tool_result", "tool_use_id": .string(id), "content": .string(output.text)])
            } catch {
                let message = (error as? AssistantTools.ToolError)?.message ?? error.localizedDescription
                log(name, "\(summary) — \(message)", "erro", ctx)
                results.append(["type": "tool_result", "tool_use_id": .string(id), "content": .string(message), "is_error": true])
            }
        }
        return results
    }

    private func log(_ tool: String, _ summary: String, _ status: String, _ ctx: ModelContext) {
        ctx.insert(AIActionLog(tool: tool, summary: summary, status: status))
    }
}
