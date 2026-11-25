@preconcurrency import WebKit
import SwiftUI
import UIKit

struct SourceLoginView: View {
    let source: BookSource
    @State private var reloadID = UUID()
    @State private var status = "打开登录页后，Cookie 会自动同步给搜索与阅读请求。"
    @State private var isChecking = false

    var body: some View {
        Group {
            if usesCustomFormLogin {
                SourceCustomLoginView(source: source)
            } else {
                webLoginBody
            }
        }
        .navigationTitle("登录 · \(source.bookSourceName)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var webLoginBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill").foregroundStyle(ReadingTheme.accent)
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                if isChecking { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color(uiColor: .secondarySystemBackground))

            if let request = loginRequest {
                SourceLoginWebView(
                    request: request,
                    sourceURL: source.bookSourceUrl,
                    sourceID: source.id,
                    loginCheckJavaScript: source.loginCheckJs,
                    reloadID: reloadID,
                    status: $status,
                    isChecking: $isChecking
                )
            } else {
                ReadingUnavailableView("登录地址无效", systemImage: "link.badge.plus", description: Text(source.loginUrl ?? "书源没有配置登录地址"))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("重新载入", systemImage: "arrow.clockwise") { reloadID = UUID() }
            }
        }
    }

    private var usesCustomFormLogin: Bool {
        if let ui = source.loginUi?.trimmingCharacters(in: .whitespacesAndNewlines), !ui.isEmpty {
            return true
        }
        guard let raw = source.loginUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return false
        }
        return !Self.isDirectWebURL(raw)
    }

    private static func isDirectWebURL(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("about:") {
            return !value.contains("\n")
        }
        if value.hasPrefix("/") && !value.contains("\n") && !value.contains(";") && !value.contains("(") {
            return true
        }
        return false
    }

    private var loginRequest: URLRequest? {
        guard let value = source.loginUrl,
              let prepared = try? LegadoURLBuilder().prepare(
                value,
                baseURL: URL(string: source.bookSourceUrl),
                defaultHeaders: sourceHeaders
              ) else { return nil }
        return prepared.urlRequest(handleCookies: source.enabledCookieJar ?? true)
    }

    private var sourceHeaders: [String: String] {
        guard let value = source.header,
              let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object.mapValues { String(describing: $0) }
    }
}

private struct SourceLoginUIRow: Decodable, Identifiable {
    struct Style: Decodable {
        var layout_flexGrow: Double?
        var layout_flexBasisPercent: Double?
        var layout_wrapBefore: Bool?
    }

    var id: String { "\(type)::\(name)::\(action ?? "")" }
    var name: String
    var type: String
    var action: String?
    var viewName: String?
    var chars: [String?]?
    var `default`: String?
    var style: Style?
}

private enum SourceLoginSectionItem: Identifiable {
    case field(SourceLoginUIRow)
    case buttonGroup([SourceLoginUIRow])

    var id: String {
        switch self {
        case .field(let row): return "field::\(row.id)"
        case .buttonGroup(let rows): return "buttons::" + rows.map(\.id).joined(separator: "|")
        }
    }
}

private struct SourceCustomLoginView: View {
    let source: BookSource
    @ObservedObject private var uiBridge = AppJavaScriptUIBridge.shared
    @State private var rows: [SourceLoginUIRow] = []
    @State private var values: [String: String] = [:]
    @State private var revealedPasswords: Set<String> = []
    @State private var isRunning = false
    @State private var runningActionLabel: String?
    @State private var errorMessage: String?
    @State private var localMessages: [String] = []
    @State private var showsHistory = false

