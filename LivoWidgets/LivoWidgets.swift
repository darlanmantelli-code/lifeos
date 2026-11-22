import WidgetKit
import SwiftUI

struct SummaryEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry { SummaryEntry(date: .now, snapshot: nil) }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        completion(SummaryEntry(date: .now, snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        // The app reloads the timeline whenever it writes new numbers; this is just a safety refresh.
        let entry = SummaryEntry(date: .now, snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

struct SummaryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SummaryEntry

    var body: some View {
        Group {
            if let s = entry.snapshot {
                if family == .systemSmall { small(s) } else { medium(s) }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    header
                    Text("Abra o app para ver seu resumo aqui.").font(.caption).foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .foregroundStyle(.white)
        .fontDesign(.rounded)
        .containerBackground(for: .widget) {
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(colors: [Color.heroTop, Color.heroBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                LivoMark(style: .mono(Color.white.opacity(0.08)))
                    .frame(width: 120)
                    .offset(x: 34, y: 28)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            LivoMark().frame(height: 14)
            Text("livo").font(.system(size: 15, weight: .heavy, design: .rounded))
        }
    }

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let b = s.balanceCents {
                Text(Money.format(b)).font(.system(size: 20, weight: .heavy, design: .rounded)).monospacedDigit()
                    .minimumScaleFactor(0.6).lineLimit(1).privacySensitive()
            }
            Spacer(minLength: 0)
            Label("\(s.tasksToday) tarefa(s) hoje", systemImage: "checklist").font(.caption)
            Label("\(s.habitsPending) hábito(s) a fazer", systemImage: "repeat").font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ s: WidgetSnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                header
                if let b = s.balanceCents {
                    Text("Saldo").font(.caption2).foregroundStyle(.white.opacity(0.75))
                    Text(Money.format(b)).font(.system(size: 22, weight: .heavy, design: .rounded)).monospacedDigit()
                        .minimumScaleFactor(0.6).lineLimit(1).privacySensitive()
                }
                Text("Despesas do mês").font(.caption2).foregroundStyle(.white.opacity(0.75))
                Text(Money.format(s.monthExpenseCents)).font(.subheadline.weight(.semibold)).monospacedDigit().privacySensitive()
            }
            VStack(alignment: .leading, spacing: 6) {
                Label(s.nextTask ?? "Nenhuma tarefa para hoje", systemImage: "checklist").font(.caption).lineLimit(2)
                Label("\(s.habitsTotal - s.habitsPending)/\(s.habitsTotal) hábitos", systemImage: "repeat").font(.caption)
                if let w = s.waterMl {
                    Label("\(Int(w)) ml" + (s.waterTargetMl.map { " de \(Int($0))" } ?? ""), systemImage: "drop.fill").font(.caption)
                }
                Spacer(minLength: 0)
                Text("Atualizado \(s.updatedAt.formatted(.dateTime.hour().minute().locale(.ptBR)))")
                    .font(.caption2).foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct LivoSummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LivoSummary", provider: SummaryProvider()) { entry in
            SummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("Resumo do livo")
        .description("Saldo, tarefas de hoje, hábitos e água.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct LivoWidgetBundle: WidgetBundle {
    var body: some Widget { LivoSummaryWidget() }
}
