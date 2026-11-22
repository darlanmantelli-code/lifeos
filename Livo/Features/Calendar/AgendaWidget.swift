import SwiftUI

struct AgendaWidget: View {
    @State private var authorized = CalendarService.eventsAuthorized
    @State private var events: [AgendaEvent] = []

    var body: some View {
        WidgetCard(.agenda) {
            if !authorized {
                Text("Conecte o Calendário para ver seus próximos compromissos aqui.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Conectar calendário", systemImage: "calendar.badge.plus") {
                    Task {
                        authorized = await CalendarService.requestEvents()
                        load()
                    }
                }
                .buttonStyle(.bordered)
            } else if events.isEmpty {
                Text("Nenhum compromisso nos próximos 7 dias.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(events.prefix(5)) { e in
                    HStack(spacing: 10) {
                        Circle().fill(e.color).frame(width: 8, height: 8).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title).lineLimit(1)
                            Text(when(e)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .task { load() }
    }

    private func load() {
        events = CalendarService.upcoming()
    }

    private func when(_ e: AgendaEvent) -> String {
        let cal = Calendar.ptBR
        let day = cal.isDateInToday(e.start) ? "Hoje" : cal.isDateInTomorrow(e.start) ? "Amanhã"
            : e.start.formatted(.dateTime.weekday(.abbreviated).day().month().locale(.ptBR))
        return e.isAllDay ? "\(day) · dia inteiro" : "\(day) · \(e.start.formatted(.dateTime.hour().minute().locale(.ptBR)))"
    }
}
