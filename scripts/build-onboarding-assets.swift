import AppKit
import WebKit

// WebKit preserves SVG filters (including the Figma assets' drop shadows).
// AppKit's SVG renderer omits these filters, so use a separate converter here.
final class AssetExporter: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let source: URL
    let output: URL
    init(source: URL, output: URL, size: CGSize) {
        self.source = source; self.output = output
        webView = WKWebView(frame: CGRect(origin: .zero, size: size))
        super.init()
        webView.navigationDelegate = self
    }
    func start() { webView.loadHTMLString("<html><body></body></html>", baseURL: nil) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Rasterize the SVG onto an alpha canvas: WebKit's PDF print path
        // adds an opaque page background, which would cover the icon under the badge.
        let data = try! Data(contentsOf: source).base64EncodedString()
        let script = """
        window.assetExport = new Promise((resolve, reject) => {
            const image = new Image(); window.assetImage = image;
            image.onload = () => {
                const canvas = document.createElement('canvas');
                canvas.width = \(Int(webView.bounds.width * 3));
                canvas.height = \(Int(webView.bounds.height * 3));
                canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
                resolve(canvas.toDataURL('image/png').split(',')[1]);
            };
            image.onerror = () => reject('SVG decode failed');
            image.src = 'data:image/svg+xml;base64,\(data)';
        })
        """
        webView.callAsyncJavaScript("return await (" + script + ")", in: nil, in: .page) { result in
            do {
                guard let base64 = try result.get() as? String,
                      let imageData = Data(base64Encoded: base64) else { throw CocoaError(.fileReadCorruptFile) }
                try imageData.write(to: self.output)
                exit(0)
            } catch { fputs("SVG export failed: \(error)\n", stderr); exit(1) }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fputs("SVG load failed: \(error)\n", stderr); exit(1)
    }
}
guard CommandLine.arguments.count == 5,
      let width = Double(CommandLine.arguments[3]), let height = Double(CommandLine.arguments[4]) else {
    fatalError("Usage: build-onboarding-assets input.svg output.png width height")
}
_ = NSApplication.shared
let exporter = AssetExporter(source: URL(fileURLWithPath: CommandLine.arguments[1]),
                             output: URL(fileURLWithPath: CommandLine.arguments[2]),
                             size: CGSize(width: width, height: height))
exporter.start()
DispatchQueue.main.asyncAfter(deadline: .now() + 30) { fputs("SVG export timed out\n", stderr); exit(1) }
RunLoop.main.run()
