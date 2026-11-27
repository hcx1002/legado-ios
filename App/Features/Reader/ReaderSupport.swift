import AVFoundation
import MediaPlayer
import SafariServices
import SwiftUI
import UIKit

struct ReaderChapterCommentsView: View {
    let target: ReaderChapterCommentsTarget

    @Environment(\.dismiss) private var dismiss
    @State private var state: StateOfComments = .loading
    @State private var attempt = 0
    @State private var showsSourcePage = false
    @State private var pages = ReaderChapterCommentPages()
    @State private var more: MoreComments = .idle

    private enum StateOfComments {
        case loading, loaded, page(URL), failed(String)
    }

    private enum MoreComments { case idle, loading(URL), failed(String) }

    var body: some View {
        ReadingNavigationStack {
            List {
                Section {
                    if target.source.ruleReview?.supportsChapterComments == true ||
                        target.source.ruleReview?.supportsChapterCommentsPage == true {
                        sourceComments
                    }
                    if let official = target.official {
                        Link(destination: official.url) {
                            Label("在\(official.platformName)查看此章", systemImage: "arrow.up.right.square")
                        }
                        .accessibilityIdentifier("reader.comments.officialChapter")
                    }
                } header: {
                    Text(target.chapter.title)
                } footer: {
                    if let official = target.official {
                        if official.platform == .fanqie {
                            Text("在官方章节页进入番茄小说 App，在章节结尾选择「\(official.discussionName)」。")
                        } else {
                            Text("打开官方章节后，在阅读页选择「\(official.discussionName)」。")
                        }
                    }
                }
            }
            .navigationTitle("本章评论")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .accessibilityIdentifier("reader.comments.close")
                }
            }
        }
        .readingPresentationDetents([.medium, .large])
        .readingPresentationDragIndicator()
        .sheet(isPresented: $showsSourcePage) {
            if case .page(let url) = state {
                ReaderCommentsBrowser(url: url, close: { showsSourcePage = false })
                    .ignoresSafeArea()
            }
        }
        .task(id: attempt) {
            let service = NetworkBookService()
            if case .loading(let nextURL) = more {
                do {
                    let page = try await service.loadChapterCommentsPage(
                        book: target.book, chapter: target.chapter, source: target.source, nextPageURL: nextURL
                    )
                    guard !Task.isCancelled else { return }
                    pages.append(page, requestedURL: nextURL)
                    more = .idle
                } catch {
                    guard !Task.isCancelled else { return }
                    more = .failed(error.localizedDescription)
                }
                return
            }
            guard case .loading = state else { return }
            do {
                if target.source.ruleReview?.supportsChapterComments == true {
                    let page = try await service.loadChapterCommentsPage(
                        book: target.book, chapter: target.chapter, source: target.source
                    )
                    guard !Task.isCancelled else { return }
                    pages.append(page, requestedURL: nil)
                    state = .loaded
                } else if target.source.ruleReview?.supportsChapterCommentsPage == true {
                    let url = try await service.chapterCommentsPageURL(
                        book: target.book, chapter: target.chapter, source: target.source
                    )
                    guard !Task.isCancelled else { return }
                    state = .page(url)
                }
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }

    @ViewBuilder private var sourceComments: some View {
        switch state {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("正在加载评论")
            }
        case .page:
            Button {
                showsSourcePage = true
            } label: {
                Label("打开书源评论页", systemImage: "safari")
            }
            .accessibilityIdentifier("reader.comments.sourcePage")
        case .failed(let message):
            Text(message)
                .accessibilityIdentifier("reader.comments.error")
            Button("重试") {
                state = .loading
                attempt += 1
            }
            .accessibilityIdentifier("reader.comments.retry")
        case .loaded:
            if pages.comments.isEmpty, pages.nextPageURL == nil {
                Text("本章暂无评论")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("reader.comments.empty")
            } else {
                ForEach(pages.comments) { comment in
                    VStack(alignment: .leading, spacing: 6) {
                        if let author = comment.author {
                            Text(author).font(.subheadline.weight(.semibold))
                        }
                        Text(comment.content).textSelection(.enabled)
                        if let postedAt = comment.postedAt {
                            Text(postedAt).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
                if let nextURL = pages.nextPageURL {
                    switch more {
                    case .loading:
                        ProgressView("正在加载更多评论")
                    case .idle:
                        Button("加载更多") { loadMore(nextURL) }
                            .accessibilityIdentifier("reader.comments.more")
                    case .failed(let message):
                        Text(message).accessibilityIdentifier("reader.comments.moreError")
                        Button("重试加载更多") { loadMore(nextURL) }
                            .accessibilityIdentifier("reader.comments.retryMore")
                    }
                }
            }
        }
    }

    private func loadMore(_ url: URL) {
        guard pages.nextPageURL == url else { return }
        if case .loading = more { return }
        more = .loading(url)
        attempt += 1
    }
}

private struct ReaderCommentsBrowser: UIViewControllerRepresentable {
    let url: URL
    let close: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(close: close) }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let close: () -> Void
        init(close: @escaping () -> Void) { self.close = close }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { close() }
    }
}

extension NSAttributedString.Key {
    static let legadoInteractiveImage = NSAttributedString.Key("legado.interactiveImage")
}

final class ReaderInlineImageAttachment: NSTextAttachment {
    let descriptor: ChapterImageDescriptor

