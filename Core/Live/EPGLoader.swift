import Foundation

struct EPGProgram: Identifiable, Hashable, Sendable {
    let title: String
    let start: String
    let end: String
    var id: String { "\(start)|\(end)|\(title)" }
}

struct EPGLoader {
    func load(template: String, channelName: String, date: Date = .now) async throws -> [EPGProgram] {
        let day = date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let encodedName = channelName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? channelName
        let address = template.replacingOccurrences(of: "{name}", with: encodedName)
            .replacingOccurrences(of: "{date}", with: day)
        guard let url = URL(string: address) else { throw LivePlaylistError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let (data, _) = try await BoundedHTTPClient().data(for: request, maximumBytes: 2 * 1024 * 1024)
        let response = try JSONDecoder().decode(EPGResponse.self, from: data)
        return response.programs.map { EPGProgram(title: $0.title, start: $0.start, end: $0.end) }
    }
}

private struct EPGResponse: Decodable {
    let programs: [RawProgram]
    enum CodingKeys: String, CodingKey { case programs = "epg_data" }
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        programs = (try? box.decode([RawProgram].self, forKey: .programs)) ?? []
    }
}

private struct RawProgram: Decodable {
    let title: String
    let start: String
    let end: String
    enum CodingKeys: String, CodingKey { case title, start, end }
}
