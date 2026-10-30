import Foundation

enum ConfigDecodingError: LocalizedError {
    case unsupportedFormat
    case invalidConfig

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "订阅不是可识别的 TVBox JSON 或图片包装配置，请确认填写的是配置直链。"
        case .invalidConfig: "TVBox 配置内容无效，或使用了尚不支持的加密格式。"
        }
    }
}

/// Separates transport wrappers and JSON extensions from the persisted domain model.
struct TVBoxConfigDecoder {
    func decode(_ data: Data) throws -> TVBoxConfig {
        let payload: Data
        let jpeg = data.starts(with: [0xFF, 0xD8])
        let png = data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        if jpeg || png {
            // TVBox image wrappers append a short tag, **, and a Base64 payload.
            let imageEnd: Data.Index?
            if jpeg {
                imageEnd = data.range(of: Data([0xFF, 0xD9]))?.upperBound
            } else {
                imageEnd = data.range(of: Data([0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]))?.upperBound
            }
            guard let imageEnd,
                  let marker = data.range(of: Data("**".utf8), in: imageEnd..<min(data.endIndex, imageEnd + 128)),
                  let text = String(data: data[marker.upperBound...], encoding: .utf8),
                  let decoded = Data(base64Encoded: text.filter { !$0.isWhitespace }) else {
                throw ConfigDecodingError.unsupportedFormat
            }
            payload = decoded
        } else {
            payload = data
        }
        guard var text = String(data: payload, encoding: .utf8) else {
            throw ConfigDecodingError.unsupportedFormat
        }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).first == "{" else {
            throw ConfigDecodingError.unsupportedFormat
        }
        do {
            return try JSONDecoder().decode(TVBoxConfig.self, from: Data(normalize(text).utf8))
        } catch {
            throw ConfigDecodingError.invalidConfig
        }
    }

    /// Strip comments and trailing commas only outside strings; URLs and escapes stay intact.
    private func normalize(_ text: String) -> String {
        let input = Array(text)
        var output: [Character] = []
        var index = 0
        var inString = false
        var escaped = false
        while index < input.count {
            let char = input[index]
            if inString {
                output.append(char)
                if escaped { escaped = false }
                else if char == "\\" { escaped = true }
                else if char == "\"" { inString = false }
                index += 1
            } else if char == "\"" {
                inString = true
                output.append(char)
                index += 1
            } else if char == "/", index + 1 < input.count, input[index + 1] == "/" {
                index += 2
                while index < input.count, !input[index].isNewline { index += 1 }
                output.append(" ")
            } else if char == "/", index + 1 < input.count, input[index + 1] == "*" {
                index += 2
                while index + 1 < input.count, !(input[index] == "*" && input[index + 1] == "/") { index += 1 }
                guard index + 1 < input.count else { return "" }
                index += 2
                output.append(" ")
            } else {
                output.append(char)
                index += 1
            }
        }
        // Comments have been removed. A second string-aware pass handles trailing commas.
        var result = ""
        inString = false
        escaped = false
        for i in output.indices {
            let char = output[i]
            if !inString, char == "," {
                var next = i + 1
                while next < output.count, output[next].isWhitespace { next += 1 }
                if next < output.count, output[next] == "}" || output[next] == "]" { continue }
            }
            result.append(char)
            if inString {
                if escaped { escaped = false }
                else if char == "\\" { escaped = true }
                else if char == "\"" { inString = false }
            } else if char == "\"" { inString = true }
        }
        return result
    }
}