    init(descriptor: ChapterImageDescriptor) {
        self.descriptor = descriptor
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
enum ReaderAttributedContentBuilder {
    static func containsImageMarkup(_ text: String) -> Bool {
        text.range(of: "<img", options: .caseInsensitive) != nil
            || text.range(of: "<mip-img", options: .caseInsensitive) != nil
    }

    static func build(
        body: String,
        bodyAttributes: [NSAttributedString.Key: Any],
        contentWidth: CGFloat,
        fontSize: CGFloat,
        displayScale: CGFloat = UIScreen.main.scale,
        foregroundColor: UIColor = .label
    ) -> NSAttributedString {
        guard containsImageMarkup(body) else {
            return NSAttributedString(string: body, attributes: bodyAttributes)
        }
        let tags = ChapterImageParser().imageTags(in: body)
        guard !tags.isEmpty else {
            return NSAttributedString(string: body, attributes: bodyAttributes)
        }

        let usableWidth = max(contentWidth, 120)
        let result = NSMutableAttributedString()
        var cursor = body.startIndex

        for (range, descriptor) in tags {
            if cursor < range.lowerBound {
                let textSegment = String(body[cursor..<range.lowerBound])
                result.append(NSAttributedString(string: textSegment, attributes: bodyAttributes))
            }
            if let attachmentString = makeAttachmentString(
                for: descriptor,
                bodyAttributes: bodyAttributes,
                usableWidth: usableWidth,
                fontSize: fontSize,
                displayScale: displayScale,
                foregroundColor: foregroundColor
            ) {
                result.append(attachmentString)
            }
            cursor = range.upperBound
        }

        if cursor < body.endIndex {
            let tail = String(body[cursor...])
            result.append(NSAttributedString(string: tail, attributes: bodyAttributes))
        }
        return result
    }

    private static func makeAttachmentString(
        for descriptor: ChapterImageDescriptor,
        bodyAttributes: [NSAttributedString.Key: Any],
        usableWidth: CGFloat,
        fontSize: CGFloat,
        displayScale: CGFloat,
        foregroundColor: UIColor
    ) -> NSAttributedString? {
        let isInlineTextStyle = descriptor.style?.uppercased() == "TEXT"
        let inlineTargetHeight: CGFloat? = isInlineTextStyle ? max(fontSize * 1.3, 18) : nil

        let image: UIImage?
        if let (mime, data) = ChapterImageParser.decodeDataURI(descriptor.rawAddress) {
            if isSVG(mime: mime, data: data) {
                image = ReaderSVGRenderer.shared.render(
                    svgData: data,
                    targetWidth: usableWidth,
                    inlineHeight: inlineTargetHeight,
                    scale: displayScale
                )
            } else {
                image = UIImage(data: data)
            }
        } else if descriptor.clickJS != nil {
            image = makeFallbackBadgeImage(
                title: "查看评论 〉",
                width: min(usableWidth, 180),
                fontSize: max(fontSize * 0.8, 13),
                foreground: foregroundColor,
                scale: displayScale
            )
        } else {
            image = nil
        }

        guard let image, image.size.width > 0, image.size.height > 0 else { return nil }
        let attachment = ReaderInlineImageAttachment(descriptor: descriptor)
        attachment.image = image

        let drawSize: CGSize
        if isInlineTextStyle, let inlineTargetHeight, image.size.width / image.size.height <= 4 {
            let ratio = image.size.width / image.size.height
            let h = inlineTargetHeight
            drawSize = CGSize(width: min(h * ratio, usableWidth), height: h)
            attachment.bounds = CGRect(x: 0, y: -(h - fontSize) * 0.3, width: drawSize.width, height: drawSize.height)
        } else {
            let width = min(image.size.width, usableWidth)
            let ratio = image.size.height / image.size.width
            let height = max(width * ratio, 16)
            drawSize = CGSize(width: width, height: height)
            attachment.bounds = CGRect(x: 0, y: 0, width: drawSize.width, height: drawSize.height)
        }

        var attributes: [NSAttributedString.Key: Any] = [
            .legadoInteractiveImage: descriptor
        ]
        if !isInlineTextStyle || drawSize.width > usableWidth * 0.5 {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.firstLineHeadIndent = 0
            paragraph.headIndent = 0
            paragraph.paragraphSpacingBefore = 6
            paragraph.paragraphSpacing = 8
            paragraph.lineSpacing = 0
            attributes[.paragraphStyle] = paragraph
        } else if let font = bodyAttributes[.font] {
            attributes[.font] = font
        }

        let output = NSMutableAttributedString(attachment: attachment)
        output.addAttributes(attributes, range: NSRange(location: 0, length: output.length))
        return output
    }

    private static func isSVG(mime: String?, data: Data) -> Bool {
        if mime?.lowercased().contains("svg") == true { return true }
        guard let prefix = String(data: data.prefix(256), encoding: .utf8)?.lowercased() else { return false }
        return prefix.contains("<svg")
    }

    private static func makeFallbackBadgeImage(
        title: String,
        width: CGFloat,
        fontSize: CGFloat,
        foreground: UIColor,
        scale: CGFloat
    ) -> UIImage {
        let height = ceil(fontSize * 2.1)
        let format = UIGraphicsImageRendererFormat()
        format.scale = max(scale, 1)
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            let rect = CGRect(x: 1, y: 1, width: width - 2, height: height - 2)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: height / 2)
            foreground.withAlphaComponent(0.08).setFill()
            path.fill()
            foreground.withAlphaComponent(0.25).setStroke()
            path.lineWidth = 1
            path.stroke()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: foreground.withAlphaComponent(0.85)
            ]
            let text = title as NSString
            let size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (width - size.width) / 2, y: (height - size.height) / 2), withAttributes: attrs)
        }
    }
}

