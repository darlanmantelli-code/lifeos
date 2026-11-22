import SwiftUI
import SwiftData

struct AssistantView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(AssistantClient.urlKey) private var urlString = ""
    @State private var session = AssistantSession()
    @State private var input = ""
    @State private var showSettings = false
    @State private var configured = AssistantClient.configured() != nil
    @FocusState private var focused: Bool

    private let examples = [
        "Quanto gastei em alimentação neste mês?",
        "Registre uma despesa de R$ 75 em combustível.",
        "Organize minhas tarefas de amanhã.",
        "Resuma minha semana.",
        "Quanto preciso economizar para atingir minha meta?",
        "Como está minha evolução nos exercícios?",
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if session.transcript.isEmpty { intro }
                            ForEach(session.transcript) { bubble($0).id($0.id) }
                            if let p = session.pending { ConfirmCard(action: p) { session.resolve($0) } }
                            if session.isWorking && session.pending == nil {
                                ProgressView("Pensando…").padding(.vertical, Spacing.s)
                            }
                            if let e = session.error {
                                Label(e, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(Color.lifeExpense)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: session.transcript.count) { _, _ in withAnimation { proxy.scrollTo("bottom") } }
                    .onChange(of: session.pending) { _, _ in withAnimation { proxy.scrollTo("bottom") } }
                }
                inputBar
            }
            .background(Color.lifeCanvas)
            .navigationTitle("livo IA")
            .brandScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Nova conversa", systemImage: "square.and.pencil") { session.reset() }
                        NavigationLink { AIActionLogView() } label: { Label("Histórico de ações", systemImage: "clock") }
                        Button("Configurar servidor", systemImage: "server.rack") { showSettings = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Opções do assistente")
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: { configured = AssistantClient.configured() != nil }) {
                AssistantSettingsView()
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            LivoMark().frame(width: 64)
            Text("Pergunte sobre suas finanças, tarefas, hábitos, metas, compras e saúde.")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.lifeInk)
            Text("O livo IA lê só o necessário dos seus registros, separa dados reais de estimativas e pede sua confirmação antes de gravar qualquer coisa.")
                .font(.subheadline).foregroundStyle(.secondary)
            if !configured {
                Button("Configurar servidor do livo IA") { showSettings = true }
                    .buttonStyle(.borderedProminent)
            }
            ForEach(examples, id: \.self) { e in
                Button { input = e; focused = true } label: {
                    Text(e).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(Color.lifeAccent)
            }
        }
        .padding(.top, Spacing.l)
    }

    @ViewBuilder
    private func bubble(_ item: ChatItem) -> some View {
        switch item.kind {
        case .user:
            Text(item.text)
                .padding(12)
                .background(Color.lifeAccent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 48)
        case .assistant:
            Text((try? AttributedString(markdown: item.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(item.text))
                .textSelection(.enabled)
                .padding(12)
                .background(Color.lifeSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.lifeHairline, lineWidth: 1))
                .padding(.trailing, 32)
        case .tool:
            Label(item.text, systemImage: "checkmark.seal").font(.caption).foregroundStyle(.secondary)
        case .notice:
            Label(item.text, systemImage: "info.circle").font(.caption).foregroundStyle(.orange)
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Pergunte ou peça algo…", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(10)
                .background(Color.lifeSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.lifeHairline, lineWidth: 1))
            Button {
                let text = input
                input = ""
                Task { await session.send(text, in: context) }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 34))
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || session.isWorking)
            .accessibilityLabel("Enviar")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct ConfirmCard: View {
    let action: PendingAction
    let onDecide: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Confirmar ação", systemImage: "hand.raised").font(.headline).foregroundStyle(Color.lifeAccent)
            Text(action.summary)
            HStack {
                Button("Recusar", role: .cancel) { onDecide(false) }.buttonStyle(.bordered)
                Spacer()
                Button("Confirmar") { onDecide(true) }.buttonStyle(.borderedProminent)
            }
        }
        .card()
        .sensoryFeedback(.warning, trigger: action.id)
    }
}

struct AssistantSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AssistantClient.urlKey) private var urlString = ""
    @State private var token = Keychain.get(AssistantClient.tokenKey) ?? ""

    private var urlValid: Bool {
        guard let u = URL(string: urlString) else { return false }
        return u.scheme == "https" || u.host() == "localhost"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://seu-servidor.exemplo", text: $urlString)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Token do aparelho", text: $token)
                } footer: {
                    Text("O servidor do livo IA guarda a chave da API e repassa as conversas ao modelo. Seus registros ficam neste iPhone: só os resultados das consultas pedidas pelo assistente são enviados. O token fica no Keychain. Use HTTPS.")
                }
            }
            .navigationTitle("Servidor do livo IA")
            .brandScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        Keychain.set(token.trimmingCharacters(in: .whitespaces), for: AssistantClient.tokenKey)
                        dismiss()
                    }
                    .disabled(!urlValid || token.isEmpty)
                }
            }
        }
    }
}

struct AIActionLogView: View {
    @Query(sort: \AIActionLog.date, order: .reverse) private var logs: [AIActionLog]

    var body: some View {
        List {
            if logs.isEmpty { Text("O assistente ainda não executou nenhuma ação.").foregroundStyle(.secondary) }
            ForEach(logs) { l in
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.summary)
                    Text("\(l.status) · \(l.date.formatted(.dateTime.day().month().hour().minute().locale(.ptBR)))")
                        .font(.caption)
                        .foregroundStyle(l.status == "erro" ? Color.lifeExpense : Color.secondary)
                }
            }
        }
        .navigationTitle("Histórico de ações")
        .brandScreen()
    }
}
