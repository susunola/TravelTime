import Foundation

/// 中国农历（农暦）转换，覆盖 1900–2100。
///
/// `lunarInfo` 与 `solarTermFix` 由 6tail/lunar-javascript 天文历算权威数据生成并全量校验
/// （73,384 天 0 误差；每年 24 节气全部吻合）。核心算法为经典的 16-bit 编码表方案。
struct ChineseLunarCalendar {

    // MARK: - 数据表（生成并校验）

    static let lunarInfo: [Int] = [
        0x4BD8,0x4AE0,0xA570,0x54D5,0xD260,0xD950,0x16554,0x56A0,0x9AD0,0x55D2,
        0x4AE0,0xA5B6,0xA4D0,0xD250,0x1D255,0xB540,0xD6A0,0xADA2,0x95B0,0x14977,
        0x4970,0xA4B0,0xB4B5,0x6A50,0x6D40,0x1AB54,0x2B60,0x9570,0x52F2,0x4970,
        0x6566,0xD4A0,0xEA50,0x16A95,0x5AD0,0x2B60,0x186E3,0x92E0,0x1C8D7,0xC950,
        0xD4A0,0x1D8A6,0xB550,0x56A0,0x1A5B4,0x25D0,0x92D0,0xD2B2,0xA950,0xB557,
        0x6CA0,0xB550,0x15355,0x4DA0,0xA5B0,0x14573,0x52B0,0xA9A8,0xE950,0x6AA0,
        0xAEA6,0xAB50,0x4B60,0xAAE4,0xA570,0x5260,0xF263,0xD950,0x5B57,0x56A0,
        0x96D0,0x4DD5,0x4AD0,0xA4D0,0xD4D4,0xD250,0xD558,0xB540,0xB6A0,0x195A6,
        0x95B0,0x49B0,0xA974,0xA4B0,0xB27A,0x6A50,0x6D40,0xAF46,0xAB60,0x9570,
        0x4AF5,0x4970,0x64B0,0x74A3,0xEA50,0x6B58,0x5AC0,0xAB60,0x96D5,0x92E0,
        0xC960,0xD954,0xD4A0,0xDA50,0x7552,0x56A0,0xABB7,0x25D0,0x92D0,0xCAB5,
        0xA950,0xB4A0,0xBAA4,0xAD50,0x55D9,0x4BA0,0xA5B0,0x15176,0x52B0,0xA930,
        0x7954,0x6AA0,0xAD50,0x5B52,0x4B60,0xA6E6,0xA4E0,0xD260,0xEA65,0xD530,
        0x5AA0,0x76A3,0x96D0,0x4AFB,0x4AD0,0xA4D0,0x1D0B6,0xD250,0xD520,0xDD45,
        0xB5A0,0x56D0,0x55B2,0x49B0,0xA577,0xA4B0,0xAA50,0x1B255,0x6D20,0xADA0,
        0x14B63,0x9370,0x49F8,0x4970,0x64B0,0x168A6,0xEA50,0x6B20,0x1A6C4,0xAAE0,
        0x92E0,0xD2E3,0xC960,0xD557,0xD4A0,0xDA50,0x5D55,0x56A0,0xA6D0,0x55D4,
        0x52D0,0xA9B8,0xA950,0xB4A0,0xB6A6,0xAD50,0x55A0,0xABA4,0xA5B0,0x52B0,
        0xB273,0x6930,0x7337,0x6AA0,0xAD50,0x14B55,0x4B60,0xA570,0x54E4,0xD160,
        0xE968,0xD520,0xDAA0,0x16AA6,0x56D0,0x4AE0,0xA9D4,0xA2D0,0xD150,0xF252,
        0xD520
    ]

    static let sTermInfo: [Int] = [0, 21208, 42467, 63836, 85337, 107014, 128867, 150921,
        173149, 195551, 218072, 240693, 263343, 285989, 308563, 331033,
        353350, 375494, 397447, 419210, 440795, 462224, 483532, 504758]