/// Fast, synchronous native SVG vector renderer for inline comment cards and badges.
@MainActor
final class ReaderSVGRenderer {
    static let shared = ReaderSVGRenderer()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 120
    }

    func render(svgData: Data, targetWidth: CGFloat, inlineHeight: CGFloat? = nil, scale: CGFloat = UIScreen.main.scale) -> UIImage? {
        guard !svgData.isEmpty else { return nil }
        let key = "\(svgData.hashValue)|\(Int(targetWidth.rounded()))|\(Int((inlineHeight ?? 0).rounded()))|\(Int(scale.rounded()))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let parser = SVGDocumentParser()
        guard let doc = parser.parse(data: svgData), doc.viewBox.width > 0, doc.viewBox.height > 0 else {
            return nil
        }

        let vb = doc.viewBox
        let outSize: CGSize
        if let inlineHeight, vb.width / vb.height <= 4 {
            let ratio = vb.width / vb.height
            let h = inlineHeight
            outSize = CGSize(width: min(max(h * ratio, 12), targetWidth), height: max(h, 12))
        } else {
            let maxW = max(targetWidth, 60)
            let desiredW = vb.width >= 240 ? maxW : min(vb.width, maxW)
            let ratio = vb.height / vb.width
            outSize = CGSize(width: desiredW, height: max(desiredW * ratio, 16))
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = max(scale, 1)
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: outSize, format: format).image { rendererContext in
            let cg = rendererContext.cgContext
            cg.saveGState()
            cg.scaleBy(x: outSize.width / vb.width, y: outSize.height / vb.height)
            cg.translateBy(x: -vb.minX, y: -vb.minY)
            for node in doc.nodes {
                draw(node: node, in: cg, viewBox: vb)
            }
            cg.restoreGState()
        }
        cache.setObject(image, forKey: key)
        return image
    }

    private func draw(node: SVGNode, in cg: CGContext, viewBox: CGRect) {
        cg.saveGState()
        if node.style.opacity < 1 {
            cg.setAlpha(CGFloat(max(0, min(node.style.opacity, 1))))
        }
        if node.translate != .zero {
            cg.translateBy(x: node.translate.x, y: node.translate.y)
        }
        switch node.kind {
        case .rect(let x, let y, let w, let h, let rx, let ry):
            let rect = CGRect(x: x, y: y, width: w, height: h)
            let radius = min(max(rx, ry), min(w, h) / 2)
            let path = radius > 0 ? UIBezierPath(roundedRect: rect, cornerRadius: radius) : UIBezierPath(rect: rect)
            fillAndStroke(path: path, style: node.style, in: cg)
        case .circle(let cx, let cy, let r):
            let path = UIBezierPath(ovalIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            fillAndStroke(path: path, style: node.style, in: cg)
        case .ellipse(let cx, let cy, let rx, let ry):
            let path = UIBezierPath(ovalIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
            fillAndStroke(path: path, style: node.style, in: cg)
        case .line(let x1, let y1, let x2, let y2):
            let path = UIBezierPath()
            path.move(to: CGPoint(x: x1, y: y1))
            path.addLine(to: CGPoint(x: x2, y: y2))
            fillAndStroke(path: path, style: node.style, in: cg)
        case .polygon(let points, let closed):
            guard let first = points.first else { break }
            let path = UIBezierPath()
            path.move(to: first)
            for pt in points.dropFirst() { path.addLine(to: pt) }
            if closed { path.close() }
            fillAndStroke(path: path, style: node.style, in: cg)
        case .path(let d):
            if let path = SVGPathBuilder.build(d) {
                fillAndStroke(path: path, style: node.style, in: cg)
            }
        case .text(let x, let y, let content):
            let trimmed = content.replacingOccurrences(of: "\n", with: " ")
            guard !trimmed.isEmpty else { break }
            let fontSize = max(node.style.fontSize, 8)
            let font = UIFont.systemFont(ofSize: fontSize, weight: node.style.isBold ? .bold : .regular)
            let fillColor = (node.style.fill ?? .black).withAlphaComponent(node.style.fillAlpha)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: fillColor
            ]
            let nsText = trimmed as NSString
            let textSize = nsText.size(withAttributes: attrs)
            let drawX: CGFloat
            switch node.style.textAnchor {
            case "middle": drawX = x - textSize.width / 2
            case "end": drawX = x - textSize.width
            default: drawX = x
            }
            let drawY: CGFloat
            if node.style.dominantBaseline == "middle" || node.style.dominantBaseline == "central" {
                drawY = y - textSize.height / 2
            } else {
                drawY = y - font.ascender
            }
            UIGraphicsPushContext(cg)
            nsText.draw(at: CGPoint(x: drawX, y: drawY), withAttributes: attrs)
            UIGraphicsPopContext()
        }
        cg.restoreGState()
    }

    private func fillAndStroke(path: UIBezierPath, style: SVGStyle, in cg: CGContext) {
        if let fill = style.fill {
            cg.addPath(path.cgPath)
            cg.setFillColor(fill.withAlphaComponent(style.fillAlpha).cgColor)
            cg.fillPath()
        }
        if let stroke = style.stroke, style.strokeWidth > 0 {
            cg.addPath(path.cgPath)
            cg.setStrokeColor(stroke.withAlphaComponent(style.strokeAlpha).cgColor)
            cg.setLineWidth(style.strokeWidth)
            cg.strokePath()
        }
    }
}

