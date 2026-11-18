import AppKit
import AVFoundation
import UserNotifications
import WebKit
import UniformTypeIdentifiers

// MARK: - Configuration

enum Config {
    static let appName = "Vibe"
    static let homeURL = URL(string: "https://chat.mistral.ai/")!
    // Hosts that stay inside the app: the Vibe web app itself and the login
    // flow. Every other link — including mistral.ai subdomains such as
    // docs.mistral.ai, and github.com — opens in the default browser.
    static let appHosts: Set<String> = [
        "chat.mistral.ai",
        "auth.mistral.ai",
        // Auth providers used by Mistral's login flow:
        "accounts.google.com",
        "appleid.apple.com",
        "login.microsoftonline.com"
    ]
}

// MARK: - Web View Controller

final class WebViewController: NSViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {

    private(set) var webView: WKWebView!
    private var recentDownloads: [URL] = []

    override func loadView() {
        let config = WKWebViewConfiguration()
        // Persistent store => cookies / localStorage survive relaunch, so the
        // user stays logged in.
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(macOS 11.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        // Skip the Safe Browsing network lookup WebKit does on each navigation —
        // we only ever load Mistral, and it adds latency to every page change.
        config.preferences.isFraudulentWebsiteWarningEnabled = false

        // A concrete frame here sets the view's fitting size; otherwise the
        // window (sized from its contentViewController) collapses to 1×1.
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 760),
                            configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        self.view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.load(URLRequest(url: Config.homeURL))
    }

