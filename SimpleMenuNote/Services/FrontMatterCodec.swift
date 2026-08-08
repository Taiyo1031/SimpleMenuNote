import Foundation

struct ParsedMarkdown {
    var id: UUID?
    var createdAt: Date?
    var updatedAt: Date?
    var tagNames: [String]
    var body: String
    var unmanagedLines: [String]
    var hadValidFrontMatter: Bool
}

enum FrontMatterCodec {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ source: String) -> ParsedMarkdown {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard normalized == "---" || normalized.hasPrefix("---\n") else {
            return ParsedMarkdown(
                id: nil,
                createdAt: nil,
                updatedAt: nil,
                tagNames: [],
                body: normalized,
                unmanagedLines: [],
                hadValidFrontMatter: false
            )
        }

        let lines = normalized.components(separatedBy: "\n")
        guard let closingIndex = lines.dropFirst().firstIndex(of: "---") else {
            return ParsedMarkdown(
                id: nil,
                createdAt: nil,
                updatedAt: nil,
                tagNames: [],
                body: normalized,
                unmanagedLines: [],
                hadValidFrontMatter: false
            )
        }

        let header = Array(lines[1..<closingIndex])
        let bodyStart = closingIndex + 1
        var bodyLines = bodyStart < lines.count ? Array(lines[bodyStart...]) : []
        if bodyLines.first == "" { bodyLines.removeFirst() }

        var id: UUID?
        var createdAt: Date?
        var updatedAt: Date?
        var tagNames: [String] = []
        var unmanaged: [String] = []
        var index = 0

        while index < header.count {
            let line = header[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let value = scalarValue(for: "id", in: trimmed) {
                id = UUID(uuidString: unquote(value))
                index += 1
                continue
            }
            if let value = scalarValue(for: "created", in: trimmed) {
                createdAt = parseDate(unquote(value))
                index += 1
                continue
            }
            if let value = scalarValue(for: "updated", in: trimmed) {
                updatedAt = parseDate(unquote(value))
                index += 1
                continue
            }
            if trimmed == "tags:" {
                index += 1
                while index < header.count {
                    let candidate = header[index]
                    let candidateTrimmed = candidate.trimmingCharacters(in: .whitespaces)
                    guard candidateTrimmed.hasPrefix("- ") else { break }
                    let raw = String(candidateTrimmed.dropFirst(2))
                    let name = unquote(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { tagNames.append(name) }
                    index += 1
                }
                continue
            }

            unmanaged.append(line)
            index += 1
        }

        return ParsedMarkdown(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            tagNames: tagNames,
            body: bodyLines.joined(separator: "\n"),
            unmanagedLines: unmanaged,
            hadValidFrontMatter: true
        )
    }

    static func render(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        tagNames: [String],
        body: String,
        unmanagedLines: [String]
    ) -> String {
        var lines = [
            "---",
            "id: \(quote(id.uuidString))",
            "created: \(quote(standardFormatter.string(from: createdAt)))",
            "updated: \(quote(standardFormatter.string(from: updatedAt)))"
        ]
        lines.append(contentsOf: unmanagedLines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return scalarValue(for: "id", in: trimmed) == nil
                && scalarValue(for: "created", in: trimmed) == nil
                && scalarValue(for: "updated", in: trimmed) == nil
                && trimmed != "tags:"
        })
        lines.append("tags:")
        lines.append(contentsOf: tagNames.map { "  - \(quote($0))" })
        lines.append("---")
        lines.append("")
        lines.append(body)
        return lines.joined(separator: "\n")
    }

    private static func scalarValue(for key: String, in line: String) -> String? {
        let prefix = "\(key):"
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    private static func parseDate(_ value: String) -> Date? {
        fractionalFormatter.date(from: value) ?? standardFormatter.date(from: value)
    }

    private static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.first == "\"", value.last == "\"" else {
            return value
        }
        let inner = String(value.dropFirst().dropLast())
        var result = ""
        var escaped = false
        for character in inner {
            if escaped {
                switch character {
                case "n": result.append("\n")
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                default:
                    result.append("\\")
                    result.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        if escaped { result.append("\\") }
        return result
    }
}