private struct SVGStyle {
    var fill: UIColor? = .black
    var fillExplicit = false
    var fillOpacity: CGFloat = 1
    var stroke: UIColor? = nil
    var strokeWidth: CGFloat = 1
    var strokeOpacity: CGFloat = 1
    var opacity: CGFloat = 1
    var fontSize: CGFloat = 16
    var isBold = false
    var textAnchor = "start"
    var dominantBaseline = "auto"

    var fillAlpha: CGFloat {
        guard let fill else { return 0 }
        var a: CGFloat = 1
        fill.getRed(nil, green: nil, blue: nil, alpha: &a)
        return a * fillOpacity
    }

    var strokeAlpha: CGFloat {
        guard let stroke else { return 0 }
        var a: CGFloat = 1
        stroke.getRed(nil, green: nil, blue: nil, alpha: &a)
        return a * strokeOpacity
    }
}

private struct SVGNode {
    enum Kind {
        case rect(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, rx: CGFloat, ry: CGFloat)
        case circle(cx: CGFloat, cy: CGFloat, r: CGFloat)
        case ellipse(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat)
        case line(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat)
        case polygon(points: [CGPoint], closed: Bool)
        case path(d: String)
        case text(x: CGFloat, y: CGFloat, content: String)
    }

    let kind: Kind
    let style: SVGStyle
    let translate: CGPoint
}

private struct SVGDocument {
    let viewBox: CGRect
    let nodes: [SVGNode]
}

private final class SVGDocumentParser: NSObject, XMLParserDelegate {
    private var viewBox = CGRect.zero
    private var nodes: [SVGNode] = []
    private var styleStack: [SVGStyle] = [SVGStyle()]
    private var translateStack: [CGPoint] = [.zero]

    private var activeText: (x: CGFloat, y: CGFloat, style: SVGStyle, translate: CGPoint, buffer: String)?

    func parse(data: Data) -> SVGDocument? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { return nil }
        if viewBox.width <= 0 || viewBox.height <= 0 {
            viewBox = CGRect(x: 0, y: 0, width: 300, height: 150)
        }
        return SVGDocument(viewBox: viewBox, nodes: nodes)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        let tag = elementName.lowercased()
        let attrs = mergedAttributes(attributeDict)
        let parentStyle = styleStack.last ?? SVGStyle()
        let style = applying(attrs: attrs, to: parentStyle, isLine: tag == "line")
        let parentTranslate = translateStack.last ?? .zero
        let localTranslate = parseTranslate(attrs["transform"])
        let combinedTranslate = CGPoint(x: parentTranslate.x + localTranslate.x, y: parentTranslate.y + localTranslate.y)

        styleStack.append(style)
        translateStack.append(combinedTranslate)

