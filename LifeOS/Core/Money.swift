import Foundation

/// Money is stored as Int64 cents everywhere. Never Double.
enum Money {
    static func format(_ cents: Int64) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: "BRL").locale(.ptBR))
    }

    /// Parses Brazilian input: "75", "75,5", "1.234,56", "R$ 1.234,56", "-10,00".
    /// "." is always a thousands separator, "," the decimal separator.
    static func parse(_ text: String) -> Int64? {
        var s = text.replacingOccurrences(of: "R$", with: "")
            .filter { !$0.isWhitespace }
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !s.isEmpty, s.filter({ $0 == "." }).count <= 1 else { return nil }
        if s.hasPrefix(".") { s = "0" + s }
        guard s.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }),
              let value = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        var cents = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &cents, 0, .bankers)
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}
