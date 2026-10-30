import Foundation

struct TVBoxConfig: Codable, Sendable {
    var sites: [TVBoxSite] = []
    var parses: [TVBoxParse] = []
    var lives: [TVBoxLive] = []
    var spider: String?

    enum CodingKeys: String, CodingKey { case sites, parses, lives, spider }

    init(sites: [TVBoxSite] = [], lives: [TVBoxLive] = []) {
        self.sites = sites
        self.lives = lives
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        sites = (try? box.decode(LossyArray<TVBoxSite>.self, forKey: .sites).elements) ?? []
        parses = (try? box.decode(LossyArray<TVBoxParse>.self, forKey: .parses).elements) ?? []
        lives = (try? box.decode(LossyArray<TVBoxLive>.self, forKey: .lives).elements) ?? []
        spider = box.decodeFlexibleStringIfPresent(forKey: .spider)
    }
}

struct TVBoxSite: Codable, Identifiable, Hashable, Sendable {
    var key: String
    var name: String
    var type: Int
    var api: String
    var searchable: Int?
    var quickSearch: Int?
    var filterable: Int?
    var ext: JSONValue?

    enum CodingKeys: String, CodingKey {
        case key, name, type, api, searchable, quickSearch, filterable, ext
    }

    init(key: String, name: String, api: String) {
        self.key = key; self.name = name; self.api = api; self.type = 1
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        key = box.decodeFlexibleStringIfPresent(forKey: .key) ?? ""
        name = box.decodeFlexibleStringIfPresent(forKey: .name) ?? key
        type = box.decodeFlexibleIntIfPresent(forKey: .type) ?? -1
        api = box.decodeFlexibleStringIfPresent(forKey: .api) ?? ""
        searchable = box.decodeFlexibleIntIfPresent(forKey: .searchable)
        quickSearch = box.decodeFlexibleIntIfPresent(forKey: .quickSearch)
        filterable = box.decodeFlexibleIntIfPresent(forKey: .filterable)
        ext = try? box.decodeIfPresent(JSONValue.self, forKey: .ext)
        guard !key.isEmpty, !api.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .key, in: box, debugDescription: "site 缺少 key 或 api")
        }
    }

    var id: String { key }

    var runtime: SourceRuntime {
        if type == 3 || api.hasPrefix("csp_") { return .gatewayRequired }
        if type == 1, URL(string: api)?.scheme?.hasPrefix("http") == true {
            return .nativeAPI
        }
        return .unsupported
    }
}

struct TVBoxParse: Codable, Hashable, Sendable {
    var name: String
    var type: Int?
    var url: String

    enum CodingKeys: String, CodingKey { case name, type, url }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = box.decodeFlexibleStringIfPresent(forKey: .name) ?? "解析"
        type = box.decodeFlexibleIntIfPresent(forKey: .type)
        url = box.decodeFlexibleStringIfPresent(forKey: .url) ?? ""
        guard !url.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .url, in: box, debugDescription: "parse 缺少 url")
        }
    }
}

struct TVBoxLive: Codable, Hashable, Sendable {
    var name: String
    var type: Int?
    var url: String
    var epg: String?
    var logo: String?

    enum CodingKeys: String, CodingKey { case name, type, url, epg, logo }

    init(name: String, url: String) {
        self.name = name; self.url = url
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = box.decodeFlexibleStringIfPresent(forKey: .name) ?? "直播"
        type = box.decodeFlexibleIntIfPresent(forKey: .type)
        url = box.decodeFlexibleStringIfPresent(forKey: .url) ?? ""
        epg = box.decodeFlexibleStringIfPresent(forKey: .epg)
        logo = box.decodeFlexibleStringIfPresent(forKey: .logo)
        guard !url.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .url, in: box, debugDescription: "live 缺少 url")
        }
    }
}

struct LiveChannel: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let group: String
    let streams: [LiveStream]
    let logoURL: URL?

    var urls: [URL] { streams.map(\.url) }
}

struct LiveStream: Codable, Identifiable, Hashable, Sendable {
    let url: URL
    let name: String?
    let headers: [String: String]

    var id: String { "\(url.absoluteString)|\(name ?? "")|\(headers)" }
}

enum SourceRuntime: String, Sendable {
    case nativeAPI
    case gatewayRequired
    case unsupported

    var label: String {
        switch self {
        case .nativeAPI: "原生支持"
        case .gatewayRequired: "需要 Gateway"
        case .unsupported: "暂不支持"
        }
    }
}

enum JSONValue: Codable, Hashable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let value = try? box.decode(Bool.self) { self = .bool(value) }
        else if let value = try? box.decode(Double.self) { self = .number(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else if let value = try? box.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try box.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .string(let value): try box.encode(value)
        case .number(let value): try box.encode(value)
        case .bool(let value): try box.encode(value)
        case .object(let value): try box.encode(value)
        case .array(let value): try box.encode(value)
        case .null: try box.encodeNil()
        }
    }
}

private struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        while !container.isAtEnd {
            if let value = try? container.decode(Element.self) {
                result.append(value)
            } else {
                _ = try? container.decode(JSONValue.self)
            }
        }
        elements = result
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleStringIfPresent(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        return nil
    }

    func decodeFlexibleIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value) }
        return nil
    }
}