        switch tag {
        case "svg":
            if let vb = attrs["viewbox"] ?? attrs["viewBox"] {
                let nums = parseNumbers(vb)
                if nums.count == 4, nums[2] > 0, nums[3] > 0 {
                    viewBox = CGRect(x: nums[0], y: nums[1], width: nums[2], height: nums[3])
                }
            }
            if viewBox.width <= 0 || viewBox.height <= 0 {
                let w = parseLength(attrs["width"], reference: 300) ?? 300
                let h = parseLength(attrs["height"], reference: 150) ?? 150
                viewBox = CGRect(x: 0, y: 0, width: w, height: h)
            }
        case "rect":
            let x = parseLength(attrs["x"], reference: viewBox.width) ?? 0
            let y = parseLength(attrs["y"], reference: viewBox.height) ?? 0
            let w = parseLength(attrs["width"], reference: viewBox.width) ?? 0
            let h = parseLength(attrs["height"], reference: viewBox.height) ?? 0
            let rx = parseLength(attrs["rx"], reference: viewBox.width) ?? 0
            let ry = parseLength(attrs["ry"], reference: viewBox.height) ?? rx
            if w > 0, h > 0 {
                nodes.append(.init(kind: .rect(x: x, y: y, w: w, h: h, rx: rx, ry: ry), style: style, translate: combinedTranslate))
            }
        case "circle":
            let cx = parseLength(attrs["cx"], reference: viewBox.width) ?? 0
            let cy = parseLength(attrs["cy"], reference: viewBox.height) ?? 0
            let r = parseLength(attrs["r"], reference: min(viewBox.width, viewBox.height)) ?? 0
            if r > 0 {
                nodes.append(.init(kind: .circle(cx: cx, cy: cy, r: r), style: style, translate: combinedTranslate))
            }
        case "ellipse":
            let cx = parseLength(attrs["cx"], reference: viewBox.width) ?? 0
            let cy = parseLength(attrs["cy"], reference: viewBox.height) ?? 0
            let rx = parseLength(attrs["rx"], reference: viewBox.width) ?? 0
            let ry = parseLength(attrs["ry"], reference: viewBox.height) ?? 0
            if rx > 0, ry > 0 {
                nodes.append(.init(kind: .ellipse(cx: cx, cy: cy, rx: rx, ry: ry), style: style, translate: combinedTranslate))
            }
        case "line":
            let x1 = parseLength(attrs["x1"], reference: viewBox.width) ?? 0
            let y1 = parseLength(attrs["y1"], reference: viewBox.height) ?? 0
            let x2 = parseLength(attrs["x2"], reference: viewBox.width) ?? 0
            let y2 = parseLength(attrs["y2"], reference: viewBox.height) ?? 0
            nodes.append(.init(kind: .line(x1: x1, y1: y1, x2: x2, y2: y2), style: style, translate: combinedTranslate))
        case "polygon", "polyline":
            let nums = parseNumbers(attrs["points"] ?? "")
            var pts: [CGPoint] = []
            var idx = 0
            while idx + 1 < nums.count {
                pts.append(CGPoint(x: nums[idx], y: nums[idx + 1]))
                idx += 2
            }
            if !pts.isEmpty {
                nodes.append(.init(kind: .polygon(points: pts, closed: tag == "polygon"), style: style, translate: combinedTranslate))
            }
        case "path":
            if let d = attrs["d"], !d.isEmpty {
                nodes.append(.init(kind: .path(d: d), style: style, translate: combinedTranslate))
            }
        case "text":
            let x = parseLength(attrs["x"], reference: viewBox.width) ?? 0
            let y = parseLength(attrs["y"], reference: viewBox.height) ?? 0
            activeText = (x, y, style, combinedTranslate, "")
        case "tspan":
            if var current = activeText {
                if !current.buffer.isEmpty {
                    nodes.append(.init(kind: .text(x: current.x, y: current.y, content: current.buffer), style: current.style, translate: current.translate))
                    current.buffer = ""
                }
                if let x = parseLength(attrs["x"], reference: viewBox.width) { current.x = x }
                if let y = parseLength(attrs["y"], reference: viewBox.height) { current.y = y }
                if let dx = parseLength(attrs["dx"], reference: viewBox.width) { current.x += dx }
                if let dy = parseLength(attrs["dy"], reference: viewBox.height) { current.y += dy }
                current.style = style
                activeText = current
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if var current = activeText {
            current.buffer += string
            activeText = current
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let tag = elementName.lowercased()
        if tag == "text", let current = activeText {
            if !current.buffer.isEmpty {
                nodes.append(.init(kind: .text(x: current.x, y: current.y, content: current.buffer), style: current.style, translate: current.translate))
            }
            activeText = nil
        }
        if styleStack.count > 1 { styleStack.removeLast() }
        if translateStack.count > 1 { translateStack.removeLast() }
    }

    private func mergedAttributes(_ raw: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (k, v) in raw { result[k.lowercased()] = v }
        if let inline = result["style"] {
            for part in inline.split(separator: ";") {
                let pair = part.split(separator: ":", maxSplits: 1)
                if pair.count == 2 {
                    let key = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let val = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !key.isEmpty { result[key] = val }
                }
            }
        }
        return result
    }

    private func applying(attrs: [String: String], to base: SVGStyle, isLine: Bool) -> SVGStyle {
        var style = base
        if isLine, !style.fillExplicit { style.fill = nil }
        if let fill = attrs["fill"] {
            style.fill = parseColor(fill)
            style.fillExplicit = true
        }
        if let fo = attrs["fill-opacity"], let v = Double(fo.trimmingCharacters(in: .whitespaces)) {
            style.fillOpacity = CGFloat(v)
        }
        if let stroke = attrs["stroke"] {
            style.stroke = parseColor(stroke)
        }
        if let sw = attrs["stroke-width"], let v = parseLength(sw, reference: 1) {
            style.strokeWidth = v
        }
        if let so = attrs["stroke-opacity"], let v = Double(so.trimmingCharacters(in: .whitespaces)) {
            style.strokeOpacity = CGFloat(v)
        }
        if let op = attrs["opacity"], let v = Double(op.trimmingCharacters(in: .whitespaces)) {
            style.opacity *= CGFloat(v)
        }
        if let fs = attrs["font-size"], let v = parseLength(fs, reference: 16) {
            style.fontSize = v
        }
        if let fw = attrs["font-weight"]?.lowercased() {
            if fw == "bold" || fw == "bolder" { style.isBold = true }
            else if fw == "normal" { style.isBold = false }
            else if let n = Int(fw) { style.isBold = n >= 600 }
        }
        if let anchor = attrs["text-anchor"]?.lowercased() {
            style.textAnchor = anchor
        }
        if let baseline = attrs["dominant-baseline"]?.lowercased() {
            style.dominantBaseline = baseline
        }
        return style
    }

    private func parseLength(_ raw: String?, reference: CGFloat) -> CGFloat? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.hasSuffix("%") {
            s.removeLast()
            return Double(s).map { CGFloat($0) / 100 * reference }
        }
        for suffix in ["px", "pt", "em", "rem"] where s.lowercased().hasSuffix(suffix) {
            s = String(s.dropLast(suffix.count))
            break
        }
        return Double(s).map { CGFloat($0) }
    }

    private func parseNumbers(_ raw: String) -> [CGFloat] {
        guard let regex = try? NSRegularExpression(pattern: #"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"#) else { return [] }
        return regex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)).compactMap { match in
            guard let range = Range(match.range, in: raw), let val = Double(raw[range]) else { return nil }
            return CGFloat(val)
        }
    }

