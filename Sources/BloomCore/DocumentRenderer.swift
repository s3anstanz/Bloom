import AppKit

/// Lays out a text document (TXT, RTF, DOCX, DOC, ODT, HTML) on US Letter pages and saves it as a PDF.
public enum DocumentRenderer {
    @MainActor
    public static func renderPDF(from source: URL, to output: URL) throws {
        let text = try NSAttributedString(url: source, options: [:], documentAttributes: nil)
        let info = NSPrintInfo(dictionary: [.jobSavingURL: output])
        info.jobDisposition = .save
        info.paperSize = NSSize(width: 612, height: 792)
        info.topMargin = 54
        info.bottomMargin = 54
        info.leftMargin = 54
        info.rightMargin = 54
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        view.appearance = NSAppearance(named: .aqua)
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.maxSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        view.textStorage?.setAttributedString(text)
        view.sizeToFit()

        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else { throw ConversionError("Couldn’t save the PDF.") }
    }
}
