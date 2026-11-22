import SwiftUI
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

/// "Comprovantes" section of the transaction form: add a photo or a PDF/image file, preview it, remove it.
/// `names` are the receipt files of this transaction; `added` tracks files created in this editing session so the
/// form can delete them again if it is cancelled.
struct ReceiptsSection: View {
    @Binding var names: [String]
    @Binding var added: [String]

    @State private var photo: PhotosPickerItem?
    @State private var showFiles = false
    @State private var preview: URL?
    @State private var error: String?

    private static let maxBytes = 15 * 1_024 * 1_024

    var body: some View {
        Section {
            ForEach(names, id: \.self) { name in
                HStack {
                    Button {
                        preview = ReceiptStore.url(name)
                    } label: {
                        Label(name.hasSuffix(".pdf") ? "Comprovante em PDF" : "Comprovante em imagem",
                              systemImage: name.hasSuffix(".pdf") ? "doc.richtext" : "photo")
                    }
                    .tint(.primary)
                    Spacer()
                    Button(role: .destructive) {
                        names.removeAll { $0 == name }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remover comprovante")
                }
            }
            PhotosPicker(selection: $photo, matching: .images) {
                Label("Adicionar foto", systemImage: "photo.badge.plus")
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    defer { photo = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        error = "Não foi possível ler a foto."
                        return
                    }
                    attach(data, ext: "jpg", isImage: true)
                }
            }
            Button("Adicionar arquivo (PDF ou imagem)", systemImage: "doc.badge.plus") { showFiles = true }
                .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image]) { result in
                    importFile(result)
                }
                .quickLookPreview($preview)
            if let error {
                Text(error).font(.footnote).foregroundStyle(Color.lifeExpense)
            }
        } header: {
            Text("Comprovantes")
        } footer: {
            Text("Ficam só neste iPhone, protegidos enquanto ele estiver bloqueado. Não entram na exportação nem na sincronização.")
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        error = nil
        guard case .success(let url) = result else {
            error = "Não foi possível abrir o arquivo."
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            error = "Não foi possível ler o arquivo."
            return
        }
        let ext = url.pathExtension.lowercased()
        attach(data, ext: ext, isImage: ext != "pdf")
    }

    private func attach(_ data: Data, ext: String, isImage: Bool) {
        error = nil
        guard data.count <= Self.maxBytes else {
            error = "Arquivo grande demais (máximo de 15 MB)."
            return
        }
        do {
            let stored = isImage ? Self.compressed(data) : data
            let name = try ReceiptStore.save(stored, ext: isImage ? "jpg" : ext)
            names.append(name)
            added.append(name)
        } catch {
            self.error = "Não foi possível salvar o comprovante."
        }
    }

    /// Photos are downscaled to 2400 px on the long side and stored as JPEG to keep the files small.
    static func compressed(_ data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 2_400 / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = scale < 1
            ? UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            : image
        return resized.jpegData(compressionQuality: 0.85) ?? data
    }
}
