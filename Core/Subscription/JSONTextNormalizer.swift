import Foundation

enum JSONTextNormalizer {
    /// Strip comments and trailing commas only outside strings; URLs and escapes stay intact.
    static func normalize(_ text: String) -> String {
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
