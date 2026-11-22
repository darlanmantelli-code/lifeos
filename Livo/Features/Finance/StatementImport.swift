import Foundation
import SwiftData

/// One line of a bank statement, before it becomes a FinanceTransaction.
struct StatementLine: Identifiable, Equatable {
    let id: String          // FITID from OFX, or a hash of date|amount|description for CSV
    let date: Date
    let amountCents: Int64  // signed: negative = money out
    let description: String
}

enum StatementImportError: LocalizedError {
    case unreadable, unknownFormat, missingColumns(String), empty
    var errorDescription: String? {
        switch self {
        case .unreadable: "Não foi possível ler o arquivo."
        case .unknownFormat: "Formato não reconhecido. Use OFX ou CSV."
        case .missingColumns(let found): "Não encontrei as colunas de data, descrição e valor. Cabeçalho: \(found)"
        case .empty: "Nenhum lançamento encontrado no arquivo."
        }
    }
}

enum StatementParser {
    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    static func parse(_ data: Data) throws -> [StatementLine] {
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        guard let text else { throw StatementImportError.unreadable }
        let lines = text.uppercased().contains("<STMTTRN>") ? parseOFX(text) : try parseCSV(text)
        guard !lines.isEmpty else { throw StatementImportError.empty }
        return lines
    }

    // MARK: OFX (1.x SGML with unclosed tags, and 2.x XML)

    static func parseOFX(_ text: String) -> [StatementLine] {
        let blocks = text.components(separatedBy: "<STMTTRN>").dropFirst()
        return blocks.compactMap { raw in
            let block = raw.components(separatedBy: "</STMTTRN>")[0]
            func tag(_ name: String) -> String? {
                guard let r = block.range(of: "<\(name)>", options: .caseInsensitive) else { return nil }
                let rest = block[r.upperBound...]
                let value = rest.prefix { $0 != "<" && $0 != "\n" && $0 != "\r" }
                return String(value).trimmingCharacters(in: .whitespaces).nilIfEmpty
            }
            guard let dateRaw = tag("DTPOSTED"), let date = ofxDate(dateRaw),
                  let amountRaw = tag("TRNAMT"), let cents = parseAmount(amountRaw) else { return nil }
            let desc = tag("MEMO") ?? tag("NAME") ?? "Lançamento"
            let id = tag("FITID") ?? syntheticID(date, cents, desc)
            return StatementLine(id: id, date: date, amountCents: cents, description: desc)
        }
    }

    /// "20261105", "20261105120000[-3:BRT]".
    static func ofxDate(_ s: String) -> Date? {
        let digits = s.prefix { $0.isNumber }
        guard digits.count >= 8, let y = Int(digits.prefix(4)), let m = Int(digits.dropFirst(4).prefix(2)),
              let d = Int(digits.dropFirst(6).prefix(2)) else { return nil }
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))
    }

    // MARK: CSV

    static func parseCSV(_ text: String) throws -> [StatementLine] {
        let rows = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let headerLine = rows.first else { throw StatementImportError.empty }
        let delimiter: Character = headerLine.filter { $0 == ";" }.count >= headerLine.filter { $0 == "," }.count ? ";" : ","
        let header = splitCSV(headerLine, delimiter).map { normalize($0) }

        func column(_ names: [String]) -> Int? {
            header.firstIndex { h in names.contains { h == $0 || h.hasPrefix($0) } }
        }
        guard let dateCol = column(["data", "date", "dt"]),
              let descCol = column(["descricao", "historico", "lancamento", "title", "estabelecimento", "description", "memo"]),
              let valueCol = column(["valor", "quantia", "amount", "value", "montante"])
        else { throw StatementImportError.missingColumns(headerLine) }

        return rows.dropFirst().compactMap { row in
            let f = splitCSV(row, delimiter)
            guard f.count > max(dateCol, descCol, valueCol),
                  let date = csvDate(f[dateCol]), let cents = parseAmount(f[valueCol]) else { return nil }
            let desc = f[descCol].trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "Lançamento"
            return StatementLine(id: syntheticID(date, cents, desc), date: date, amountCents: cents, description: desc)
        }
    }

    /// Handles quoted fields ("Padaria, centro";-12,50).
    static func splitCSV(_ line: String, _ delimiter: Character) -> [String] {
        var fields: [String] = [], current = "", quoted = false
        for ch in line {
            if ch == "\"" { quoted.toggle() }
            else if ch == delimiter && !quoted { fields.append(current); current = "" }
            else { current.append(ch) }
        }
        fields.append(current)
        return fields.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// dd/MM/yyyy, dd/MM/yy, dd-MM-yyyy or ISO yyyy-MM-dd.
    static func csvDate(_ s: String) -> Date? {
        let parts = s.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0 == "/" || $0 == "-" || $0 == " " || $0 == "T" })
        guard parts.count >= 3, let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]) else { return nil }
        let (y, m, d) = parts[0].count == 4 ? (a, b, c) : (c < 100 ? 2000 + c : c, b, a)
        guard (1...12).contains(m), (1...31).contains(d) else { return nil }
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))
    }

    /// "1.234,56", "-50,00", "R$ 12,90", "12.5" (dot decimal), "-1234.56", "1,234.56".
    static func parseAmount(_ raw: String) -> Int64? {
        var s = raw.replacingOccurrences(of: "R$", with: "").filter { !$0.isWhitespace }
        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") { negative = true; s = String(s.dropFirst().dropLast()) }
        if s.hasPrefix("-") { negative.toggle(); s.removeFirst() } else if s.hasPrefix("+") { s.removeFirst() }
        if s.hasSuffix("-") { negative.toggle(); s.removeLast() }
        let lastComma = s.lastIndex(of: ","), lastDot = s.lastIndex(of: ".")
        let decimalSep: Character?
        switch (lastComma, lastDot) {
        case let (c?, d?): decimalSep = c > d ? "," : "."
        case (_?, nil): decimalSep = ","
        case let (nil, d?): decimalSep = s.distance(from: d, to: s.endIndex) - 1 <= 2 ? "." : nil // "1.234" = thousands
        default: decimalSep = nil
        }
        let normalized = s.compactMap { ch -> Character? in
            if ch.isNumber { return ch }
            return ch == decimalSep ? "." : nil
        }
        guard let value = Decimal(string: String(normalized), locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        var cents = value * 100, rounded = Decimal()
        NSDecimalRound(&rounded, &cents, 0, .plain)
        let v = NSDecimalNumber(decimal: rounded).int64Value
        return negative ? -v : v
    }

    static func syntheticID(_ date: Date, _ cents: Int64, _ desc: String) -> String {
        "\(Int(date.timeIntervalSince1970 / 86_400))|\(cents)|\(normalize(desc))"
    }

    /// Lowercased, without accents or extra spaces: "Histórico " → "historico".
    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .ptBR)
            .lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// Suggests a category for an imported line. Learned matches (the user's own past entries) win over keywords.