    private func parseTranslate(_ transform: String?) -> CGPoint {
        guard let transform,
              let range = transform.range(of: #"translate\s*\(([^)]+)\)"#, options: .regularExpression) else { return .zero }
        let nums = parseNumbers(String(transform[range]))
        if nums.count >= 2 { return CGPoint(x: nums[0], y: nums[1]) }
        if nums.count == 1 { return CGPoint(x: nums[0], y: 0) }
        return .zero
    }

    private func parseColor(_ raw: String) -> UIColor? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty || s == "none" || s == "transparent" { return nil }
        if s.hasPrefix("#") {
            let hex = String(s.dropFirst())
            var value: UInt64 = 0
            guard Scanner(string: hex).scanHexInt64(&value) else { return nil }
            switch hex.count {
            case 3:
                let r = CGFloat((value >> 8) & 0xF) / 15
                let g = CGFloat((value >> 4) & 0xF) / 15
                let b = CGFloat(value & 0xF) / 15
                return UIColor(red: r, green: g, blue: b, alpha: 1)
            case 6:
                let r = CGFloat((value >> 16) & 0xFF) / 255
                let g = CGFloat((value >> 8) & 0xFF) / 255
                let b = CGFloat(value & 0xFF) / 255
                return UIColor(red: r, green: g, blue: b, alpha: 1)
            case 8:
                let r = CGFloat((value >> 24) & 0xFF) / 255
                let g = CGFloat((value >> 16) & 0xFF) / 255
                let b = CGFloat((value >> 8) & 0xFF) / 255
                let a = CGFloat(value & 0xFF) / 255
                return UIColor(red: r, green: g, blue: b, alpha: a)
            default:
                return nil
            }
        }
        if s.hasPrefix("rgba(") || s.hasPrefix("rgb(") {
            let nums = parseNumbers(s)
            guard nums.count >= 3 else { return nil }
            let a = nums.count >= 4 ? nums[3] : 1
            return UIColor(red: nums[0] / 255, green: nums[1] / 255, blue: nums[2] / 255, alpha: a)
        }
        switch s {
        case "white": return .white
        case "black": return .black
        case "red": return .systemRed
        case "gray", "grey": return .systemGray
        case "blue": return .systemBlue
        case "green": return .systemGreen
        case "orange": return .systemOrange
        case "yellow": return .systemYellow
        case "pink": return .systemPink
        case "purple": return .systemPurple
        default: return nil
        }
    }
}

private enum SVGPathBuilder {
    static func build(_ d: String) -> UIBezierPath? {
        guard let regex = try? NSRegularExpression(pattern: #"[MmLlHhVvQqCcZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"#) else { return nil }
        let tokens = regex.matches(in: d, range: NSRange(d.startIndex..., in: d)).compactMap {
            Range($0.range, in: d).map { String(d[$0]) }
        }
        guard !tokens.isEmpty else { return nil }
        let path = UIBezierPath()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var command: Character = "M"
        var index = 0

        func nextNum() -> CGFloat? {
            guard index < tokens.count, let v = Double(tokens[index]) else { return nil }
            index += 1
            return CGFloat(v)
        }

        while index < tokens.count {
            let token = tokens[index]
            if token.count == 1, let ch = token.first, ch.isLetter {
                command = ch
                index += 1
                if command == "Z" || command == "z" {
                    path.close()
                    current = start
                    continue
                }
            }
            switch command {
            case "M", "m":
                guard let x = nextNum(), let y = nextNum() else { index += 1; continue }
                let pt = command == "m" ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.move(to: pt)
                current = pt
                start = pt
                command = command == "m" ? "l" : "L"
            case "L", "l":
                guard let x = nextNum(), let y = nextNum() else { index += 1; continue }
                let pt = command == "l" ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addLine(to: pt)
                current = pt
            case "H", "h":
                guard let x = nextNum() else { index += 1; continue }
                let pt = CGPoint(x: command == "h" ? current.x + x : x, y: current.y)
                path.addLine(to: pt)
                current = pt
            case "V", "v":
                guard let y = nextNum() else { index += 1; continue }
                let pt = CGPoint(x: current.x, y: command == "v" ? current.y + y : y)
                path.addLine(to: pt)
                current = pt
            case "Q", "q":
                guard let cx = nextNum(), let cy = nextNum(), let x = nextNum(), let y = nextNum() else { index += 1; continue }
                let ctrl = command == "q" ? CGPoint(x: current.x + cx, y: current.y + cy) : CGPoint(x: cx, y: cy)
                let pt = command == "q" ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addQuadCurve(to: pt, controlPoint: ctrl)
                current = pt
            case "C", "c":
                guard let c1x = nextNum(), let c1y = nextNum(), let c2x = nextNum(), let c2y = nextNum(), let x = nextNum(), let y = nextNum() else { index += 1; continue }
                let c1 = command == "c" ? CGPoint(x: current.x + c1x, y: current.y + c1y) : CGPoint(x: c1x, y: c1y)
                let c2 = command == "c" ? CGPoint(x: current.x + c2x, y: current.y + c2y) : CGPoint(x: c2x, y: c2y)
                let pt = command == "c" ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addCurve(to: pt, controlPoint1: c1, controlPoint2: c2)
                current = pt
            default:
                index += 1
            }
        }
        return path
    }
}

struct ReaderInteractivePopEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.enableInteractivePopIfAvailable()
    }

    static func dismantleUIViewController(_ uiViewController: Controller, coordinator: Void) {
        uiViewController.restoreInteractivePopDelegate()
    }

    final class Controller: UIViewController {
        private weak var popGesture: UIGestureRecognizer?
        private var previousDelegate: (any UIGestureRecognizerDelegate)?
        private var releasedDelegate = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enableInteractivePopIfAvailable()
        }

        func enableInteractivePopIfAvailable() {
            guard let navigationController,
                  navigationController.viewControllers.count > 1,
                  let gesture = navigationController.interactivePopGestureRecognizer else { return }
            if gesture.delegate != nil {
                previousDelegate = gesture.delegate
                gesture.delegate = nil
                releasedDelegate = true
            }
            gesture.isEnabled = true
            popGesture = gesture
        }

        func restoreInteractivePopDelegate() {
            guard releasedDelegate, let popGesture, popGesture.delegate == nil else { return }
            popGesture.delegate = previousDelegate
            previousDelegate = nil
            releasedDelegate = false
        }

    }
}

