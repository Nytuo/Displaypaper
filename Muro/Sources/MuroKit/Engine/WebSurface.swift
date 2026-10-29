import AppKit
import WebKit
import UniformTypeIdentifiers

/// Hosts a Workshop web wallpaper within its own item directory.
public final class WebSurface: NSObject, WKURLSchemeHandler, WKNavigationDelegate {
    private let root: URL
    public private(set) var view: WKWebView!
    private var volume: Double = 0
    private var suspended = false

    public init?(directory: URL, frame: CGRect) {
        root = directory.resolvingSymlinksInPath().standardizedFileURL
        guard let data = try? Data(contentsOf: root.appendingPathComponent("project.json")),
              let project = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let file = project["file"] as? String else { return nil }
        let candidate = root.appendingPathComponent(file).resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        super.init()
        let definitions = (project["general"] as? [String: Any])?["properties"] as? [String: [String: Any]] ?? [:]
        var props: [String: Any] = [:]
        for (key, value) in definitions where (value["type"] as? String) != "group" {
            if let initial = value["value"] { props[key] = ["value": initial] }
        }
        let json = (try? JSONSerialization.data(withJSONObject: props)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(self, forURLScheme: "wer")
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addUserScript(WKUserScript(source: Self.shim.replacingOccurrences(of: "__WER_PROPERTIES__", with: json), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        view = WKWebView(frame: frame, configuration: config)
        view.navigationDelegate = self
        view.autoresizingMask = [.width, .height]
        var components = URLComponents()
        components.scheme = "wer"
        components.host = "localhost"
        components.path = "/" + file
        if let url = components.url { view.load(URLRequest(url: url)) }
    }

    public func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, url.host == "localhost" else { task.didFailWithError(URLError(.badURL)); return }
        let path = url.path.removingPercentEncoding ?? url.path
        let candidate = root.appendingPathComponent(String(path.drop(while: { $0 == "/" }))).resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: candidate) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let mime = UTType(filenameExtension: candidate.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }
    public func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        setVolume(volume)
        setSuspended(suspended)
    }
    public func setSuspended(_ value: Bool) {
        suspended = value
        view.evaluateJavaScript("window.__wer && window.__wer.setPaused(\(value ? "true" : "false"))", completionHandler: nil)
        if #available(macOS 12.0, *) { view.setAllMediaPlaybackSuspended(value) }
    }
    public func setVolume(_ volume: Double) {
        self.volume = volume
        view.evaluateJavaScript("document.querySelectorAll('audio,video').forEach(e => { e.volume = \(max(0, min(1, volume))); })", completionHandler: nil)
    }
    public func invalidate() { view.stopLoading(); view.removeFromSuperview() }
    private static let shim = #"""
// Wallpaper Engine web-wallpaper API shim, injected before the page's own scripts.
// Written for Rosetta from how real Workshop pages use the API.
(function () {
	if (window.__wer) return;
	var wer = (window.__wer = { errors: [], started: false });
	var props = __WER_PROPERTIES__;
	var audioCallback = null;

	// 64 left + 64 right frequency bands. No audio capture yet, so the pages see silence.
	window.wallpaperRegisterAudioListener = function (callback) { audioCallback = callback; };
	var ignore = function () {};
	window.wallpaperRegisterMediaStatusListener = ignore;
	window.wallpaperRegisterMediaPropertiesListener = ignore;
	window.wallpaperRegisterMediaThumbnailListener = ignore;
	window.wallpaperRegisterMediaPlaybackListener = ignore;
	window.wallpaperRegisterMediaTimelineListener = ignore;
	// "pick a random file from the property's folder": there is none.
	window.wallpaperRequestRandomFileForProperty = function (name, callback) {
		try { callback(name, null); } catch (e) { wer.errors.push(String(e)); }
	};

	wer.start = function () {
		if (wer.started) return;
		wer.started = true;
		var listener = window.wallpaperPropertyListener;
		// Each call runs on its own; a call that throws (a framework such as p5 that is not
		// ready yet) is tried once more shortly after.
		var steps = [
			function () { if (listener.applyGeneralProperties) listener.applyGeneralProperties({ fps: 60 }); },
			function () { if (listener.applyUserProperties) listener.applyUserProperties(props); },
			function () { if (listener.setPaused) listener.setPaused(false); }
		];
		var failed = [];
		if (listener) {
			steps.forEach(function (step) { try { step(); } catch (e) { failed.push(step); } });
		}
		if (failed.length) {
			setTimeout(function () {
				failed.forEach(function (step) {
					try { step(); } catch (e) { wer.errors.push('listener: ' + e); }
				});
			}, 500);
		}
		setInterval(function () {
			if (!audioCallback || wer.realAudio) return;
			try { audioCallback(new Array(128).fill(0)); } catch (e) { wer.errors.push('audio: ' + e); }
		}, 33);
	};
	// The host pushes the live spectrum (64 left + 64 right) when system audio is captured.
	wer.pushAudio = function (bands) {
		wer.realAudio = true;
		if (!audioCallback) return;
		try { audioCallback(bands); } catch (e) { wer.errors.push('audio: ' + e); }
	};
	wer.setProperty = function (name, value) {
		var changed = {};
		changed[name] = { value: value };
		props[name] = changed[name];
		var l = window.wallpaperPropertyListener;
		if (l && l.applyUserProperties) l.applyUserProperties(changed);
	};
	wer.setPaused = function (paused) {
		var l = window.wallpaperPropertyListener;
		if (l && l.setPaused) l.setPaused(!!paused);
	};

	window.addEventListener('error', function (e) { wer.errors.push(String(e.message || e)); });
	window.addEventListener('unhandledrejection', function (e) { wer.errors.push('promise: ' + String(e.reason)); });
	// Pages assign `window.wallpaperPropertyListener` while loading; call into it afterwards.
	window.addEventListener('load', function () { setTimeout(wer.start, 100); });
})();

"""#
}
