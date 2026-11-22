import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Import a bank statement (OFX or CSV) into one account, with a preview before anything is saved.
struct ImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Account> { $0.archived == false }, sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \FinanceCategory.name) private var categories: [FinanceCategory]

    @State private var account: Account?
    @State private var positiveIsExpense = false
    @State private var lines: [StatementLine] = []
    @State private var candidates: [StatementImporter.Candidate] = []
    @State private var fileName = ""
    @State private var showPicker = false
    @State private var error: String?

    private static let types: [UTType] = [.commaSeparatedText, .plainText, .text, UTType(filenameExtension: "ofx") ?? .data, .data]

    private var selectedCount: Int { candidates.filter(\.include).count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Conta", selection: $account) {
                        Text("Selecione").tag(Account?.none)
                        ForEach(accounts) { Text($0.name).tag(Optional($0)) }
                    }
                    Button(fileName.isEmpty ? "Escolher arquivo OFX ou CSV" : fileName, systemImage: "doc.badge.plus") { showPicker = true }
                    Toggle("Valores positivos são despesas", isOn: $positiveIsExpense)
                } footer: {
                    Text("Ative para faturas de cartão que listam compras com valor positivo. Nada é gravado antes de você confirmar. Lançamentos já importados nesta conta aparecem como duplicados.")
                }

                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.lifeExpense) }
                }

                if !candidates.isEmpty {
                    Section("\(selectedCount) de \(candidates.count) selecionados") {
                        ForEach($candidates) { $c in
                            HStack(alignment: .top, spacing: 12) {
                                Button { c.include.toggle() } label: {
                                    Image(systemName: c.include ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(c.include ? Color.lifeAccent : Color.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(c.include ? "Não importar" : "Importar")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(c.line.description).lineLimit(2)
                                    Text(c.line.date.formatted(.dateTime.day().month().year().locale(.ptBR)) + (c.duplicate ? " · duplicado" : ""))
                                        .font(.caption).foregroundStyle(c.duplicate ? Color.orange : Color.secondary)
                                    Menu {
                                        Button("Sem categoria") { c.category = nil }
                                        ForEach(categories.filter { $0.kind == (isExpense(c.line) ? .despesa : .receita) }) { cat in
                                            Button(cat.displayName) { c.category = cat }
                                        }
                                    } label: {
                                        Label(c.category?.displayName ?? "Sem categoria", systemImage: "tag").font(.caption)
                                    }
                                }
                                Spacer()
                                Text((isExpense(c.line) ? "−" : "+") + Money.format(abs(c.line.amountCents)))
                                    .monospacedDigit()
                                    .foregroundStyle(isExpense(c.line) ? Color.primary : Color.lifeIncome)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Importar extrato")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importar \(selectedCount)") { commit() }
                        .disabled(selectedCount == 0 || account == nil)
                }
            }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: Self.types) { result in load(result) }
            .onAppear { account = account ?? accounts.first }
            .onChange(of: account) { _, _ in rebuild() }
            .onChange(of: positiveIsExpense) { _, _ in rebuild() }
        }
    }

    private func isExpense(_ l: StatementLine) -> Bool { positiveIsExpense ? l.amountCents > 0 : l.amountCents < 0 }

    private func load(_ result: Result<URL, Error>) {
        error = nil
        guard case .success(let url) = result else { error = StatementImportError.unreadable.errorDescription; return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            lines = try StatementParser.parse(try Data(contentsOf: url))
            fileName = url.lastPathComponent
            rebuild()
        } catch {
            lines = []
            candidates = []
            self.error = (error as? LocalizedError)?.errorDescription ?? StatementImportError.unreadable.errorDescription
        }
    }

    private func rebuild() {
        guard let account, !lines.isEmpty else { candidates = []; return }
        candidates = StatementImporter.candidates(lines, account: account, positiveIsExpense: positiveIsExpense, in: context)
    }

    private func commit() {
        guard let account else { return }
        StatementImporter.commit(candidates, account: account, positiveIsExpense: positiveIsExpense, in: context)
        dismiss()
    }
}
