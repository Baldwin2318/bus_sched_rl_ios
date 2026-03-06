import Foundation

enum CSVParserError: Error, LocalizedError {
    case malformedQuotedField

    var errorDescription: String? {
        switch self {
        case .malformedQuotedField:
            return "Malformed quoted CSV field"
        }
    }
}

struct CSVParser {
    static func parseLine(_ line: String) throws -> [String] {
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var index = line.startIndex

        while index < line.endIndex {
            let char = line[index]
            if char == "\"" {
                let nextIndex = line.index(after: index)
                if inQuotes, nextIndex < line.endIndex, line[nextIndex] == "\"" {
                    field.append("\"")
                    index = nextIndex
                } else {
                    inQuotes.toggle()
                }
            } else if char == ",", !inQuotes {
                fields.append(field)
                field.removeAll(keepingCapacity: true)
            } else {
                field.append(char)
            }
            index = line.index(after: index)
        }

        if inQuotes {
            throw CSVParserError.malformedQuotedField
        }

        fields.append(field)
        return fields
    }
}
