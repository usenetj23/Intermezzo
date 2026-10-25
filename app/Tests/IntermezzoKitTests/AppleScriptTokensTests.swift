import XCTest
@testable import IntermezzoKit

final class AppleScriptTokensTests: XCTestCase {
    private func spans(_ s: String) -> [(String, AppleScriptTokenKind)] {
        let ns = s as NSString
        return AppleScriptTokens.scan(s).map { (ns.substring(with: $0.range), $0.kind) }
    }

    func testCommentsStringsNumbersKeywords() {
        let out = spans("""
        -- note "not a string"
        property apps : {"Safari", "a\\"b"} # tail
        if h is greater than 12 then return true
        (* block
        comment *) set x to 3.5
        """)
        XCTAssertTrue(out.contains { $0 == ("-- note \"not a string\"", .comment) })
        XCTAssertTrue(out.contains { $0 == ("\"Safari\"", .string) })
        XCTAssertTrue(out.contains { $0 == ("\"a\\\"b\"", .string) })
        XCTAssertTrue(out.contains { $0 == ("# tail", .comment) })
        XCTAssertTrue(out.contains { $0 == ("12", .number) })
        XCTAssertTrue(out.contains { $0 == ("3.5", .number) })
        XCTAssertTrue(out.contains { $0 == ("(* block\ncomment *)", .comment) })
        for kw in ["property", "if", "is", "greater", "than", "then", "return", "true", "set", "to"] {
            XCTAssertTrue(out.contains { $0 == (kw, .keyword) }, kw)
        }
        XCTAssertFalse(out.contains { $0.0 == "apps" })
        XCTAssertFalse(out.contains { $0.0 == "h" })
    }

    func testUnterminatedStringAndCommentRunToEnd() {
        XCTAssertEqual(spans("say \"abc").last?.1, .string)
        XCTAssertEqual(spans("(* open").last?.0, "(* open")
    }

    func testNonASCIIOffsetsAreUTF16() {
        let out = spans("-- zażółć\nreturn \"ą\"")
        XCTAssertEqual(out.map(\.0), ["-- zażółć", "return", "\"ą\""])
    }

    func testIdentifiersContainingKeywordsAreNotKeywords() {
        XCTAssertTrue(spans("set toHour to 1").filter { $0.1 == .keyword }.map(\.0) == ["set", "to"])
    }
}
