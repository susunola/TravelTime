import Foundation

struct HolidayCountry: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let localName: String

    /// Stable, subdued accents used everywhere a holiday region is shown.
    var accentHex: String {
        switch id {
        case "cn": return "#D35D57"
        case "hk": return "#A85C8E"
        case "sg": return "#2B8A72"
        case "my": return "#5573C8"
        case "th": return "#C58A2A"
        default: return "#7C8580"
        }
    }

    static let common: [HolidayCountry] = [
        .init(id: "cn", name: "China", localName: "中国大陆"),
        .init(id: "hk", name: "Hong Kong", localName: "香港"),
        .init(id: "sg", name: "Singapore", localName: "新加坡"),
        .init(id: "my", name: "Malaysia", localName: "马来西亚"),
        .init(id: "th", name: "Thailand", localName: "泰国")
    ]
}

struct BundledHoliday: Hashable {
    let countryCode: String
    let date: String
    let name: String
    let localName: String
    let note: String
}

/// Offline holiday data shipped with TravelTime. Calendar display no longer
/// depends on credentials, network access, quotas, or a third-party policy.
enum BundledHolidayCatalog {
    static let edition = "2026"
    static let coverageYears: ClosedRange<Int> = 2026...2026
    static let holidays: [BundledHoliday] = entries.flatMap { $0 }

    private static let entries: [[BundledHoliday]] = [
        // China — national statutory holiday periods.
        day("cn", "2026-01-01", "New Year's Day", "元旦"),
        span("cn", 2026, 2, 15...23, "Spring Festival", "春节"),
        span("cn", 2026, 4, 4...6, "Qingming Festival", "清明节"),
        span("cn", 2026, 5, 1...5, "Labour Day", "劳动节"),
        span("cn", 2026, 6, 19...21, "Dragon Boat Festival", "端午节"),
        span("cn", 2026, 9, 25...27, "Mid-Autumn Festival", "中秋节"),
        span("cn", 2026, 10, 1...7, "National Day", "国庆节"),

        // Singapore — nationwide public holidays and weekday substitutions.
        day("sg", "2026-01-01", "New Year's Day", "元旦"),
        day("sg", "2026-02-17", "Chinese New Year", "农历新年"),
        day("sg", "2026-02-18", "Chinese New Year", "农历新年第二天"),
        day("sg", "2026-03-21", "Hari Raya Puasa", "开斋节"),
        day("sg", "2026-04-03", "Good Friday", "耶稣受难日"),
        day("sg", "2026-05-01", "Labour Day", "劳动节"),
        day("sg", "2026-05-27", "Hari Raya Haji", "哈芝节"),
        day("sg", "2026-05-31", "Vesak Day", "卫塞节"),
        day("sg", "2026-06-01", "Vesak Day (in lieu)", "卫塞节补假"),
        day("sg", "2026-08-09", "National Day", "国庆日"),
        day("sg", "2026-08-10", "National Day (in lieu)", "国庆日补假"),
        day("sg", "2026-11-08", "Deepavali", "屠妖节"),
        day("sg", "2026-11-09", "Deepavali (in lieu)", "屠妖节补假"),
        day("sg", "2026-12-25", "Christmas Day", "圣诞节"),

        // Malaysia — federal holidays; state-only holidays are omitted.
        day("my", "2026-01-01", "New Year's Day", "元旦", "Except selected states"),
        day("my", "2026-02-17", "Chinese New Year", "农历新年"),
        day("my", "2026-02-18", "Chinese New Year", "农历新年第二天"),
        day("my", "2026-03-21", "Hari Raya Aidilfitri", "开斋节"),
        day("my", "2026-03-22", "Hari Raya Aidilfitri", "开斋节第二天"),
        day("my", "2026-05-01", "Labour Day", "劳动节"),
        day("my", "2026-05-27", "Hari Raya Haji", "哈芝节"),
        day("my", "2026-05-31", "Wesak Day", "卫塞节"),
        day("my", "2026-06-01", "Birthday of the Yang di-Pertuan Agong", "国家元首诞辰"),
        day("my", "2026-06-17", "Awal Muharram", "回历元旦"),
        day("my", "2026-08-25", "Prophet Muhammad's Birthday", "先知穆罕默德诞辰"),
        day("my", "2026-08-31", "National Day", "国庆日"),
        day("my", "2026-09-16", "Malaysia Day", "马来西亚日"),
        day("my", "2026-11-08", "Deepavali", "屠妖节", "Except Sarawak"),
        day("my", "2026-12-25", "Christmas Day", "圣诞节"),

        // Thailand — nationwide public and substitute holidays.
        day("th", "2026-01-01", "New Year's Day", "วันขึ้นปีใหม่"),
        day("th", "2026-03-03", "Makha Bucha Day", "วันมาฆบูชา"),
        day("th", "2026-04-06", "Chakri Memorial Day", "วันจักรี"),
        span("th", 2026, 4, 13...15, "Songkran Festival", "วันสงกรานต์"),
        day("th", "2026-05-01", "National Labour Day", "วันแรงงานแห่งชาติ"),
        day("th", "2026-05-04", "Coronation Day", "วันฉัตรมงคล"),
        day("th", "2026-05-31", "Visakha Bucha Day", "วันวิสาขบูชา"),
        day("th", "2026-06-01", "Visakha Bucha Day (substitute)", "ชดเชยวันวิสาขบูชา"),
        day("th", "2026-06-03", "Queen Suthida's Birthday", "วันเฉลิมพระชนมพรรษาสมเด็จพระนางเจ้าฯ"),
        day("th", "2026-07-28", "King Vajiralongkorn's Birthday", "วันเฉลิมพระชนมพรรษาพระบาทสมเด็จพระเจ้าอยู่หัว"),
        day("th", "2026-07-29", "Asalha Bucha Day", "วันอาสาฬหบูชา"),
        day("th", "2026-08-12", "Queen Mother's Birthday", "วันแม่แห่งชาติ"),
        day("th", "2026-10-13", "King Bhumibol Memorial Day", "วันนวมินทรมหาราช"),
        day("th", "2026-10-23", "Chulalongkorn Day", "วันปิยมหาราช"),
        day("th", "2026-12-05", "King Bhumibol's Birthday", "วันพ่อแห่งชาติ"),
        day("th", "2026-12-07", "King Bhumibol's Birthday (substitute)", "วันหยุดชดเชย"),
        day("th", "2026-12-10", "Constitution Day", "วันรัฐธรรมนูญ"),
        day("th", "2026-12-31", "New Year's Eve", "วันสิ้นปี"),

        // Hong Kong — general holidays.
        day("hk", "2026-01-01", "The first day of January", "一月一日"),
        span("hk", 2026, 2, 17...19, "Lunar New Year", "农历新年"),
        day("hk", "2026-04-03", "Good Friday", "耶稣受难节"),
        day("hk", "2026-04-04", "Day following Good Friday", "耶稣受难节翌日"),
        day("hk", "2026-04-06", "Day following Ching Ming Festival", "清明节翌日"),
        day("hk", "2026-04-07", "Day following Easter Monday", "复活节星期一翌日"),
        day("hk", "2026-05-01", "Labour Day", "劳动节"),
        day("hk", "2026-05-25", "Day following the Birthday of the Buddha", "佛诞翌日"),
        day("hk", "2026-06-19", "Tuen Ng Festival", "端午节"),
        day("hk", "2026-07-01", "HKSAR Establishment Day", "香港特别行政区成立纪念日"),
        day("hk", "2026-09-26", "Day following Mid-Autumn Festival", "中秋节翌日"),
        day("hk", "2026-10-01", "National Day", "国庆日"),
        day("hk", "2026-10-19", "Day following Chung Yeung Festival", "重阳节翌日"),
        day("hk", "2026-12-25", "Christmas Day", "圣诞节"),
        day("hk", "2026-12-26", "First weekday after Christmas Day", "圣诞节后第一个周日")
    ]

