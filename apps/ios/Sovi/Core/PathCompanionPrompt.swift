import Foundation

extension AppointmentRecord {
    func needsAttendanceCheck(at now: Date) -> Bool {
        status == .confirmed && attendance == .unrecorded && date < now &&
            (checkInDeferredUntil.map { $0 <= now } ?? true)
    }

    func attendanceQuestion(calendar: Calendar, language: ChatLanguage, locale: Locale) -> String {
        var style = Date.FormatStyle().day().month(.abbreviated).hour().minute()
        style.calendar = calendar; style.timeZone = calendar.timeZone; style.locale = locale
        return language.localized("Warst du am \(date.formatted(style)) beim Termin „\(title)“?")
    }
}

extension AppState {
    /// Proactive questions concern the most recent month. A user can still open an older entry directly.
    func pastAppointmentToCheckIn(now: Date) -> PathNode? {
        guard let since = pathCalendar.date(byAdding: .day, value: -30, to: now) else { return nil }
        let eligible = appointments.filter { $0.needsAttendanceCheck(at: now) && $0.date >= since }
        return nodes.compactMap { node -> (node: PathNode, date: Date)? in
            guard let id = node.appointmentID,
                  let record = eligible.first(where: { $0.id == id }) else { return nil }
            return (node, record.date)
        }.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.node.id.uuidString < $1.node.id.uuidString
        }.first?.node
    }
}

/// A read-only invitation, based only on dated local entries. It never records
/// attendance, completes a task or schedules a notification.
struct PathCompanionPrompt: Equatable {
    var text: String
    var contextID: UUID?

    static func make(state: AppState, now: Date, locale: Locale = .current) -> Self {
        let calendar = state.pathCalendar
        if let node = state.pastAppointmentToCheckIn(now: now),
           let record = state.appointments.first(where: { $0.id == node.appointmentID }) {
            let language = locale.language.languageCode.flatMap { ChatLanguage(rawValue: $0.identifier) } ?? .app
            return Self(text: record.attendanceQuestion(calendar: calendar, language: language, locale: locale), contextID: node.id)
        }
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 30, to: now) ?? now
        let endDay = calendar.startOfDay(for: end)
        struct Candidate {
            var node: PathNode
            var date: Date
            var orderDate: Date
            var isAppointment: Bool
        }
        var candidates: [Candidate] = []
        for node in state.nodes {
            if let id = node.appointmentID {
                guard let appointment = state.appointments.first(where: { $0.id == id }),
                      appointment.status == .confirmed, appointment.attendance == .unrecorded,
                      appointment.date >= now, appointment.date <= end else { continue }
                candidates.append(Candidate(node: node, date: appointment.date,
                                            orderDate: appointment.date, isAppointment: true))
            } else if node.kind == .task,
                      node.taskStatus != .completed, node.taskStatus != .cancelled,
                      node.history?.linkedTaskID == nil, let date = node.date {
                let day = calendar.startOfDay(for: date)
                guard day >= today, day <= endDay else { continue }
                // A task's calendar date has no invented appointment time.
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day
                candidates.append(Candidate(node: node, date: day,
                                            orderDate: dayEnd, isAppointment: false))
            }
        }
        guard let next = candidates.sorted(by: {
            if $0.orderDate != $1.orderDate { return $0.orderDate < $1.orderDate }
            return $0.node.id.uuidString < $1.node.id.uuidString
        }).first else {
            return Self(text: String(localized: "Wie läuft’s bei dir?", locale: locale), contextID: nil)
        }
        let title = next.node.displayTitle
        if next.isAppointment {
            var time = Date.FormatStyle().hour().minute()
            time.calendar = calendar; time.timeZone = calendar.timeZone; time.locale = locale
            let hour = next.date.formatted(time)
            if calendar.isDate(next.date, inSameDayAs: now) {
                return Self(text: String(localized: "Heute um \(hour): \(title).", locale: locale), contextID: next.node.id)
            }
            let date = formattedDay(next.date, calendar: calendar, locale: locale)
            return Self(text: String(localized: "Am \(date) um \(hour): \(title).", locale: locale), contextID: next.node.id)
        }
        if calendar.isDate(next.date, inSameDayAs: now) {
            return Self(text: String(localized: "Heute offen: \(title).", locale: locale), contextID: next.node.id)
        }
        let date = formattedDay(next.date, calendar: calendar, locale: locale)
        return Self(text: String(localized: "Am \(date): \(title).", locale: locale), contextID: next.node.id)
    }

    private static func formattedDay(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        var style = Date.FormatStyle().day().month(.abbreviated)
        style.calendar = calendar; style.timeZone = calendar.timeZone; style.locale = locale
        return date.formatted(style)
    }
}