    static let solarTermFix: [Int: Int] = [
        190901: 121,
        191002: 205,
        191006: 406,
        191108: 507,
        191200: 107,
        191218: 1009,
        191709: 521,
        191722: 1208,
        193510: 606,
        194201: 121,
        194302: 205,
        194306: 406,
        194500: 106,
        194723: 1223,
        195007: 420,
        195022: 1208,
        195123: 1223,
        195205: 321,
        195513: 723,
        195603: 220,
        195720: 1108,
        195812: 707,
        195815: 823,
        196016: 907,
        196111: 621,
        197308: 505,
        197421: 1123,
        197501: 121,
        197517: 923,
        197602: 205,
        197704: 306,
        197714: 807,
        197800: 106,
        197821: 1123,
        197909: 521,
        198002: 205,
        198023: 1222,
        198104: 306,
        198200: 106,
        198322: 1208,
        198413: 722,
        198423: 1222,
        198505: 321,
        198712: 707,
        198813: 722,
        198903: 219,
        198916: 907,
        199011: 621,
        199020: 1108,
        199112: 707,
        199115: 823,
        199411: 621,
        199710: 605,
        200608: 505,
        200614: 807,
        200721: 1123,
        200801: 121,
        200817: 922,
        200902: 204,
        201004: 306,
        201014: 807,
        201100: 106,
        201121: 1123,
        201201: 121,
        201209: 520,
        201222: 1207,
        201302: 204,
        201313: 722,
        201323: 1222,
        201404: 306,
        201500: 106,
        201622: 1207,
        201713: 722,
        201723: 1222,
        201803: 219,
        201805: 321,
        201911: 621,
        202012: 706,
        202015: 822,
        202022: 1207,
        202203: 219,
        202216: 907,
        202311: 621,
        202319: 1024,
        202320: 1108,
        202415: 822,
        202610: 605,
        203010: 605,
        203508: 505,
        203514: 807,
        203701: 120,
        203914: 807,
        204000: 106,
        204018: 1008,
        204021: 1122,
        204101: 120,
        204109: 520,
        204202: 204,
        204304: 306,
        204314: 807,
        204400: 106,
        204421: 1122,
        204501: 120,
        204507: 419,
        204509: 520,
        204522: 1207,
        204602: 204,
        204613: 722,
        204623: 1222,
        204704: 306,
        204800: 106,
        204811: 620,
        204912: 706,
        204915: 822,
        204922: 1207,
        205013: 722,
        205023: 1222,
        205103: 219,
        205116: 907,
        205211: 620,
        205312: 706,
        205315: 822,
        205322: 1207,
        205423: 1222,
        205503: 219,
        205510: 605,
        205516: 907,
        205611: 620,
        205619: 1023,
        205620: 1107,
        205903: 219,
        205910: 605,
        206310: 605,
        206808: 504,
        206814: 806,
        207001: 120,
        207009: 520,
        207017: 922,
        207102: 204,
        207106: 405,
        207214: 806,
        207300: 105,
        207321: 1122,
        207401: 120,
        207409: 520,
        207502: 204,
        207513: 722,
        207523: 1222,
        207604: 305,
        207700: 105,
        207721: 1122,
        207801: 120,
        207807: 419,
        207812: 706,
        207822: 1207,
        207902: 204,
        207913: 722,
        207923: 1222,
        208004: 305,
        208005: 320,
        208100: 105,
        208111: 620,
        208201: 120,
        208212: 706,
        208215: 822,
        208222: 1207,
        208313: 722,
        208323: 1222,
        208403: 219,
        208416: 906,
        208511: 620,
        208612: 706,
        208615: 822,
        208622: 1207,
        208723: 1222,
        208803: 219,
        208810: 604,
        208816: 906,
        208911: 620,
        208919: 1023,
        208920: 1107,
        209203: 219,
        209210: 604,
        209714: 806
    ]

    static let gan = ["甲","乙","丙","丁","戊","己","庚","辛","壬","癸"]
    static let zhi = ["子","丑","寅","卯","辰","巳","午","未","申","酉","戌","亥"]
    static let animals = ["鼠","牛","虎","兔","龙","蛇","马","羊","猴","鸡","狗","猪"]
    static let monthNames = ["正月","二月","三月","四月","五月","六月","七月","八月","九月","十月","冬月","腊月"]
    static let dayNames = ["初一","初二","初三","初四","初五","初六","初七","初八","初九","初十",
                           "十一","十二","十三","十四","十五","十六","十七","十八","十九","二十",
                           "廿一","廿二","廿三","廿四","廿五","廿六","廿七","廿八","廿九","三十"]
    static let solarTermNames = ["小寒","大寒","立春","雨水","惊蛰","春分","清明","谷雨","立夏","小满","芒种","夏至",
                                 "小暑","大暑","立秋","处暑","白露","秋分","寒露","霜降","立冬","小雪","大雪","冬至"]

