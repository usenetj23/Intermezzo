import Foundation

// Helps the model write a rule script for the editor: the contract it must follow, cleaning of its answer
// and a list of risky constructs worth a second look before the script is saved. Pure text work.

public enum RuleScriptAuthor {
    private static let header = "-- Intermezzo Rule:"

    private static func contract(language: String) -> String {
        """
        You write AppleScript rules for a break reminder app on macOS. A rule decides whether the next break \
        should be postponed or skipped right now.
        Contract:
        - The first line is `\(header) <short name>`.
        - The script ends by returning true when the condition is met (the rule fires) and false otherwise.
        - The script only looks at the computer: it must not change, delete, quit, launch or type anything.
        - Values the user may want to tweak (app names, thresholds) are top-level `property` lines holding a list \
        of strings, an integer, a boolean or a string, each with a comment line right above it: `-- Setting: <label>`.
        - Reply with the script only, inside one ```applescript code fence. Write comments and labels in \
        \(language == "pl" ? "Polish" : "English").
        """
    }

    public static func prompt(description: String, examples: [String], language: String) -> AIRequest {
        let shown = examples.enumerated().map { ["Example \($0.offset + 1):", "```applescript", $0.element, "```"].joined(separator: "\n") }
        let system = ([contract(language: language)] + shown).joined(separator: "\n\n")
        return AIRequest(system: system, user: description)
    }

    public static func repairPrompt(description: String, script: String, compilerError: String, language: String) -> AIRequest {
        AIRequest(system: contract(language: language),
                  user: ["Request: \(description)", "", "This script does not compile:", "```applescript", script, "```",
                         "Compiler error: \(compilerError)", "", "Return the corrected script only."].joined(separator: "\n"))
    }

    /// The script out of the model's answer (code fence removed), with the rule header the app expects.
    public static func clean(_ modelText: String, fallbackName: String) -> String {
        var body = modelText
        if let fence = body.range(of: "```[A-Za-z]*\\n", options: .regularExpression) {
            let rest = body[fence.upperBound...]
            body = String(rest.range(of: "```").map { rest[..<$0.lowerBound] } ?? rest)
        }
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = body.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return first.hasPrefix(header) ? body : "\(header) \(fallbackName)\n" + body
    }

    /// The applications a script talks to, by name and by bundle id, each once, in the order they appear.
    public static func applicationReferences(in script: String) -> (names: [String], bundleIDs: [String]) {
        func matches(_ pattern: String) -> [String] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
            var found: [String] = []
            for match in regex.matches(in: script, range: NSRange(script.startIndex..., in: script)) {
                if let range = Range(match.range(at: 1), in: script), !found.contains(String(script[range])) {
                    found.append(String(script[range]))
                }
            }
            return found
        }
        return (matches("\\bapp(?:lication)?\\s+\"([^\"]+)\""), matches("\\bapplication\\s+id\\s+\"([^\"]+)\""))
    }

    /// Constructs a reviewer should look at: each appears at most once, in a fixed order, without regard to case.
    public static func risks(in script: String) -> [String] {
        // A line continuation (¬) can split any phrase over two lines.
        let text = script.replacingOccurrences(of: "¬\\s*\\n\\s*", with: " ", options: .regularExpression)
        let checks: [(label: String, pattern: String)] = [
            ("do shell script", "do\\s+shell\\s+script|event\\s+sysoexec"), ("run script", "\\brun\\s+script\\b"),
            ("sudo", "\\bsudo\\b"), ("rm", "\\brm\\b"), ("delete", "\\bdelete\\b"), ("curl", "\\bcurl\\b"),
            ("keystroke", "\\bkeystroke\\b"), ("key code", "\\bkey\\s+code\\b"), ("click", "\\bclick\\b"),
            ("quit", "\\bquit\\b"), ("activate", "\\bactivate\\b"), ("launch", "\\blaunch\\b"),
            ("do javascript", "\\bdo\\s+javascript\\b"), ("open for access", "\\bopen\\s+for\\s+access\\b"),
            ("administrator privileges", "administrator\\s+privileges"), ("open location", "open\\s+location"),
        ]
        return checks.filter { text.range(of: $0.pattern, options: [.regularExpression, .caseInsensitive]) != nil }.map(\.label)
    }
}