struct ReaderMenuDismissShape: Shape {
    var leadingExclusion: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        Path(CGRect(
            x: min(max(leadingExclusion, 0), rect.width),
            y: 0,
            width: max(rect.width - leadingExclusion, 0),
            height: rect.height
        ))
    }
}

@MainActor enum ReaderScreenOrientation {
    static private(set) var supportedOrientations: UIInterfaceOrientationMask = .allButUpsideDown

    static func apply(_ value: String) {
        let mask: UIInterfaceOrientationMask = switch value {
        case "1": .portrait
        case "2": .landscape
        case "3": .all
        case "4": .portraitUpsideDown
        case "5": .landscapeLeft
        default: .allButUpsideDown
        }
        supportedOrientations = mask
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        if #available(iOS 16.0, *) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
            scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    static func restoreApplicationDefault() { apply("0") }
}

struct ReaderChapterSlider: View {
    let directory: ReaderChapterDirectory
    let currentNumber: Int
    let progress: Double
    let onSelect: (Int) -> Void
    @State private var previewNumber: Int?

    var body: some View {
        let count = directory.readableIndices.count
        let number = previewNumber ?? currentNumber
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let previewNumber, directory.readableIndices.indices.contains(previewNumber - 1) {
                    Text(directory.rows[directory.readableIndices[previewNumber - 1]].title)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Text("\(previewNumber)/\(count)")
                } else {
                    Text("第 \(currentNumber) 章 / 共 \(count) 章")
                    Spacer(minLength: 0)
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            if count > 1 {
                Slider(value: Binding(
                    get: { Double(max(number, 1)) },
                    set: { previewNumber = Int($0.rounded()) }
                ), in: 1...Double(count), step: 1) { editing in
                    if !editing, let previewNumber {
                        self.previewNumber = nil
                        select(previewNumber)
                    }
                }
                .tint(ReadingTheme.accent)
                .accessibilityLabel("章节跳转")
                .accessibilityValue("第 \(number) 章，共 \(count) 章")
                .accessibilityIdentifier("reader.chapterSlider")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: select(currentNumber + 1)
                    case .decrement: select(currentNumber - 1)
                    @unknown default: break
                    }
                }
            } else {
                ProgressView(value: progress).tint(ReadingTheme.accent)
            }
        }
    }

    private func select(_ number: Int) {
        guard directory.readableIndices.indices.contains(number - 1) else { return }
        onSelect(directory.readableIndices[number - 1])
    }
}

struct ReaderTableOfContents: View {
    let directory: ReaderChapterDirectory
    let currentIndex: Int
    let bookTitle: String
    let bookURL: String
    let sourceID: String?
    let cache: ChapterContentCache
    @Binding var descending: Bool
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        ReadingNavigationStack {
            ScrollViewReader { proxy in
                let rows = directory.rows(matching: search, descending: descending)
                List {
                    Section {
                        ForEach(rows) { row in
                            chapterRow(row).id(row.id)
                        }
                    } header: {
                        HStack {
                            Text(bookTitle).lineLimit(1)
                            Spacer()
                            Text("共 \(directory.readableIndices.count) 章")
                        }
                        .textCase(nil)
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if rows.isEmpty && !search.isEmpty { ReadingUnavailableView.search(text: search) }
                }
                .onAppear {
                    DispatchQueue.main.async { proxy.scrollTo(currentIndex, anchor: .center) }
                }
                .onChange(of: descending) { _ in
                    if rows.contains(where: { $0.id == currentIndex }) { proxy.scrollTo(currentIndex, anchor: .center) }
                }
                .onChange(of: search) { query in
                    if query.isEmpty { proxy.scrollTo(currentIndex, anchor: .center) }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            if search.isEmpty { proxy.scrollTo(currentIndex, anchor: .center) }
                            else { search = "" }
                        } label: { Image(systemName: "scope") }
                        .accessibilityLabel("定位当前章节")
                        Button(descending ? "正序" : "倒序") { descending.toggle() }
                    }
                }
            }
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索章节")
        }
    }

    @ViewBuilder private func chapterRow(_ row: ReaderChapterDirectory.Row) -> some View {
        if let number = row.number {
            let current = row.id == currentIndex
            Button { onSelect(row.id) } label: {
                HStack(spacing: 12) {
                    Text("\(number)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(current ? ReadingTheme.accent : .secondary)
                        .frame(minWidth: 28, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title).lineLimit(2)
                        if current {
                            Text("正在阅读")
                                .font(.caption)
                                .foregroundStyle(ReadingTheme.accent)
                        }
                    }
                    Spacer(minLength: 0)
                    if let sourceID {
                        ChapterAvailabilityIcon(bookURL: bookURL, chapterURL: row.chapterURL, sourceID: sourceID, cache: cache)
                    }
                }
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(current ? .isSelected : [])
            .accessibilityIdentifier("reader.toc.\(row.id)")
            .listRowBackground(current ? ReadingTheme.accent.opacity(0.08) : Color.clear)
        } else {
            Label(row.title, systemImage: "books.vertical")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }
    }
}

struct ChapterAvailabilityIcon: View {
    let bookURL: String
    let chapterURL: String
    let sourceID: String
    var cache: ChapterContentCache = .live()
    @State private var isCached: Bool?

