import Foundation
import PDFKit
import AppKit

/// Helper for loading and rendering PDF documents
struct PDFDocumentLoader {

    static func load(from url: URL) -> PDFDocumentWrapper? {
        guard let document = PDFDocument(url: url) else { return nil }
        return PDFDocumentWrapper(document: document)
    }
}

struct PDFDocumentWrapper {
    let document: PDFDocument

    var pageCount: Int { document.pageCount }

    func renderFirstPage() -> NSImage? {
        renderPage(at: 0)
    }

    func renderPage(at index: Int, dpi: CGFloat = 300) -> NSImage? {
        guard index < document.pageCount,
              let page = document.page(at: index) else { return nil }

        let pageRect = page.bounds(for: .mediaBox)
        let scale = dpi / 72.0
        let scaledSize = CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale
        )

        let image = NSImage(size: scaledSize)
        image.lockFocus()

        if let context = NSGraphicsContext.current?.cgContext {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: scaledSize))

            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
        }

        image.unlockFocus()
        return image
    }
}
