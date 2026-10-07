import Foundation

// MARK: - 参考書

struct Part: Decodable, Identifiable, Hashable {
    let n: Int
    let t: String
    let d: String
    var id: Int { n }
}

enum Block: Decodable, Hashable {
    case paragraph(String)
    case list([String])
    case table(header: [String], rows: [[String]])
    case code(String)

    private enum CodingKeys: String, CodingKey { case type, text, items, header, rows }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "list":
            self = .list(try c.decode([String].self, forKey: .items))
        case "table":
            self = .table(header: try c.decode([String].self, forKey: .header),
                          rows: try c.decode([[String]].self, forKey: .rows))
        case "code":
            self = .code(try c.decode(String.self, forKey: .text))
        default:
            self = .paragraph(try c.decode(String.self, forKey: .text))
        }
    }
}

struct ChapterSection: Decodable, Hashable, Identifiable {
    let h: String
    let blocks: [Block]
    var id: String { h }
}

struct Chapter: Decodable, Hashable, Identifiable {
    let id: Int
    let part: Int
    let t: String
    let sum: String
    let quiz: [Int]
    let lead: String
    let secs: [ChapterSection]
    let points: [String]
    let traps: [String]
}

// MARK: - ドリル

struct Question: Decodable, Hashable, Identifiable {
    let id: Int
    let cat: String
    let since: String?
    let q: String
    let code: String?
    let opts: [String]
    let a: Int
    let exp: String
    let chapter: Int?
}

// MARK: - 作って学ぶ

struct BuildStep: Decodable, Hashable, Identifiable {
    let id: Int
    let t: String
    let learn: [String]
    let tasks: [String]
    let code: String?
}

// MARK: - 同梱データ

enum Content {
    static let parts: [Part] = load("parts")
    static let chapters: [Chapter] = load("book")
    static let questions: [Question] = load("quiz")
    static let steps: [BuildStep] = load("steps")

    static let categories = ["基礎", "モダンJava", "Silver対策"]

    static func chapter(_ id: Int) -> Chapter? { chapters.first { $0.id == id } }
    static func part(_ n: Int) -> Part? { parts.first { $0.n == n } }
    static func chapters(in part: Part) -> [Chapter] { chapters.filter { $0.part == part.n } }

    private static func load<T: Decodable>(_ name: String) -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("\(name).json がバンドルにありません")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            fatalError("\(name).json を読み込めません: \(error)")
        }
    }
}
