import Foundation

public enum AppleScriptTokenKind: Equatable, Sendable {
    case comment, string, number, keyword
}

public struct AppleScriptToken: Equatable, Sendable {
    /// UTF-16 range, ready for NSTextStorage.
    public let range: NSRange
    public let kind: AppleScriptTokenKind
}

/// A small lexer for colouring AppleScript in the script editor: comments (`--`, `#`, `(* *)`),
/// strings, numbers and the language's keywords. Anything else is left plain.
public enum AppleScriptTokens {
    static let keywords: Set<String> = [
        "about", "above", "after", "against", "and", "apart", "around", "as", "aside", "at", "back", "before",
        "beginning", "behind", "below", "beneath", "beside", "between", "but", "by", "considering", "contain",
        "contains", "continue", "copy", "div", "does", "eighth", "else", "end", "equal", "equals", "error",
        "every", "exit", "false", "fifth", "first", "for", "fourth", "from", "front", "get", "given", "global",
        "if", "ignoring", "in", "instead", "into", "is", "it", "its", "last", "local", "me", "middle", "mod",
        "my", "ninth", "not", "of", "on", "onto", "or", "out", "over", "prop", "property", "put", "ref",
        "reference", "repeat", "return", "returning", "script", "second", "set", "seventh", "since", "sixth",
        "some", "tell", "tenth", "than", "that", "the", "then", "third", "through", "thru", "timeout",
        "times", "to", "transaction", "true", "try", "until", "where", "while", "whose", "with", "without",
        "greater", "less", "application", "missing", "value", "count", "exists", "start", "starts", "ends",
    ]

    public static func scan(_ source: String) -> [AppleScriptToken] {
        let s = Array(source.utf16)
        var out: [AppleScriptToken] = []
        var i = 0
        func add(_ start: Int, _ end: Int, _ kind: AppleScriptTokenKind) {
            out.append(AppleScriptToken(range: NSRange(location: start, length: end - start), kind: kind))
        }
        func at(_ k: Int) -> UInt16 { k < s.count ? s[k] : 0 }
        let dash: UInt16 = 45, hash: UInt16 = 35, quote: UInt16 = 34, backslash: UInt16 = 92
        let lparen: UInt16 = 40, rparen: UInt16 = 41, star: UInt16 = 42, newline: UInt16 = 10, dot: UInt16 = 46

        while i < s.count {
            let c = s[i]
            if (c == dash && at(i + 1) == dash) || c == hash {
                let start = i
                while i < s.count && s[i] != newline { i += 1 }
                add(start, i, .comment)
            } else if c == lparen && at(i + 1) == star {
                let start = i
                i += 2
                while i < s.count && !(s[i] == star && at(i + 1) == rparen) { i += 1 }
                i = min(i + 2, s.count)
                add(start, i, .comment)
            } else if c == quote {
                let start = i
                i += 1
                while i < s.count && s[i] != quote { i += s[i] == backslash ? 2 : 1 }
                i = min(i + 1, s.count)
                add(start, i, .string)
            } else if isDigit(c) && !isWordChar(at(i - 1), allowAt: i - 1) {
                let start = i
                while i < s.count && (isDigit(s[i]) || (s[i] == dot && isDigit(at(i + 1)))) { i += 1 }
                add(start, i, .number)
            } else if isLetter(c) {
                let start = i
                while i < s.count && isWordChar(s[i], allowAt: i) { i += 1 }
                let word = String(utf16CodeUnits: Array(s[start..<i]), count: i - start).lowercased()
                if keywords.contains(word) { add(start, i, .keyword) }
            } else {
                i += 1
            }
        }
        return out
    }

    private static func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
    private static func isLetter(_ c: UInt16) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c > 127
    }
    private static func isWordChar(_ c: UInt16, allowAt index: Int) -> Bool {
        index >= 0 && (isLetter(c) || isDigit(c))
    }
}