    var body: some View {
        ZStack {
            if isCached == false {
                Image(systemName: "icloud")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("未下载")
            }
        }
        .frame(width: 24)
        .task(id: [bookURL, chapterURL, sourceID]) {
            isCached = nil
            let changes = await cache.availability(bookURL: bookURL, chapterURL: chapterURL, sourceID: sourceID)
            for await cached in changes {
                guard !Task.isCancelled else { return }
                isCached = cached
            }
        }
    }
}

struct ReaderChapterLoadingOverlay: View {
    let title: String
    let foreground: Color
    let background: Color
    @State private var showsIndicator = false

    var body: some View {
        ZStack {
            if showsIndicator {
                HStack(spacing: 12) {
                    ProgressView().tint(foreground)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("正在打开本章").font(.subheadline.weight(.semibold))
                        Text(title).font(.caption).lineLimit(1)
                    }
                }
                .foregroundStyle(foreground)
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(background.opacity(0.82))
                        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(foreground.opacity(0.14))
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("reader.chapterLoading")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .task {
            do { try await Task.sleep(nanoseconds: 180_000_000) } catch { return }
            showsIndicator = true
        }
    }
}

struct ReaderPageTurnRequest: Equatable {
    let id = UUID()
    let direction: Int
}

struct ReaderVolumeKeyMonitor: UIViewRepresentable {
    let isEnabled: Bool
    let onPageTurn: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPageTurn: onPageTurn) }

    func makeUIView(context: Context) -> UIView {
        let host = UIView(frame: CGRect(x: -1000, y: -1000, width: 100, height: 40))
        host.alpha = 0.01
        host.isUserInteractionEnabled = false
        host.clipsToBounds = true
        context.coordinator.attach(to: host)
        context.coordinator.setEnabled(isEnabled)
        return host
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onPageTurn = onPageTurn
        context.coordinator.setEnabled(isEnabled)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onPageTurn: (Int) -> Void
        private weak var hostView: UIView?
        private var volumeView: MPVolumeView?
        private var volumeObservation: NSKeyValueObservation?
        private var resignObserver: NSObjectProtocol?
        private var activeObserver: NSObjectProtocol?
        private var isActive = false
        private var isEnabled = false
        private var baselineVolume: Float = 0.5
        private var originalVolume: Float?
        private var ignoringUntil: CFTimeInterval = 0

        init(onPageTurn: @escaping (Int) -> Void) {
            self.onPageTurn = onPageTurn
            super.init()
            resignObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.stop(restoreOriginalVolume: true) }
            }
            activeObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isEnabled else { return }
                    self.start()
                }
            }
        }

        func teardown() {
            stop(restoreOriginalVolume: true)
            if let resignObserver {
                NotificationCenter.default.removeObserver(resignObserver)
                self.resignObserver = nil
            }
            if let activeObserver {
                NotificationCenter.default.removeObserver(activeObserver)
                self.activeObserver = nil
            }
        }

        func attach(to host: UIView) {
            hostView = host
        }

        func setEnabled(_ enabled: Bool) {
            isEnabled = enabled
            if enabled {
                if !isActive { start() }
            } else {
                if isActive { stop(restoreOriginalVolume: true) }
            }
        }

        private func start() {
            guard !isActive else { return }
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.ambient, options: [.mixWithOthers])
            try? session.setActive(true)

            if volumeView == nil, let hostView {
                let mpView = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
                mpView.showsVolumeSlider = true
                hostView.addSubview(mpView)
                volumeView = mpView
            }

            let current = session.outputVolume
            originalVolume = current
            if current <= 0.06 {
                baselineVolume = 0.125
                setSystemVolume(baselineVolume, ignoreDuration: 0.4)
            } else if current >= 0.94 {
                baselineVolume = 0.875
                setSystemVolume(baselineVolume, ignoreDuration: 0.4)
            } else {
                baselineVolume = current
                ignoringUntil = CACurrentMediaTime() + 0.15
            }

            isActive = true
            volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
                guard let newVolume = change.newValue else { return }
                Task { @MainActor [weak self] in
                    self?.handleVolumeChange(newVolume)
                }
            }
        }

        func stop(restoreOriginalVolume: Bool) {
            volumeObservation?.invalidate()
            volumeObservation = nil
            if restoreOriginalVolume, let originalVolume, abs(originalVolume - baselineVolume) > 0.01 {
                setSystemVolume(originalVolume, ignoreDuration: 0.3)
            }
            originalVolume = nil
            volumeView?.removeFromSuperview()
            volumeView = nil
            isActive = false
        }

        private func handleVolumeChange(_ newVolume: Float) {
            guard isActive, CACurrentMediaTime() >= ignoringUntil else { return }
            let delta = newVolume - baselineVolume
            guard abs(delta) >= 0.005 else { return }
            // 音量减 -> 下一页 (1)，音量加 -> 上一页 (-1)
            let direction = delta < 0 ? 1 : -1
            setSystemVolume(baselineVolume, ignoreDuration: 0.25)
            onPageTurn(direction)
        }

        private func setSystemVolume(_ value: Float, ignoreDuration: CFTimeInterval) {
            ignoringUntil = CACurrentMediaTime() + ignoreDuration
            let target = min(max(value, 0.0), 1.0)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000)
                guard let slider = self?.volumeSlider() else { return }
                slider.setValue(target, animated: false)
                slider.sendActions(for: .touchUpInside)
            }
        }

        private func volumeSlider() -> UISlider? {
            volumeView?.subviews.compactMap { $0 as? UISlider }.first
        }
    }
}
