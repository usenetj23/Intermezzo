import AppKit
import SwiftUI
import IntermezzoKit

enum ReportError: LocalizedError {
    case cannotCreatePDF(URL)
    case cannotRenderPage(Int)
    case pageCountMismatch

    var errorDescription: String? {
        switch self {
        case .cannotCreatePDF(let url): return String(localized: "Could not create a PDF at \(url.path).")
        case .cannotRenderPage(let n): return String(localized: "Could not render page \(n) of the report.")
        case .pageCountMismatch: return String(localized: "The report has an unexpected number of pages.")
        }
    }
}

/// Writes the report as PDF (summary page + one page per day) or CSV.
@MainActor
enum ReportExporter {
    static let pageSize = CGSize(width: 595, height: 842)

    static func exportPDF(data: ReportData, range: ReportRange, to url: URL,
                          calendar: Calendar = .current) throws {
        let interval = range.interval(calendar: calendar)
        let days = range.days(calendar: calendar)
        var pages: [AnyView] = [AnyView(ReportSummaryPage(data: data, interval: interval, calendar: calendar))]
        pages += days.map { AnyView(DayReportPage(day: $0, data: data, calendar: calendar)) }
        // Render beside the target; read the page count back from the written file
        // and move it into place only when it is one summary + one page per day.
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).pdf.tmp")
        do {
            try render(pages, to: tmp)
            let written = CGPDFDocument(tmp as CFURL)?.numberOfPages ?? 0
            guard ReportLayout.isConsistent(pageCount: written, days: days) else {
                throw ReportError.pageCountMismatch
            }
            try place(tmp, at: url)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw error
        }
    }

    private static func render(_ pages: [AnyView], to url: URL) throws {
        var box = CGRect(origin: .zero, size: pageSize)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { throw ReportError.cannotCreatePDF(url) }
        defer { pdf.closePDF() }
        for (index, page) in pages.enumerated() {
            let renderer = ImageRenderer(content: page.frame(width: pageSize.width, height: pageSize.height))
            renderer.proposedSize = ProposedViewSize(pageSize)
            var drawn = false
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
                drawn = true
            }
            guard drawn else { throw ReportError.cannotRenderPage(index + 1) }
        }
    }

    private static func place(_ tmp: URL, at url: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: url)
        }
    }

    static func exportCSV(data: ReportData, range: ReportRange, to url: URL,
                          calendar: Calendar = .current) throws {
        let interval = range.interval(calendar: calendar)
        let csv = PomodoroCSV.make(records: data.records, projects: data.projects,
                                   from: interval.start, to: interval.end)
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