    static func events(for country: HolidayCountry) -> [CalendarEvent] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return holidays.filter { $0.countryCode == country.id }.compactMap { holiday in
            let fields = holiday.date.split(separator: "-").compactMap { Int($0) }
            guard fields.count == 3,
                  let start = calendar.date(from: DateComponents(year: fields[0], month: fields[1], day: fields[2])),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            let title = holiday.localName.isEmpty ? holiday.name : "\(holiday.localName) · \(holiday.name)"
            let notes = [briefDescription(for: holiday), holiday.note]
                .filter { !$0.isEmpty }.joined(separator: "\n")
            return CalendarEvent(uid: "traveltime-holiday-\(country.id)-\(holiday.date)-\(holiday.name)",
                                 summary: title, location: country.localName, notes: notes,
                                 isAllDay: true, start: start, end: end, rrule: nil)
        }
    }

    static func covers(year: Int) -> Bool { coverageYears.contains(year) }

    /// A short, human explanation for the detail row. Matching the stable
    /// English catalogue name also covers substitute/in-lieu variants.
    static func briefDescription(for holiday: BundledHoliday) -> String {
        let name = holiday.name.lowercased()
        if name.contains("new year") && !name.contains("chinese") && !name.contains("lunar") && !name.contains("muharram") {
            return "迎接公历新年，通常用于团聚、庆祝并开启新一年的生活。"
        }
        if name.contains("spring festival") || name.contains("chinese new year") || name.contains("lunar new year") {
            return "庆祝农历新年，以家庭团聚、拜年和迎福纳新为核心。"
        }
        if name.contains("qingming") || name.contains("ching ming") { return "祭祖扫墓、追思先人，也有踏青迎春的传统。" }
        if name.contains("labour") { return "向劳动者及其社会贡献致意的公共假日。" }
        if name.contains("dragon boat") || name.contains("tuen ng") { return "以龙舟竞渡和粽子等习俗纪念传统文化与历史人物。" }
        if name.contains("mid-autumn") { return "赏月、团聚并分享月饼，寄托家庭圆满的节日。" }
        if name.contains("hari raya puasa") || name.contains("aidilfitri") { return "标志斋月结束，穆斯林家庭礼拜、团聚并互致祝福。" }
        if name.contains("good friday") { return "基督徒纪念耶稣受难与牺牲的庄严节日。" }
        if name.contains("hari raya haji") { return "纪念信仰与奉献，并与朝觐季及慈善分享传统相关。" }
        if name.contains("vesak") || name.contains("wesak") || name.contains("visakha") || name.contains("birthday of the buddha") {
            return "佛教徒纪念佛陀诞生、觉悟与涅槃的重要日子。"
        }
        if name.contains("deepavali") { return "印度教灯节，象征光明战胜黑暗、善战胜恶。" }
        if name.contains("christmas") { return "基督徒纪念耶稣诞生，也是家人团聚与互赠祝福的节日。" }
        if name.contains("muharram") { return "伊斯兰历新年的开始，是反思、祈祷与更新的日子。" }
        if name.contains("prophet muhammad") { return "纪念先知穆罕默德诞辰及其教诲。" }
        if name.contains("malaysia day") { return "纪念马来西亚联邦成立及各地区共同组成国家。" }
        if name.contains("yang di-pertuan agong") { return "庆祝马来西亚最高元首诞辰的联邦公共假日。" }
        if name.contains("makha bucha") { return "纪念佛陀时代重要僧团集会，以礼佛和行善为主要活动。" }
        if name.contains("chakri") { return "纪念泰国却克里王朝建立及历代君主。" }
        if name.contains("songkran") { return "泰历新年，以浴佛、敬老与泼水祝福迎接新开始。" }
        if name.contains("coronation") { return "纪念泰国国王加冕及王室传统。" }
        if name.contains("asalha") { return "纪念佛陀首次说法，是泰国重要佛教节日。" }
        if name.contains("queen") || name.contains("king") { return "纪念泰国王室成员诞辰或历史贡献的公共假日。" }
        if name.contains("constitution") { return "纪念宪法颁布及国家现代政治制度的建立。" }
        if name.contains("easter") { return "基督教复活节假期，纪念耶稣复活。" }
        if name.contains("hksar establishment") { return "纪念香港特别行政区成立。" }
        if name.contains("chung yeung") { return "重阳节传统包括登高、祭祖与敬老。" }
        if name.contains("national day") { return "纪念国家或地区重要历史时刻，并举行公共庆祝活动。" }
        return "当地公众共同纪念的重要节日或法定休息日。"
    }

    private static func day(_ country: String, _ date: String, _ name: String,
                            _ localName: String, _ note: String = "") -> [BundledHoliday] {
        [BundledHoliday(countryCode: country, date: date, name: name, localName: localName, note: note)]
    }

    private static func span(_ country: String, _ year: Int, _ month: Int,
                             _ days: ClosedRange<Int>, _ name: String,
                             _ localName: String) -> [BundledHoliday] {
        days.map { value in
            BundledHoliday(countryCode: country,
                           date: String(format: "%04d-%02d-%02d", year, month, value),
                           name: name, localName: localName, note: "")
        }
    }
}