    private var groupedItems: [SourceLoginSectionItem] {
        var items: [SourceLoginSectionItem] = []
        var pendingButtons: [SourceLoginUIRow] = []
        func flushButtons() {
            guard !pendingButtons.isEmpty else { return }
            items.append(.buttonGroup(pendingButtons))
            pendingButtons.removeAll()
        }
        for row in rows {
            if row.type.lowercased() == "button" {
                let basis = row.style?.layout_flexBasisPercent ?? 1.0
                if row.style?.layout_wrapBefore == true {
                    flushButtons()
                }
                if basis > 0.55 {
                    flushButtons()
                    items.append(.buttonGroup([row]))
                } else {
                    pendingButtons.append(row)
                    if pendingButtons.count == 2 {
                        flushButtons()
                    }
                }
            } else {
                flushButtons()
                items.append(.field(row))
            }
        }
        flushButtons()
        return items
    }

    var body: some View {
        Form {
            if isRunning || !localMessages.isEmpty || errorMessage != nil {
                Section("执行反馈") {
                    if isRunning {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(runningActionLabel.map { "正在执行：\($0)…" } ?? "正在执行脚本…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                    if let latest = localMessages.last {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(latest)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 14) {
                                Button("复制提示") {
                                    UIPasteboard.general.string = latest
                                }
                                .font(.caption)
                                .buttonStyle(.borderless)
                                Button("清空") {
                                    localMessages.removeAll()
                                    errorMessage = nil
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }

            if rows.isEmpty {
                Section {
                    Text("此书源使用脚本登录，未定义自定义表单项。点击右上角「登录」执行登录脚本。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("登录与书源操作") {
                    ForEach(groupedItems) { item in
                        switch item {
                        case .field(let row):
                            fieldView(for: row)
                        case .buttonGroup(let buttons):
                            HStack(spacing: 10) {
                                ForEach(buttons) { button in
                                    Button {
                                        runAction(button.action, title: label(for: button))
                                    } label: {
                                        Text(label(for: button))
                                            .font(.subheadline.weight(.medium))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 9)
                                            .padding(.horizontal, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(ReadingTheme.accent.opacity(0.12))
                                            )
                                            .foregroundStyle(ReadingTheme.accent)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isRunning)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !uiBridge.toastHistory.isEmpty {
                    Button("记录") { showsHistory = true }
                }
                Button(isRunning ? "执行中" : "登录") {
                    saveAndLogin()
                }
                .disabled(isRunning)
            }
        }
        .sheet(isPresented: $showsHistory) {
            NavigationView {
                List(uiBridge.toastHistory.reversed()) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(item.text)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                }
                .navigationTitle("书源提示记录")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { showsHistory = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("清空") { uiBridge.clearHistory() }
                    }
                }
            }
        }
        .task { loadRows() }
        .onChange(of: uiBridge.latestToast?.id) { _ in
            if let text = uiBridge.latestToast?.text.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                localMessages.append(text)
                if localMessages.count > 20 { localMessages.removeFirst(localMessages.count - 20) }
            }
        }
    }

    @ViewBuilder
    private func fieldView(for row: SourceLoginUIRow) -> some View {
        switch row.type.lowercased() {
        case "password":
            VStack(alignment: .leading, spacing: 4) {
                Text(label(for: row)).font(.caption).foregroundStyle(.secondary)
                HStack {
                    if revealedPasswords.contains(row.name) {
                        TextField(label(for: row), text: binding(for: row))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField(label(for: row), text: binding(for: row))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Button {
                        if revealedPasswords.contains(row.name) {
                            revealedPasswords.remove(row.name)
                        } else {
                            revealedPasswords.insert(row.name)
                        }
                    } label: {
                        Image(systemName: revealedPasswords.contains(row.name) ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
        case "select":
            Picker(label(for: row), selection: binding(for: row)) {
                ForEach(options(for: row), id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .onChange(of: values[row.name]) { _ in
                if let action = row.action, !action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    runAction(action, title: label(for: row))
                }
            }
        case "toggle":
            VStack(alignment: .leading, spacing: 6) {
                Text(label(for: row)).font(.caption).foregroundStyle(.secondary)
                Picker(label(for: row), selection: binding(for: row)) {
                    ForEach(options(for: row), id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: values[row.name]) { _ in
                    if let action = row.action, !action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        runAction(action, title: label(for: row))
                    }
                }
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text(label(for: row)).font(.caption).foregroundStyle(.secondary)
                TextField("请输入\(label(for: row))", text: binding(for: row))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

    private func loadRows() {
        values = decodeLoginInfo()
        do {
            let json = try renderedLoginUI()
            let decoded: [SourceLoginUIRow]
            if let strict = try? JSONDecoder().decode([SourceLoginUIRow].self, from: Data(json.utf8)) {
                decoded = strict
            } else {
                let normalized = try LegadoURLBuilder.decodeLenientJSON(json)
                let data = try JSONEncoder().encode(normalized)
                decoded = try JSONDecoder().decode([SourceLoginUIRow].self, from: data)
            }
            rows = decoded
            for row in rows where row.type.lowercased() != "button" && values[row.name] == nil {
                values[row.name] = row.default ?? (row.type.lowercased() == "select" || row.type.lowercased() == "toggle" ? options(for: row).first : "") ?? ""
            }
        } catch {
            errorMessage = "解析登录界面失败：\(error.localizedDescription)"
        }
    }

    private func renderedLoginUI() throws -> String {
        guard var raw = source.loginUi?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return "[]"
        }
        let script: String?
        if raw.hasPrefix("@js:") {
            script = String(raw.dropFirst(4))
        } else if raw.hasPrefix("<js>"), raw.hasSuffix("</js>") {
            script = String(raw.dropFirst(4).dropLast(5))
        } else {
            script = nil
        }
        if let script {
            let result = try JavaScriptRuleEvaluator().evaluate(
                script: script,
                result: .object(values.mapValues(JSONValue.string)),
                executionContext: .init(source: source)
            )
            raw = result.value.stringValue
        }
        return raw
    }

    private func decodeLoginInfo() -> [String: String] {
        let raw = BookSourceRuntimeStore.shared.get(sourceID: source.bookSourceUrl, key: "loginInfo")
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object.mapValues { value in
            if value is NSNull { return "" }
            return String(describing: value)
        }
    }

    private func persistLoginInfo() {
        var merged = decodeLoginInfo()
        for (k, v) in values { merged[k] = v }
        if let data = try? JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys]) {
            let raw = String(decoding: data, as: UTF8.self)
            BookSourceRuntimeStore.shared.put(sourceID: source.bookSourceUrl, key: "loginInfo", value: raw)
        }
    }

    private func binding(for row: SourceLoginUIRow) -> Binding<String> {
        Binding(
            get: { values[row.name] ?? row.default ?? "" },
            set: { values[row.name] = $0 }
        )
    }

    private func options(for row: SourceLoginUIRow) -> [String] {
        let opts = row.chars?.compactMap { $0 } ?? []
        return opts.isEmpty ? [row.default ?? ""] : opts
    }

    private func label(for row: SourceLoginUIRow) -> String {
        if let value = row.viewName?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            if value.count >= 2, value.first == "'", value.last == "'" {
                return String(value.dropFirst().dropLast())
            }
            return value
        }
        return row.name.trimmingCharacters(in: .whitespaces)
    }

    private func runAction(_ action: String?, title: String) {
        guard let action = action?.trimmingCharacters(in: .whitespacesAndNewlines), !action.isEmpty else { return }
        persistLoginInfo()
        isRunning = true
        runningActionLabel = title
        errorMessage = nil
        let source = source
        let currentValues = decodeLoginInfo()
        let script = "\(source.loginUrl ?? "")\n\(action)"
        Task { @MainActor in
            defer {
                isRunning = false
                runningActionLabel = nil
            }
            do {
                _ = try await JavaScriptRuleEvaluator().evaluateAsync(
                    script: script,
                    result: .object(currentValues.mapValues(JSONValue.string)),
                    executionContext: .init(source: source)
                )
                let refreshed = decodeLoginInfo()
                for (k, v) in refreshed { values[k] = v }
                if source.loginUi?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@js:") == true
                    || source.loginUi?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<js>") == true {
                    loadRows()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func saveAndLogin() {
        persistLoginInfo()
        let loginScript = source.loginUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !loginScript.isEmpty else {
            localMessages.append("已保存登录配置")
            return
        }
        runAction("if (typeof login === 'function') login(true);", title: "登录")
    }
}

struct JavaScriptToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let long: Bool
    let timestamp = Date()
}

final class AppJavaScriptUIBridge: ObservableObject, JavaScriptUIBridging, @unchecked Sendable {
    static let shared = AppJavaScriptUIBridge()
    static let exploreRefreshNotification = Notification.Name("LegadoJavaScriptRefreshExplore")

    @Published var latestToast: JavaScriptToastMessage?
    @Published var toastHistory: [JavaScriptToastMessage] = []

    func showToast(_ message: String, long: Bool) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task { @MainActor in
            let entry = JavaScriptToastMessage(text: trimmed, long: long)
            self.latestToast = entry
            self.toastHistory.append(entry)
            if self.toastHistory.count > 50 {
                self.toastHistory.removeFirst(self.toastHistory.count - 50)
            }
        }
    }

    @MainActor
    func clearHistory() {
        toastHistory.removeAll()
        latestToast = nil
    }

    func refreshExplore(sourceID: String) {
        Task { @MainActor in
            NotificationCenter.default.post(name: Self.exploreRefreshNotification, object: sourceID)
        }
    }

    func startBrowser(url: String, title: String, awaitResult: Bool, sourceID: String) -> JavaScriptBrowserResult {
        if Thread.isMainThread {
            if !awaitResult {
                Task { @MainActor in
                    self.presentBrowser(url: url, title: title, sourceID: sourceID, onComplete: nil)
                }
            }
            return JavaScriptBrowserResult(url: url, body: "", statusCode: 0, headers: [:])
        }
        if !awaitResult {
            Task { @MainActor in
                self.presentBrowser(url: url, title: title, sourceID: sourceID, onComplete: nil)
            }
            return JavaScriptBrowserResult(url: url, body: "", statusCode: 200, headers: [:])
        }
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        nonisolated(unsafe) var output = JavaScriptBrowserResult(url: url, body: "", statusCode: 200, headers: [:])
        nonisolated(unsafe) var signaled = false
        let finish: @Sendable (JavaScriptBrowserResult) -> Void = { result in
            lock.lock()
            defer { lock.unlock() }
            guard !signaled else { return }
            signaled = true
            output = result
            semaphore.signal()
        }
        Task { @MainActor in
            self.presentBrowser(url: url, title: title, sourceID: sourceID, onComplete: finish)
        }
        _ = semaphore.wait(timeout: .now() + 600)
        lock.lock()
        let finalResult = output
        lock.unlock()
        return finalResult
    }

    @MainActor
    private func presentBrowser(
        url: String,
        title: String,
        sourceID: String,
        onComplete: (@Sendable (JavaScriptBrowserResult) -> Void)?
    ) {
        guard let presenter = Self.topViewController() else {
            onComplete?(JavaScriptBrowserResult(url: url, body: "", statusCode: 0, headers: [:]))
            return
        }
        let fallbackBaseURL = Self.preferredBaseURL(for: sourceID)
        let controller = JSInteractiveBrowserViewController(
            rawURL: url,
            pageTitle: title.isEmpty ? "书源浏览器" : title,
            sourceID: sourceID,
            fallbackBaseURL: fallbackBaseURL,
            onComplete: onComplete
        )
        let nav = UINavigationController(rootViewController: controller)
        nav.modalPresentationStyle = .pageSheet
        nav.presentationController?.delegate = controller
        presenter.present(nav, animated: true)
    }

    private static func preferredBaseURL(for sourceID: String) -> URL? {
        guard !sourceID.isEmpty else { return nil }
        let rawVar = BookSourceRuntimeStore.shared.get(sourceID: sourceID, key: "__sourceVariable")
        if let data = rawVar.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let server = json["server"] as? String,
           let url = URL(string: server),
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            return url
        }
        if let url = URL(string: sourceID), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            return url
        }
        return nil
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

@MainActor
private final class JSInteractiveBrowserViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, UIAdaptivePresentationControllerDelegate {
    private let rawURL: String
    private let pageTitle: String
    private let sourceID: String
    private let fallbackBaseURL: URL?
    private let onComplete: (@Sendable (JavaScriptBrowserResult) -> Void)?

    private var webView: WKWebView!
    private var lastStatusCode = 200
    private var lastHeaders: [String: String] = [:]
    private var hasCompleted = false

    init(
        rawURL: String,
        pageTitle: String,
        sourceID: String,
        fallbackBaseURL: URL?,
        onComplete: (@Sendable (JavaScriptBrowserResult) -> Void)?
    ) {
        self.rawURL = rawURL
        self.pageTitle = pageTitle
        self.sourceID = sourceID
        self.fallbackBaseURL = fallbackBaseURL
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = pageTitle
        view.backgroundColor = UIColor(ReadingTheme.canvas)

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "完成",
            style: .done,
            target: self,
            action: #selector(finishAndDismiss)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(reloadPage)
        )

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        installCookiesAndLoad()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            collectAndComplete()
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        collectAndComplete()
    }

    @objc private func reloadPage() {
        if rawURL.lowercased().hasPrefix("data:") {
            loadTargetURL()
        } else {
            webView.reload()
        }
    }

    @objc private func finishAndDismiss() {
        collectAndComplete { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    private func installCookiesAndLoad() {
        let targetURL = URL(string: rawURL) ?? fallbackBaseURL
        let cookies = targetURL.flatMap { HTTPCookieStorage.shared.cookies(for: $0) } ?? []
        guard !cookies.isEmpty else {
            loadTargetURL()
            return
        }
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) { [weak self] in
            Task { @MainActor [weak self] in
                self?.loadTargetURL()
            }
        }
    }

    private func loadTargetURL() {
        if let html = Self.decodeDataHTML(rawURL) {
            webView.loadHTMLString(html, baseURL: fallbackBaseURL)
        } else if let url = URL(string: rawURL) {
            webView.load(URLRequest(url: url))
        }
    }

    private static func decodeDataHTML(_ raw: String) -> String? {
        guard raw.lowercased().hasPrefix("data:"),
              let comma = raw.firstIndex(of: ",") else { return nil }
        let meta = raw[raw.index(raw.startIndex, offsetBy: 5)..<comma].lowercased()
        let payload = String(raw[raw.index(after: comma)...])
        if meta.contains(";base64") {
            let cleaned = payload.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
            guard let data = Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        return payload.removingPercentEncoding ?? payload
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        if let http = navigationResponse.response as? HTTPURLResponse {
            lastStatusCode = http.statusCode
            lastHeaders = http.allHeaderFields.reduce(into: [:]) { acc, entry in
                acc[String(describing: entry.key)] = String(describing: entry.value)
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        syncCookies(from: webView)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor () -> Void
    ) {
        let alert = UIAlertController(title: pageTitle, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor (Bool) -> Void
    ) {
        let alert = UIAlertController(title: pageTitle, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    private func syncCookies(from webView: WKWebView, completion: (@MainActor @Sendable () -> Void)? = nil) {
        let sourceID = self.sourceID
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            var grouped: [String: [HTTPCookie]] = [:]
            for cookie in cookies {
                HTTPCookieStorage.shared.setCookie(cookie)
                let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                guard !domain.isEmpty else { continue }
                grouped[domain, default: []].append(cookie)
            }
            for (domain, domainCookies) in grouped {
                let header = HTTPCookie.requestHeaderFields(with: domainCookies)["Cookie"] ?? ""
                guard !header.isEmpty else { continue }
                LegadoCookieStore.shared.setCookie(header, for: "https://\(domain)")
                if let url = URL(string: "https://\(domain)") {
                    Task {
                        await SourceNetworkPolicy.shared.setCookieHeader(header, sourceID: sourceID, url: url)
                    }
                }
            }
            if let completion {
                Task { @MainActor in completion() }
            }
        }
    }

    private func collectAndComplete(afterSync: (@MainActor @Sendable () -> Void)? = nil) {
        guard !hasCompleted else {
            afterSync?()
            return
        }
        hasCompleted = true
        let currentURL = webView?.url?.absoluteString ?? rawURL
        let statusCode = lastStatusCode
        let headers = lastHeaders
        guard let webView else {
            onComplete?(JavaScriptBrowserResult(url: currentURL, body: "", statusCode: statusCode, headers: headers))
            afterSync?()
            return
        }
        webView.evaluateJavaScript("document.documentElement ? document.documentElement.outerHTML : ''") { [weak self] value, _ in
            let html = value as? String ?? ""
            guard let self else { return }
            self.syncCookies(from: webView) {
                self.onComplete?(JavaScriptBrowserResult(url: currentURL, body: html, statusCode: statusCode, headers: headers))
                afterSync?()
            }
        }
    }
}

private struct SourceLoginWebView: UIViewRepresentable {
    let request: URLRequest
    let sourceURL: String
    let sourceID: String
    let loginCheckJavaScript: String?
    let reloadID: UUID
    @Binding var status: String
    @Binding var isChecking: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(ReadingTheme.canvas)
        webView.scrollView.backgroundColor = UIColor(ReadingTheme.canvas)
        webView.navigationDelegate = context.coordinator
        context.coordinator.installExistingCookies(in: webView) { webView.load(request) }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.lastReloadID != reloadID else { return }
        context.coordinator.lastReloadID = reloadID
        webView.reload()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: SourceLoginWebView
        var lastReloadID: UUID

        init(parent: SourceLoginWebView) {
            self.parent = parent
            lastReloadID = parent.reloadID
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
            parent.status = "正在打开登录页…"
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            syncCookies(from: webView)
            guard let script = parent.loginCheckJavaScript?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !script.isEmpty else {
                parent.status = "页面已载入；登录后 Cookie 会自动同步。"
                return
            }
            parent.isChecking = true
            webView.evaluateJavaScript(script) { [weak self] value, error in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.parent.isChecking = false
                    if let error {
                        self.parent.status = "登录检测脚本失败：\(error.localizedDescription)"
                    } else {
                        self.parent.status = Self.truthy(value) ? "书源登录检测已通过" : "页面已载入，尚未检测到登录状态"
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
            parent.status = "登录页加载失败：\(error.localizedDescription)"
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
            parent.status = "登录页加载失败：\(error.localizedDescription)"
        }

        func installExistingCookies(in webView: WKWebView, completion: @escaping () -> Void) {
            guard let url = URL(string: parent.sourceURL) else {
                completion()
                return
            }
            let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
            guard !cookies.isEmpty else {
                completion()
                return
            }
            let group = DispatchGroup()
            for cookie in cookies {
                group.enter()
                webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { group.leave() }
            }
            group.notify(queue: .main, execute: completion)
        }

        private func syncCookies(from webView: WKWebView) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                cookies.forEach(HTTPCookieStorage.shared.setCookie)
                guard let url = URL(string: self.parent.sourceURL) else { return }
                let matching = HTTPCookieStorage.shared.cookies(for: url) ?? []
                let header = HTTPCookie.requestHeaderFields(with: matching)["Cookie"] ?? ""
                Task {
                    await SourceNetworkPolicy.shared.setCookieHeader(
                        header,
                        sourceID: self.parent.sourceID,
                        url: url
                    )
                }
            }
        }

        private static func truthy(_ value: Any?) -> Bool {
            if let value = value as? Bool { return value }
            if let value = value as? NSNumber { return value.boolValue }
            guard let text = value.map(String.init(describing:))?.lowercased() else { return false }
            return !text.isEmpty && !["false", "0", "null", "undefined"].contains(text)
        }
    }
}

final class WKSourceWebViewExecutor: NSObject, SourceWebViewRequestExecuting, @unchecked Sendable {
    @MainActor
    func execute(_ prepared: PreparedRequest, source: BookSource, timeout: TimeInterval) async throws -> HTTPResponse {
        let override = ApplicationSettingsStore.shared.settings.timeoutSeconds
        return try await BackgroundWebViewRequest(prepared: prepared, source: source, timeout: override > 0 ? Double(override) : timeout).run()
    }
}

@MainActor
private final class BackgroundWebViewRequest: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private let prepared: PreparedRequest
    private let source: BookSource
    private let timeout: TimeInterval
    private let webView: WKWebView
    private var continuation: CheckedContinuation<HTTPResponse, Error>?
    private var responseStatus = 200
    private var responseHeaders: [String: String] = [:]
    private var completed = false
    private var timeoutTask: Task<Void, Never>?
    private var evaluationTask: Task<Void, Never>?
    private var sourcePattern: NSRegularExpression?
    private var collectingResponse = false

    init(prepared: PreparedRequest, source: BookSource, timeout: TimeInterval) {
        self.prepared = prepared
        self.source = source
        self.timeout = timeout
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = prepared.headers.first { $0.key.caseInsensitiveCompare("User-Agent") == .orderedSame }?.value
        super.init()
        webView.navigationDelegate = self
        if prepared.sourceRegex != nil {
            configuration.userContentController.addUserScript(.init(source: Self.resourceObserver,
                injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
    }

    func run() async throws -> HTTPResponse {
        try Task.checkCancellation()
        if let pattern = prepared.sourceRegex { sourcePattern = try NSRegularExpression(pattern: pattern) }
        if sourcePattern != nil { webView.configuration.userContentController.add(self, name: "legadoResource") }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                installRequestCookies { [weak self] in self?.startLoading() }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }

    private func startLoading() {
        guard !completed else { return }
        timeoutTask = Task { [weak self] in
            let seconds = min(max(self?.timeout ?? 30, 1), 300)
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let error: Error
            if let pattern = prepared.sourceRegex {
                error = RuleEngineError.invalidInput(rule: pattern, expected: "WebView 在超时前未找到匹配的可观察资源地址")
            } else { error = URLError(.timedOut) }
            finish(.failure(error))
        }
        if let html = prepared.webViewHTML {
            webView.loadHTMLString(html, baseURL: prepared.url)
        } else {
            webView.load(prepared.urlRequest(timeout: timeout, handleCookies: true))
        }
    }

    private func installRequestCookies(completion: @escaping () -> Void) {
        guard let header = prepared.headers.first(where: { $0.key.caseInsensitiveCompare("Cookie") == .orderedSame })?.value,
              let host = prepared.url.host, !header.isEmpty else {
            completion()
            return
        }
        let cookies = header.split(separator: ";").compactMap { part -> HTTPCookie? in
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return nil }
            return HTTPCookie(properties: [
                .name: pair[0].trimmingCharacters(in: .whitespaces),
                .value: pair[1],
                .domain: host,
                .path: "/",
                .secure: prepared.url.scheme == "https" ? "TRUE" : "FALSE"
            ])
        }
        guard !cookies.isEmpty else { completion(); return }
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main, execute: completion)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        if let response = navigationResponse.response as? HTTPURLResponse {
            responseStatus = response.statusCode
            responseHeaders = response.allHeaderFields.reduce(into: [:]) { result, entry in
                result[String(describing: entry.key)] = String(describing: entry.value)
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        evaluationTask?.cancel()
        evaluationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let defaultDelay = prepared.webJavaScript == nil ? 900 : 0
                let delay = 100 + min(max(prepared.webViewDelayMilliseconds, defaultDelay), 300_000)
                try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
                guard !completed else { return }
                if sourcePattern != nil {
                    // Resource sniffing has priority over script output; the
                    // script may start a media/fetch request after load.
                    if let script = prepared.webJavaScript, !script.isEmpty {
                        _ = try await webView.evaluateJavaScript(script)
                    }
                    return
                }
                let script = prepared.webJavaScript.flatMap { $0.isEmpty ? nil : $0 }
                    ?? "document.documentElement.outerHTML"
                for attempt in 0...31 {
                    try Task.checkCancellation()
                    guard !completed else { return }
                    let value = try await webView.evaluateJavaScript(script)
                    if let value, !(value is NSNull) {
                        let body: String
                        if let string = value as? String { body = string }
                        else {
                            body = String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]), as: UTF8.self)
                        }
                        await deliver(body)
                        return
                    }
                    guard attempt < 31 else { throw URLError(.timedOut) }
                    try await Task.sleep(nanoseconds: UInt64(min(attempt + 1, 5) * 200) * 1_000_000)
                }
            } catch {
                guard !Task.isCancelled else { return }
                finish(.failure(error))
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let address = message.body as? String else { return }
        observeResource(address)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
        if prepared.webViewHTML == nil, let address = webView.url?.absoluteString { observeResource(address) }
    }

    private func observeResource(_ address: String) {
        guard !completed, !collectingResponse, let pattern = sourcePattern else { return }
        let range = NSRange(address.startIndex..., in: address)
        guard pattern.firstMatch(in: address, range: range)?.range == range else { return }
        collectingResponse = true
        Task { [weak self] in await self?.deliver(address) }
    }

    private func deliver(_ body: String) async {
        guard !completed else { return }
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        guard !completed else { return }
        let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"] ?? ""
        var headers = responseHeaders
        if source.enabledCookieJar == true, !cookieHeader.isEmpty {
            await SourceNetworkPolicy.shared.setCookieHeader(cookieHeader, sourceID: source.id, url: prepared.url)
            headers["Set-Cookie"] = cookieHeader
        }
        finish(.success(.init(data: Data(body.utf8), statusCode: responseStatus, headers: headers,
                              finalURL: webView.url ?? prepared.url, requestedCharset: "utf-8")))
    }

    // Public WK APIs do not expose every network request. Observe browser
    // resource timing, dispatched fetch/XHR, and media load events, including
    // frames. Native HLS segments, service-worker internals and DRM traffic
    // cannot be promised; a missing match fails explicitly at the deadline.
    private static let resourceObserver = #"""
    (() => {
        const send = value => {
            try { if (value) window.webkit.messageHandlers.legadoResource.postMessage(new URL(String(value), document.baseURI).href); } catch (_) {}
        };
        try {
            new PerformanceObserver(list => list.getEntries().forEach(entry => send(entry.name))).observe({type:'resource', buffered:true});
        } catch (_) {}
        const originalFetch = window.fetch;
        if (originalFetch) window.fetch = function(input, init) {
            const result = originalFetch.apply(this, arguments);
            send(typeof input === 'string' || input instanceof URL ? input : input.url);
            return result;
        };
        const open = XMLHttpRequest.prototype.open, transmit = XMLHttpRequest.prototype.send;
        const addresses = new WeakMap();
        XMLHttpRequest.prototype.open = function(method, url) { const result = open.apply(this, arguments); addresses.set(this, url); return result; };
        XMLHttpRequest.prototype.send = function() { const result = transmit.apply(this, arguments); send(addresses.get(this)); return result; };
        document.addEventListener('loadstart', event => {
            if (event.target instanceof HTMLMediaElement) send(event.target.currentSrc || event.target.src);
        }, true);
        window.addEventListener('load', () => performance.getEntriesByType('resource').forEach(entry => send(entry.name)));
    })();
    """#

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<HTTPResponse, Error>) {
        guard !completed else { return }
        completed = true
        timeoutTask?.cancel()
        evaluationTask?.cancel()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "legadoResource")
        webView.navigationDelegate = nil
        webView.stopLoading()
        continuation?.resume(with: result)
        continuation = nil
    }
}

private extension WKHTTPCookieStore {
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            getAllCookies { continuation.resume(returning: $0) }
        }
    }
}
