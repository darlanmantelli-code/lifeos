import SwiftUI

/// Temporary home: greeting + menu geral. The widget dashboard replaces the placeholder section in stage 4.
struct HomeView: View {
    private var greeting: String {
        switch Calendar.ptBR.component(.hour, from: .now) {
        case 5..<12: "Bom dia"
        case 12..<18: "Boa tarde"
        default: "Boa noite"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greeting).font(.largeTitle.bold())
                        Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.ptBR)).capitalized)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, Spacing.s)
                    .listRowBackground(Color.clear)
                }
                Section("Módulos") {
                    NavigationLink { ShoppingHomeView() } label: { Label("Compras", systemImage: "cart") }
                    NavigationLink { HealthView() } label: { Label("Saúde", systemImage: "heart") }
                }
                Section {
                    Text("O painel com widgets chega na etapa 4.").foregroundStyle(.secondary)
                } footer: {
                    Text("livo · sua vida mais inteligente")
                }
            }
            .navigationTitle("Início")
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