enum CategorySuggester {
    static let keywords: [(String, [String])] = [
        ("Transporte", ["posto", "combust", "ipiranga", "shell", "uber", "99app", "99 ", "estaciona", "pedagio", "sem parar", "metro", "onibus"]),
        ("Alimentação", ["ifood", "restaurante", "padaria", "mercado", "supermerc", "acougue", "lanchonete", "pizzaria", "hortifruti", "atacad", "rappi"]),
        ("Assinaturas", ["netflix", "spotify", "disney", "prime video", "amazon prime", "youtube", "hbo", "max.com", "icloud", "apple.com", "google one"]),
        ("Saúde", ["farmacia", "drogaria", "droga", "raia", "pague menos", "hospital", "clinica", "laborat", "academia", "smart fit"]),
        ("Moradia", ["aluguel", "condominio", "energia", "enel", "cemig", "copel", "sabesp", "agua", "gas ", "internet", "vivo", "claro", "tim "]),
        ("Educação", ["escola", "faculdade", "curso", "udemy", "alura", "livraria"]),
        ("Lazer", ["cinema", "ingresso", "show", "steam", "playstation", "xbox", "bar "]),
        ("Impostos e taxas", ["iof", "tarifa", "anuidade", "juros", "imposto", "iptu", "ipva", "darf"]),
        ("Salário", ["salario", "folha", "pagamento de salario"]),
        ("Rendimentos", ["rendimento", "dividendo", "juros sobre capital", "resgate"]),
    ]

    static func suggest(_ description: String, isIncome: Bool, categories: [FinanceCategory], history: [FinanceTransaction]) -> FinanceCategory? {
        let wanted: CategoryKind = isIncome ? .receita : .despesa
        let key = StatementParser.normalize(description)
        if let learned = history.first(where: { $0.category?.kind == wanted && StatementParser.normalize($0.title) == key })?.category {
            return learned
        }
        let padded = key + " "
        for (name, words) in keywords where words.contains(where: { padded.contains($0) }) {
            if let c = categories.first(where: { $0.parent == nil && $0.kind == wanted && $0.name == name }) { return c }
        }
        return nil
    }
}

@MainActor
enum StatementImporter {
    struct Candidate: Identifiable {
        let line: StatementLine
        var include: Bool
        var category: FinanceCategory?
        let duplicate: Bool
        var id: String { line.id }
    }

    /// `positiveIsExpense`: credit-card exports (e.g. Nubank fatura) list purchases as positive numbers.
    static func candidates(_ lines: [StatementLine], account: Account, positiveIsExpense: Bool, in ctx: ModelContext) -> [Candidate] {
        let history = (try? ctx.fetch(FetchDescriptor<FinanceTransaction>())) ?? []
        let categories = (try? ctx.fetch(FetchDescriptor<FinanceCategory>())) ?? []
        let existing = Set(history.filter { $0.account == account }.compactMap(\.externalID))
        return lines.map { line in
            let expense = positiveIsExpense ? line.amountCents > 0 : line.amountCents < 0
            let dup = existing.contains(line.id)
            return Candidate(line: line, include: !dup && line.amountCents != 0,
                             category: CategorySuggester.suggest(line.description, isIncome: !expense, categories: categories, history: history),
                             duplicate: dup)
        }
    }

    @discardableResult
    static func commit(_ candidates: [Candidate], account: Account, positiveIsExpense: Bool, in ctx: ModelContext) -> Int {
        var count = 0
        for c in candidates where c.include && c.line.amountCents != 0 {
            let expense = positiveIsExpense ? c.line.amountCents > 0 : c.line.amountCents < 0
            let created = FinanceStore.insert(TransactionDraft(kind: expense ? .despesa : .receita, amountCents: abs(c.line.amountCents),
                                                               title: c.line.description, date: c.line.date, account: account,
                                                               category: c.category, source: .importacao), in: ctx)
            created.first?.externalID = c.line.id
            count += 1
        }
        return count
    }
}
