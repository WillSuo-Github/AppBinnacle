import Foundation

/// A calendar day with no time zone attached, such as 2026-10-12.
struct Day: Hashable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    private static let utc = TimeZone(secondsFromGMT: 0)!

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }()

    init?(year: Int, month: Int, day: Int) {
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: Self.utcCalendar) else { return nil }
        self.init(validYear: year, month: month, day: day)
    }

    private init(validYear year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(validYear: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    /// Parses yyyy-MM-dd.
    init?(iso string: String) {
        let parts = string.trimmed.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// Parses yyyyMMdd, the format of the GA4 date dimension.
    init?(compact string: String) {
        let value = string.trimmed
        guard value.count == 8, value.allSatisfy(\.isNumber),
              let year = Int(value.prefix(4)),
              let month = Int(value.dropFirst(4).prefix(2)),
              let day = Int(value.suffix(2))
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// Parses MM/dd/yyyy, the format used in App Store sales reports.
    init?(slashed string: String) {
        let parts = string.trimmed.split(separator: "/")
        guard parts.count == 3, parts[2].count == 4,
              let month = Int(parts[0]), let day = Int(parts[1]), let year = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    var iso: String { "\(Self.pad(year, 4))-\(Self.pad(month, 2))-\(Self.pad(day, 2))" }
    var compact: String { "\(Self.pad(year, 4))\(Self.pad(month, 2))\(Self.pad(day, 2))" }
    var description: String { iso }

    var startOfDayUTC: Date {
        Self.utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Midnight of this day in the given calendar, used for charts and display.
    func startDate(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? startOfDayUTC
    }

    func adding(days: Int) -> Day {
        let date = Self.utcCalendar.date(byAdding: .day, value: days, to: startOfDayUTC)!
        return Day(date: date, timeZone: Self.utc)
    }

    func distance(to other: Day) -> Int {
        Self.utcCalendar.dateComponents([.day], from: startOfDayUTC, to: other.startOfDayUTC).day ?? 0
    }

    /// Yesterday in Pacific Time, the reporting time zone App Store Connect uses.
    static func yesterday(now: Date = Date(), timeZone: TimeZone = .appStoreReporting) -> Day {
        Day(date: now, timeZone: timeZone).adding(days: -1)
    }

    static func < (lhs: Day, rhs: Day) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}

extension Day: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let day = Day(iso: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected yyyy-MM-dd, found \(string)")
        }
        self = day
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }
}

extension TimeZone {
    static let appStoreReporting = TimeZone(identifier: "America/Los_Angeles")!
}

/// An inclusive range of days.
struct DayRange: Hashable, Sendable, Codable, CustomStringConvertible {
    let start: Day
    let end: Day

    init(start: Day, end: Day) {
        precondition(start <= end, "A day range must not end before it starts.")
        self.start = start
        self.end = end
    }

    init(ending end: Day, length: Int) {
        precondition(length > 0, "A day range needs at least one day.")
        self.init(start: end.adding(days: -(length - 1)), end: end)
    }

    var length: Int { start.distance(to: end) + 1 }
    var days: [Day] { (0..<length).map { start.adding(days: $0) } }
    var previous: DayRange { DayRange(ending: start.adding(days: -1), length: length) }
    var description: String { "\(start.iso) to \(end.iso)" }

    func contains(_ day: Day) -> Bool { day >= start && day <= end }
}
