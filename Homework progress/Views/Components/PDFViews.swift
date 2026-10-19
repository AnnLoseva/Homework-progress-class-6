//
//  PDFViews.swift
//  Homework progress
//

import SwiftUI
import PDFKit

/// PDFKit's viewer. Works with Apple Pencil and trackpad scrolling; read-only by design —
/// handwriting happens in Notability.
struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}

/// Renders page 1 off the main thread, with a small in-memory cache.
struct PDFThumbnail: View {
    let url: URL
    var size = CGSize(width: 64, height: 84)
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.track)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(2)
            } else {
                Image(systemName: failed ? "exclamationmark.triangle" : "doc.richtext")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
        .task(id: url) {
            let key = url.path as NSString
            if let cached = ThumbnailCache.shared.object(forKey: key) {
                image = cached
                return
            }
            let target = CGSize(width: size.width * 3, height: size.height * 3)
            let fileURL = url
            let rendered = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let page = PDFDocument(url: fileURL)?.page(at: 0) else { return nil }
                return page.thumbnail(of: target, for: .cropBox)
            }.value
            if let rendered {
                ThumbnailCache.shared.setObject(rendered, forKey: key)
                image = rendered
            } else {
                failed = true
            }
        }
    }
}

enum ThumbnailCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        return cache
    }()
}

/// Full-screen PDF reader with a direct "Send to Notability" action.
struct PDFViewerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    let attachment: HomeworkAttachment

    var body: some View {
        let url = services.files.url(forStoredFilename: attachment.storedFilename)
        NavigationStack {
            Group {
                if services.files.fileExists(storedFilename: attachment.storedFilename) {
                    PDFKitView(url: url).ignoresSafeArea(edges: .bottom)
                } else {
                    MissingPDFView(filename: attachment.originalFilename)
                }
            }
            .navigationTitle(attachment.originalFilename)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    SendToNotabilityButton(attachment: attachment, compact: true)
                }
            }
        }
    }
}

struct MissingPDFView: View {
    let filename: String

    var body: some View {
        ContentUnavailableView {
            Label("PDF unavailable", systemImage: "doc.questionmark")
        } description: {
            Text("The app’s copy of “\(filename)” can’t be found. Your progress is safe. Use Replace to import the PDF again.")
        }
    }
}