@MainActor
final class HolidayStore: ObservableObject {
    @Published private(set) var selectedCountries: [HolidayCountry]
    private let defaults: UserDefaults
    private static let countriesKey = "holidays.offline.countries.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let ids = defaults.array(forKey: Self.countriesKey) as? [String] {
            selectedCountries = HolidayCountry.common.filter { ids.contains($0.id) }
        } else {
            // Migrate the former API-backed selection without touching Keychain.
            let oldIDs: Set<String>
            if let data = defaults.data(forKey: "holidays.countries.v1"),
               let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                oldIDs = Set(objects.compactMap { $0["id"] as? String })
            } else { oldIDs = [] }
            selectedCountries = HolidayCountry.common.filter { oldIDs.contains($0.id) }
        }
    }

    func isEnabled(_ country: HolidayCountry) -> Bool {
        selectedCountries.contains { $0.id == country.id }
    }

    func setEnabled(_ enabled: Bool, country: HolidayCountry, eventStore: EventStore) {
        if enabled {
            if !isEnabled(country) { selectedCountries.append(country) }
            eventStore.replaceHolidaySource(country: country, events: BundledHolidayCatalog.events(for: country))
        } else {
            selectedCountries.removeAll { $0.id == country.id }
            eventStore.removeHolidaySources(countryCode: country.id)
        }
        defaults.set(selectedCountries.map(\.id), forKey: Self.countriesKey)
    }

    func installEnabledHolidays(into eventStore: EventStore) {
        selectedCountries.forEach {
            eventStore.replaceHolidaySource(country: $0, events: BundledHolidayCatalog.events(for: $0))
        }
    }
}
