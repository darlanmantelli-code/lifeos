import XCTest
import SwiftData
import UIKit
@testable import Livo

final class ReceiptTests: XCTestCase {
    override func tearDown() {
        ReceiptStore.deleteAll()
        super.tearDown()
    }

    func testSaveReadAndDelete() throws {
        let name = try ReceiptStore.save(Data("%PDF-1.4 teste".utf8), ext: "PDF")
        XCTAssertTrue(name.hasSuffix(".pdf"))
        let url = try XCTUnwrap(ReceiptStore.url(name))
        XCTAssertEqual(try Data(contentsOf: url), Data("%PDF-1.4 teste".utf8))
        ReceiptStore.delete([name])
        XCTAssertNil(ReceiptStore.url(name))
    }

    func testUnknownExtensionAndUnsafeNames() throws {
        XCTAssertTrue(try ReceiptStore.save(Data([1]), ext: "exe").hasSuffix(".bin"))
        XCTAssertTrue(try ReceiptStore.save(Data([1]), ext: "../../etc").hasSuffix(".bin"))
        for bad in ["", "../x.pdf", "a/b.pdf", "a\\b.pdf", ".."] {
            XCTAssertFalse(ReceiptStore.isSafe(bad), bad)
            XCTAssertNil(ReceiptStore.url(bad))
        }
    }

    func testPhotosAreDownscaledToJPEG() throws {
        let size = CGSize(width: 4_000, height: 3_000)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let big = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let out = ReceiptsSection.compressed(try XCTUnwrap(big.pngData()))
        let image = try XCTUnwrap(UIImage(data: out))
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height) * image.scale, 2_400)
        XCTAssertLessThan(out.count, try XCTUnwrap(big.pngData()).count)
    }

    @MainActor
    func testTransactionReceiptsAndCleanupOnDeleteAndWipe() throws {
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        let conta = Account(name: "Conta", kind: .corrente)
        ctx.insert(conta)
        let t = FinanceStore.insert(.init(kind: .despesa, amountCents: 1_000, title: "Nota", date: .now, account: conta), in: ctx)[0]
        let a = try ReceiptStore.save(Data([1, 2, 3]), ext: "jpg")
        let b = try ReceiptStore.save(Data([4, 5, 6]), ext: "pdf")
        t.receipts = [a, b]
        XCTAssertEqual(t.receipts, [a, b])
        XCTAssertEqual(t.receiptsRaw, "\(a)\n\(b)")

        try FinanceStore.delete(t, includingFuture: false, in: ctx)
        XCTAssertNil(ReceiptStore.url(a))
        XCTAssertNil(ReceiptStore.url(b))

        let c = try ReceiptStore.save(Data([7]), ext: "png")
        try BackupStore.wipe(ctx)
        XCTAssertNil(ReceiptStore.url(c)) // "apagar tudo" removes attachments too
    }
}