    // MARK: - 农历年/月/日

    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    static func lYearDays(_ y: Int) -> Int {
        var sum = 348
        let code = lunarInfo[y - 1900]
        var i = 0x8000
        while i > 0x8 {
            if code & i != 0 { sum += 1 }
            i >>= 1
        }
        if code & 0xf != 0 { sum += (code & 0x10000 != 0) ? 30 : 29 }
        return sum
    }

    static func leapMonth(_ y: Int) -> Int { lunarInfo[y - 1900] & 0xf }

    static func leapDays(_ y: Int) -> Int {
        let c = lunarInfo[y - 1900]
        return (c & 0xf) != 0 ? ((c & 0x10000) != 0 ? 30 : 29) : 0
    }

    static func monthDays(_ y: Int, _ m: Int) -> Int {
        (lunarInfo[y - 1900] & (0x10000 >> m)) != 0 ? 30 : 29
    }

    struct LunarDate {
        let year: Int
        let month: Int
        let day: Int
        let isLeap: Bool
    }

    /// 把给定日期（按 `calendar` 的本地年月日）转换为农历。
    static func lunarDate(for date: Date, calendar: Calendar) -> LunarDate {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 1900
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        let base = utcCalendar.date(from: DateComponents(year: 1900, month: 1, day: 31))!
        let cur = utcCalendar.date(from: DateComponents(year: y, month: m, day: d))!
        var offset = Int(cur.timeIntervalSince(base) / 86400)
        var year = 1900
        while offset >= lYearDays(year) { offset -= lYearDays(year); year += 1 }
        let leap = leapMonth(year)
        var seq: [(m: Int, leap: Bool)] = []
        for mo in 1...12 {
            seq.append((mo, false))
            if leap > 0 && mo == leap { seq.append((mo, true)) }
        }
        var month = 1
        var isLeap = false
        for s in seq {
            let dm = s.leap ? leapDays(year) : monthDays(year, s.m)
            if offset < dm { month = s.m; isLeap = s.leap; break }
            offset -= dm
        }
        return LunarDate(year: year, month: month, day: offset + 1, isLeap: isLeap)
    }

    // MARK: - 干支 / 生肖 / 名称

    static func ganZhiYear(_ lunarYear: Int) -> String {
        let g = gan[((lunarYear - 4) % 10 + 10) % 10]
        let z = zhi[((lunarYear - 4) % 12 + 12) % 12]
        return g + z
    }

    static func animal(_ lunarYear: Int) -> String {
        animals[((lunarYear - 4) % 12 + 12) % 12]
    }

    static func monthName(_ month: Int, isLeap: Bool) -> String {
        let base = monthNames[month - 1]
        return isLeap ? "闰" + base : base
    }

    static func dayName(_ day: Int) -> String {
        dayNames[day - 1]
    }

    // MARK: - 节气

    /// 第 n 个节气（0=小寒）在给定公历年份的 (月, 日)，UTC。
    static func termMonthDay(year: Int, term: Int) -> (Int, Int) {
        let base = utcCalendar.date(from: DateComponents(year: 1900, month: 1, day: 6, hour: 2, minute: 5))!
        let ms = 31556925974.7 * Double(year - 1900) + Double(sTermInfo[term]) * 60000
            + base.timeIntervalSince1970 * 1000
        let dt = Date(timeIntervalSince1970: ms / 1000)
        let c = utcCalendar.dateComponents([.month, .day], from: dt)
        return (c.month ?? 1, c.day ?? 1)
    }

    /// 返回该日期的节气名称（若无则返回 nil）。
    static func solarTermName(for date: Date, calendar: Calendar) -> String? {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 1900
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        for n in 0..<24 {
            var cd = termMonthDay(year: y, term: n)
            if let fix = solarTermFix[y * 100 + n] {
                cd = (fix / 100, fix % 100)
            }
            if cd.0 == m && cd.1 == d { return solarTermNames[n] }
        }
        return nil
    }

    // MARK: - 便捷汇总

    struct Summary {
        let ganZhiYear: String
        let animal: String
        let monthText: String
        let dayText: String
        let solarTerm: String?
    }

    static func summary(for date: Date, calendar: Calendar) -> Summary {
        let ld = lunarDate(for: date, calendar: calendar)
        return Summary(
            ganZhiYear: ganZhiYear(ld.year),
            animal: animal(ld.year),
            monthText: monthName(ld.month, isLeap: ld.isLeap),
            dayText: dayName(ld.day),
            solarTerm: solarTermName(for: date, calendar: calendar)
        )
    }
}
