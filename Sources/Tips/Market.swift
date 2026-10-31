import Foundation

struct MarketIndex: Identifiable, Hashable, Sendable {
    /// Tencent quote code, e.g. `sh000001`.
    let code: String
    let name: String

    var id: String { code }

    static let catalog: [MarketIndex] = [
        MarketIndex(code: "sh000001", name: "上证指数"),
        MarketIndex(code: "sz399001", name: "深证成指"),
        MarketIndex(code: "sz399006", name: "创业板指"),
        MarketIndex(code: "sh000300", name: "沪深300"),
        MarketIndex(code: "sh000688", name: "科创50"),
        MarketIndex(code: "hkHSI", name: "恒生指数"),
        MarketIndex(code: "hkHSTECH", name: "恒生科技"),
        MarketIndex(code: "hkHSCEI", name: "国企指数"),
        MarketIndex(code: "usNDX", name: "纳斯达克100"),
        MarketIndex(code: "usIXIC", name: "纳斯达克"),
        MarketIndex(code: "usINX", name: "标普500"),
        MarketIndex(code: "usDJI", name: "道琼斯"),
    ]

    static let defaultCodes = ["sh000001", "sz399001", "sz399006", "hkHSI", "usNDX", "usINX", "usDJI"]

    static func named(_ code: String) -> String {
        catalog.first { $0.code == code }?.name ?? code
    }
}

struct Quote: Identifiable, Equatable, Sendable {
    let code: String
    let name: String
    let price: Double
    let change: Double
    let changePercent: Double

    var id: String { code }
}

protocol MarketProviding: Sendable {
    func quotes(for codes: [String]) async throws -> [Quote]
}

enum TipsError: LocalizedError, Equatable {
    case badResponse
    case undecodable

    var errorDescription: String? {
        switch self {
        case .badResponse: "服务暂时不可用"
        case .undecodable: "数据格式无法识别"
        }
    }
}

/// Index quotes from Tencent's public quote endpoint (no API key, reachable from mainland China).
///
/// Response (GBK encoded), one line per code:
/// `v_s_sh000001="1~上证指数~000001~3599.02~-52.41~-1.44~...";`
struct TencentMarketProvider: MarketProviding {
    var session: URLSession = .shared

    func quotes(for codes: [String]) async throws -> [Quote] {
        guard !codes.isEmpty else { return [] }
        let list = codes.map { "s_\($0)" }.joined(separator: ",")
        guard let url = URL(string: "https://qt.gtimg.cn/q=\(list)") else { throw TipsError.badResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("tat/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw TipsError.badResponse }
        let quotes = Self.parse(Self.decodeGBK(data))
        // Keep the order the user picked.
        return codes.compactMap { code in quotes.first { $0.code == code } }
    }

    static func decodeGBK(_ data: Data) -> String {
        let gb18030 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: gb18030))
            ?? String(decoding: data, as: UTF8.self)
    }

    static func parse(_ body: String) -> [Quote] {
        body.split(separator: ";").compactMap { line -> Quote? in
            guard let start = line.range(of: "v_s_"),
                  let equals = line.range(of: "=\"", range: start.upperBound..<line.endIndex),
                  let closing = line.range(of: "\"", options: .backwards),
                  closing.lowerBound > equals.upperBound
            else { return nil }
            let code = String(line[start.upperBound..<equals.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let fields = line[equals.upperBound..<closing.lowerBound].split(separator: "~", omittingEmptySubsequences: false)
            guard fields.count > 5,
                  let price = Double(fields[3]),
                  let change = Double(fields[4]),
                  let percent = Double(fields[5])
            else { return nil }
            return Quote(code: code, name: MarketIndex.named(code), price: price, change: change, changePercent: percent)
        }
    }
}