    func reload() { webView.reload() }
    func goHome() { webView.load(URLRequest(url: Config.homeURL)) }
    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }
    func zoomIn() { webView.pageZoom += 0.1 }
    func zoomOut() { webView.pageZoom = max(0.5, webView.pageZoom - 0.1) }
    func zoomReset() { webView.pageZoom = 1.0 }

    /// Show the most recent downloads in Finder (menu item / ⌘J).
    /// Falls back to opening ~/Downloads when nothing was downloaded yet.
    func showDownloads() {
        if !recentDownloads.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(recentDownloads)
        } else if let downloads = FileManager.default.urls(for: .downloadsDirectory,
                                                           in: .userDomainMask).first {
            NSWorkspace.shared.open(downloads)
        }
    }

    // MARK: PATCH 4 — reliable microphone/camera permission

    /// WebKit has a known issue where getUserMedia() silently hangs without
    /// ever showing a prompt when this delegate method is missing. Granting at
    /// the web layer makes the regular macOS system prompt (TCC) appear
    /// reliably; the OS itself remains the real gatekeeper for mic/camera.
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        print("🎤 MEDIATOEGANG GEVRAAGD voor \(origin.host)")
        decisionHandler(.grant)
    }

    /// Pre-authorize the microphone at the macOS level (App-menu item), so the
    /// system prompt can be answered before using voice features.
    func requestMicAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            print("🎤 Microfoon al toegestaan")
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print(granted ? "🎤 Microfoon toegestaan" : "🎤 Microfoon geweigerd")
            }
        default:
            print("🎤 Eerder geweigerd — zet aan via Systeeminstellingen → Privacy & Beveiliging → Microfoon")
        }
    }

    // MARK: PATCH 5 — open page in browser / copy link

    func openInBrowser() {
        guard let url = webView.url,
              let scheme = url.scheme, scheme == "http" || scheme == "https" else { return }
        NSWorkspace.shared.open(url)
    }

    func copyPageLink() {
        guard let url = webView.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    // MARK: PATCH 6 — find in page (⌘F)
    // macOS has no public WKWebView find API (findString/WKFindConfiguration
    // are iOS-only) and window.find() is non-functional in WKWebView, so this
    // uses a self-contained JavaScript highlighter instead.

    private static let findScript = #"""
(function() {
    var query = window.__vibeQuery || "";
    if (!query) {
        if (window.__vibeCleanup) { window.__vibeCleanup(); }
        return 0;
    }
    if (window.__vibeLast === query && window.__vibeMarks && window.__vibeMarks.length) {
        window.__vibeIdx = (window.__vibeIdx + 1) % window.__vibeMarks.length;
        window.__vibeMarks[window.__vibeIdx].scrollIntoView({block: "center", behavior: "smooth"});
        return window.__vibeMarks.length;
    }
    if (window.__vibeCleanup) { window.__vibeCleanup(); }
    var re = new RegExp(query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "gi");
    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
        acceptNode: function(n) {
            if (!n.nodeValue || !n.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
            var p = n.parentNode;
            while (p && p !== document.body) {
                var t = p.nodeName;
                if (t === "SCRIPT" || t === "STYLE" || t === "NOSCRIPT" || t === "INPUT" || t === "TEXTAREA") return NodeFilter.FILTER_REJECT;
                p = p.parentNode;
            }
            return NodeFilter.FILTER_ACCEPT;
        }
    });
    var nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    var marks = [];
    nodes.forEach(function(node) {
        var remaining = node;
        var text = remaining.nodeValue;
        var match;
        while ((match = re.exec(text)) !== null) {
            var after = remaining.splitText(match.index);
            var rest = after.splitText(match[0].length);
            var mark = document.createElement("mark");
            mark.className = "__vibe_mark";
            mark.style.cssText = "background:#ffe066;color:#000;border-radius:2px;";
            mark.appendChild(document.createTextNode(after.nodeValue));
            after.parentNode.replaceChild(mark, after);
            marks.push(mark);
            remaining = rest;
            text = remaining.nodeValue;
            re.lastIndex = 0;
        }
    });
    window.__vibeMarks = marks;
    window.__vibeLast = query;
    window.__vibeIdx = marks.length ? 0 : -1;
    window.__vibeCleanup = function() {
        document.querySelectorAll("mark.__vibe_mark").forEach(function(mk) {
            var parent = mk.parentNode;
            if (!parent) return;
            while (mk.firstChild) parent.insertBefore(mk.firstChild, mk);
            parent.removeChild(mk);
            parent.normalize();
        });
        window.__vibeMarks = null;
        window.__vibeLast = null;
        window.__vibeCleanup = null;
    };
    if (marks.length) { marks[0].scrollIntoView({block: "center", behavior: "smooth"}); }
    return marks.length;
})()
"""#

    func findInPage() {
        let alert = NSAlert()
        alert.messageText = "Find in Page"
        alert.informativeText = "Enter a search term and click Find.\nPress ⌘F again (same term) to jump to the next match.\nLeave the field empty and click Find to clear all highlights."
        alert.addButton(withTitle: "Find")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let query = field.stringValue
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        webView.evaluateJavaScript("window.__vibeQuery = \"\(escaped)\"", completionHandler: nil)
        webView.evaluateJavaScript(Self.findScript) { result, error in
            if let error {
                print("🔍 Find error: \(error.localizedDescription)")
            } else if !query.isEmpty, let count = result as? Int, count == 0 {
                NSSound.beep()
            }
        }
    }

    private func isAppHost(_ url: URL) -> Bool {
        guard let host = url.host else { return true } // about:blank etc.
        // GitHub stays in-app only for the OAuth connect flow of Code Mode
        // (github.com/login, github.com/oauth); normal github.com links
        // (repositories, pull requests, …) open in the default browser.
        if host == "github.com" || host.hasSuffix(".github.com") {
            return url.path.hasPrefix("/login") || url.path.hasPrefix("/oauth")
        }
        return Config.appHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// PATCH: data:-URL's (canvas-exporten) bevatten het hele bestand base64-
    /// gecodeerd in de link. WebKit probeert ze weer te geven in plaats van te
    /// downloaden; hier worden ze handmatig gedecodeerd en opgeslagen.
    private static func saveDataURL(_ url: URL, to downloads: URL) -> URL? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let raw = comps.percentEncodedPath + (comps.percentEncodedQuery.map { "?" + $0 } ?? "")
        guard let comma = raw.firstIndex(of: ",") else { return nil }
        let meta = String(raw[raw.startIndex..<comma])
        let payload = String(raw[raw.index(after: comma)...])
        let parts = meta.split(separator: ";")
        let mime = parts.first.flatMap { $0.isEmpty ? nil : String($0) } ?? "application/octet-stream"
        let isBase64 = parts.dropFirst().contains { $0.lowercased() == "base64" }
        let data = isBase64
            ? Data(base64Encoded: payload)
            : payload.removingPercentEncoding?.data(using: .utf8)
        guard let data, !data.isEmpty else { return nil }
        let ext = UTType(mimeType: mime)?.preferredFilenameExtension ?? "bin"
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HHmmss"
        var dest = downloads.appendingPathComponent("Vibe-download \(df.string(from: Date())).\(ext)")
        var i = 1
        while FileManager.default.fileExists(atPath: dest.path) { i += 1; dest = downloads.appendingPathComponent("Vibe-download \(df.string(from: Date())) \(i).\(ext)") }
        do {
            try data.write(to: dest, options: .atomic)
            return dest
        } catch {
            print("❌ DATA-URL SCHRIJFFOUT: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow, preferences); return
        }
        print("🔄 NAVIGATIE: type=\(navigationAction.navigationType.rawValue) hoofframe=\(navigationAction.targetFrame?.isMainFrame ?? false) url=\(url.absoluteString.prefix(80))")

        // PATCH: bijlage-downloads van Vibe (chat.mistral.ai/api/files/...)
        // zijn JS-navigaties met een "toonbaar" MIME-type (bv. text/x-swift),
        // waardoor WebKit de inhoud toont i.p.v. te downloaden. Forceer
        // daarom het download-pad voor deze URL's.
        if let host = url.host, host.hasSuffix("mistral.ai"),
           url.path.hasPrefix("/api/files/") {
            print("⬇️ BESTAND HERKEND ALS DOWNLOAD: \(url.absoluteString.prefix(80))")
            decisionHandler(.download, preferences)
            return
        }

        // PATCH: data:-URL's (canvas-exporten) opslaan als bestand i.p.v. in de
        // app weer te geven. WebKit toont een data-PDF anders "gewoon", zonder
        // dat er ooit een download plaatsvindt.
        if url.scheme?.lowercased() == "data" {
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            if let dest = Self.saveDataURL(url, to: downloads) {
                recentDownloads.append(dest)
                if recentDownloads.count > 10 { recentDownloads.removeFirst(recentDownloads.count - 10) }
                print("✅ DATA-URL OPGESLAGEN: \(dest.path)")
                NSWorkspace.shared.activateFileViewerSelecting([dest])
            } else {
                print("❌ DATA-URL NIET OPGESLOPEN")
            }
            decisionHandler(.cancel, preferences)
            return
        }

        // PATCH 1.3.0: every link clicked in an answer — whether a normal link
        // click or a JS-initiated navigation by the web app — opens in a new
        // tab of the default browser when it points outside the Vibe app
        // itself. This includes mistral.ai subdomains (docs.mistral.ai …) and
        // github.com, which the old whitelist kept in-app. Downloads keep
        // their own (earlier) paths and popups go through createWebViewWith.
        if navigationAction.targetFrame?.isMainFrame == true,
           !navigationAction.shouldPerformDownload,
           navigationAction.navigationType == .linkActivated || navigationAction.navigationType == .other,
           let scheme = url.scheme, scheme == "http" || scheme == "https",
           !isAppHost(url) {
            print("🌐 NAAR BROWSER: \(url.absoluteString.prefix(80))")
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel, preferences)
            return
        }
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        print("📄 ANTWOORD: mime=\(navigationResponse.response.mimeType ?? "onbekend") toonbaar=\(navigationResponse.canShowMIMEType)")
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            decisionHandler(.download) // hand off to the download delegate
        }
    }

    func webView(_ webView: WKWebView,
                 navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView,
                 navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: WKUIDelegate — handle target="_blank" / window.open

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        print("🪟 NIEUW VENSTER: \(navigationAction.request.url?.absoluteString ?? "geen url")")
        if let url = navigationAction.request.url {
            // PATCH: blob: and data: URLs (used by canvas exports / JS-initiated
            // downloads) are loaded in the main view, so the download delegate
            // can handle them and Finder opens when finished. Everything else
            // non-internal still goes to the default browser.
            let scheme = url.scheme?.lowercased() ?? ""
            if isAppHost(url) || scheme == "blob" || scheme == "data" {
                webView.load(URLRequest(url: url))
            } else {
                NSWorkspace.shared.open(url)
            }
        }
        return nil
    }

    // File picker for uploads (attaching files in chat)
    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.begin { result in
            completionHandler(result == .OK ? panel.urls : nil)
        }
    }

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        print("⬇️ DOWNLOAD GESTART: \(suggestedFilename)")
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        // PATCH: sanitize the server-suggested filename so it can never
        // contain path components like "../" (path traversal hardening).
        let safeName = ((suggestedFilename as NSString).lastPathComponent as NSString)
        let baseName = safeName.deletingPathExtension
        let ext = safeName.pathExtension
        if baseName.isEmpty && ext.isEmpty {
            completionHandler(downloads.appendingPathComponent("Download"))
            return
        }
        var dest = downloads.appendingPathComponent(baseName + (ext.isEmpty ? "" : "." + ext))
        var i = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let name = ext.isEmpty ? "\(baseName) \(i)" : "\(baseName) \(i).\(ext)"
            dest = downloads.appendingPathComponent(name)
            i += 1
        }
        completionHandler(dest)
    }

    func download(_ download: WKDownload, didFailWithError error: Error,
                  resumeData: Data?) {
        print("❌ DOWNLOAD MISLUKT: \(error.localizedDescription)")
        NSSound.beep()
    }

    func downloadDidFinish(_ download: WKDownload) {
        print("✅ DOWNLOAD KLAAR: \(download.progress.fileURL?.path ?? "onbekend pad")")
        if let url = download.progress.fileURL {
            recentDownloads.append(url)
            if recentDownloads.count > 10 { recentDownloads.removeFirst(recentDownloads.count - 10) }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    private var window: NSWindow!
    private var controller: WebViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = WebViewController()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.title = Config.appName
        window.titlebarAppearsTransparent = false
        window.contentViewController = controller
        window.setFrameAutosaveName("MistralMainWindow") // restores size/position
        // Guard against a previously-saved degenerate frame: if the restored
        // size is too small to be usable, fall back to the default and center.
        if window.frame.width < 480 || window.frame.height < 360 {
            window.setContentSize(NSSize(width: 1100, height: 760))
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(controller.webView) // first click hits the page, not focus

        buildMenu()
        NSApp.activate(ignoringOtherApps: true)

        // PATCH 7 — notifications: register this app with the macOS
        // notification center so web notifications can appear while the app
        // is in the foreground (best effort; delivery also depends on macOS).
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("🔔 Notificatiefout: \(error.localizedDescription)")
            } else {
                print(granted ? "🔔 Notificaties toegestaan" : "🔔 Notificaties geweigerd")
            }
        }
    }

    /// Show notifications as banners even when the app is frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // Keep the app alive when the window is closed (it's only hidden, see below).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Clicking the red close button hides the window instead of destroying it,
    // so the web view (and your session/page state) stays alive. The app keeps
    // running in the Dock; reopen it from the Dock icon. Quit with ⌘Q.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    // Re-show the window when the Dock icon is clicked.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    // MARK: Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(Config.appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Enable Microphone Access…", action: #selector(requestMicAccess), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(Config.appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(Config.appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit menu (gives Cmd+C/V/X/A/Z standard behavior)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // View menu
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Reload", action: #selector(reload), keyEquivalent: "r")
        let home = viewMenu.addItem(withTitle: "Home", action: #selector(goHome), keyEquivalent: "h")
        home.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(.separator())
        // PATCH: page zoom shortcuts (Cmd+ / Cmd- / Cmd0)
        viewMenu.addItem(withTitle: "Zoom In", action: #selector(zoomIn), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(zoomOut), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(zoomReset), keyEquivalent: "0")
        viewMenu.addItem(withTitle: "Find…", action: #selector(findInPage), keyEquivalent: "f")
        viewMenu.addItem(.separator())
        let back = viewMenu.addItem(withTitle: "Back", action: #selector(goBack), keyEquivalent: "[")
        back.keyEquivalentModifierMask = [.command]
        let fwd = viewMenu.addItem(withTitle: "Forward", action: #selector(goForward), keyEquivalent: "]")
        fwd.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(.separator())
        let fullScreen = viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]

        // Go menu
        let goMenuItem = NSMenuItem()
        mainMenu.addItem(goMenuItem)
        let goMenu = NSMenu(title: "Go")
        goMenuItem.submenu = goMenu
        // PATCH: Downloads shortcut (Cmd+J) — shows the most recent downloads
        // in Finder, or opens ~/Downloads if nothing was downloaded yet.
        goMenu.addItem(withTitle: "Downloads", action: #selector(showDownloads), keyEquivalent: "j")
        goMenu.addItem(.separator())
        let openBrowser = goMenu.addItem(withTitle: "Open Page in Browser", action: #selector(openInBrowser), keyEquivalent: "b")
        openBrowser.keyEquivalentModifierMask = [.command, .shift]
        goMenu.addItem(withTitle: "Copy Page Link", action: #selector(copyPageLink), keyEquivalent: "")

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")

        NSApp.mainMenu = mainMenu
    }

    @objc private func reload() { controller.reload() }
    @objc private func goHome() { controller.goHome() }
    @objc private func goBack() { controller.goBack() }
    @objc private func goForward() { controller.goForward() }
    @objc private func zoomIn() { controller.zoomIn() }
    @objc private func zoomOut() { controller.zoomOut() }
    @objc private func zoomReset() { controller.zoomReset() }
    @objc private func showDownloads() { controller.showDownloads() }
    @objc private func requestMicAccess() { controller.requestMicAccess() }
    @objc private func findInPage() { controller.findInPage() }
    @objc private func openInBrowser() { controller.openInBrowser() }
    @objc private func copyPageLink() { controller.copyPageLink() }
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
