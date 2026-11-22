import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(AppLock.enabledKey) private var lockEnabled = false
    @AppStorage(DemoMode.key) private var demo = false
    @AppStorage(HealthSync.autoKey) private var healthAuto = false

    @State private var exportURL: URL?
    @State private var message: String?
    @State private var showMessage = false
    @State private var showImporter = false
    @State private var pendingRestore: Data?
    @State private var confirmRestore = false
    @State private var showWipe = false
    @State private var wipeText = ""

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        List {
            Section {
                Toggle("Bloquear com Face ID", isOn: $lockEnabled)
            } header: {
                Text("Segurança")
            } footer: {
                Text("Pede Face ID (ou o código do iPhone) ao voltar para o app. O conteúdo também fica oculto na troca de apps.")
            }

            Section {
                Button("Gerar arquivo de exportação", systemImage: "square.and.arrow.up") { export() }
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Compartilhar \(exportURL.lastPathComponent)", systemImage: "doc") }
                }
                Button("Restaurar backup…", systemImage: "arrow.counterclockwise") { showImporter = true }
            } header: {
                Text("Seus dados")
            } footer: {
                Text("A exportação é um arquivo JSON com todos os seus registros, para backup ou para levar a outro app. Guarde-o em local seguro: ele não é criptografado. O backup do iPhone/iCloud também inclui os dados do app.")
            }

            if HealthSync.isAvailable {
                Section {
                    Toggle("Atualizar do app Saúde ao abrir", isOn: $healthAuto)
                } header: {
                    Text("Integrações")
                } footer: {
                    Text("Lê os últimos 7 dias do app Saúde sempre que você abre o livo. Somente leitura; você escolhe os tipos de dados na tela de permissão do iOS.")
                }
            }

            Section {
                Toggle("Modo demonstração", isOn: $demo)
            } footer: {
                Text("Mostra dados fictícios para conhecer o app. Seus dados reais não são tocados e voltam ao desativar.")
            }

            Section {
                NavigationLink { AssistantSettingsView() } label: { Label("Servidor do livo IA", systemImage: "server.rack") }
                NavigationLink { AIActionLogView() } label: { Label("Histórico de ações da IA", systemImage: "clock") }
            } header: {
                Text("Assistente")
            } footer: {
                Text("O assistente recebe apenas os resultados das consultas que ele pede (por exemplo, totais do mês), nunca o banco inteiro. Toda gravação pede sua confirmação.")
            }

            Section {
                Button("Apagar todos os dados", systemImage: "trash", role: .destructive) {
                    wipeText = ""
                    showWipe = true
                }
                .disabled(demo)
            } footer: {
                Text(demo ? "Desative o modo demonstração para apagar seus dados reais." : "Remove todos os registros deste aparelho. Não pode ser desfeito; exporte antes se quiser guardar.")
            }

            Section {
                LabeledContent("Versão", value: version)
            } footer: {
                Text("livo · sua vida mais inteligente\nSeus dados ficam neste iPhone. Nada é enviado sem uma ação sua (assistente) e nenhuma conta bancária é acessada.")
            }
        }
        .navigationTitle("Configurações")
        .onChange(of: healthAuto) { _, on in
            if on { Task { do { try await HealthSync.requestAccess() } catch { healthAuto = false; show("Não foi possível acessar o app Saúde.") } } }
        }
        .onChange(of: lockEnabled) { _, on in
            if on && !AppLock.canUse() {
                lockEnabled = false
                show("Ative um código ou Face ID nos Ajustes do iPhone para usar o bloqueio.")
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    pendingRestore = try Data(contentsOf: url)
                    confirmRestore = true
                } catch {
                    show("Não foi possível ler o arquivo.")
                }
            case .failure:
                show("Não foi possível abrir o arquivo.")
            }
        }
        .confirmationDialog("Substituir todos os dados pelo backup?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restaurar", role: .destructive) { restore() }
            Button("Cancelar", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("Os registros atuais deste aparelho serão apagados e trocados pelos do arquivo.")
        }
        .alert("Apagar todos os dados?", isPresented: $showWipe) {
            TextField("Digite APAGAR", text: $wipeText)
            Button("Apagar", role: .destructive) { wipe() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Digite APAGAR para confirmar. Esta ação não pode ser desfeita.")
        }
        .alert("livo", isPresented: $showMessage) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func show(_ text: String) {
        message = text
        showMessage = true
    }

    private func export() {
        do {
            exportURL = try BackupStore.exportFile(context)
        } catch {
            show("Falha ao exportar: \(error.localizedDescription)")
        }
    }

    private func restore() {
        guard let data = pendingRestore else { return }
        pendingRestore = nil
        do {
            try BackupStore.restore(data, into: context)
            show("Backup restaurado.")
        } catch {
            show(error.localizedDescription)
        }
    }

    private func wipe() {
        guard wipeText.trimmingCharacters(in: .whitespaces).uppercased() == "APAGAR" else {
            show("Confirmação incorreta. Nada foi apagado.")
            return
        }
        do {
            try BackupStore.wipe(context)
            FinanceStore.seedCategoriesIfNeeded(context)
            show("Todos os dados foram apagados.")
        } catch {
            show("Falha ao apagar: \(error.localizedDescription)")
        }
    }
}
