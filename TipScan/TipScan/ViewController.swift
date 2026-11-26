import UIKit
import WebKit

class ViewController: UIViewController, WKScriptMessageHandler, WKUIDelegate,
                      UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    private var webView: WKWebView!
    private var openPanelCompletion: (([URL]?) -> Void)?
    private var didShowSettings = false

    // 把 WKWebView 的 postMessage 桥接包装成 app.js 期望的 NativeHttpBridge.post 形态。
    // 这样 app.js 无需改动，浏览器/安卓/iOS 三端共用同一份逻辑。
    private let bridgeJS = """
    (function(){
      if (window.NativeHttpBridge) return;
      window.NativeHttpBridge = {
        post: function(url, headersJson, bodyJson, callbackId){
          try {
            window.webkit.messageHandlers.nativeHttp.postMessage({
              url: url, headers: headersJson, body: bodyJson, callbackId: callbackId
            });
          } catch(e) {
            if (window.__nativeCb && window.__nativeCb[callbackId]) {
              window.__nativeCb[callbackId]('原生桥接调用失败: ' + e, null);
            }
          }
        }
      };
      window.__TIPSCAN_IOS__ = true;
    })();
    """

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(hex: 0xF6F7F9)
        title = "拍照搜题"

        let config = WKWebViewConfiguration()
        let cc = WKUserContentController()
        cc.add(self, name: "nativeHttp")
        cc.addUserScript(WKUserScript(source: bridgeJS,
                                      injectionTime: .atDocumentStart,
                                      forMainFrameOnly: true))
        config.userContentController = cc

        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.uiDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // 右上角原生「设置」按钮：不依赖网页 DOM，必定可点
        let btn = UIButton(type: .system)
        btn.setTitle("设置", for: .normal)
        btn.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor(hex: 0x7A4FD6)
        btn.layer.cornerRadius = 8
        btn.frame = CGRect(x: 0, y: 0, width: 56, height: 32)
        btn.addTarget(self, action: #selector(showSettings), for: .touchUpInside)
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: btn)

        loadPage()
        applySavedConfigToStorage()

        // 首次启动自动弹原生设置框
        let key = "native_settings_intro"
        if !UserDefaults.standard.bool(forKey: key) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.showSettings()
            }
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    private func loadPage() {
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Assets") else {
            let label = UILabel(frame: view.bounds)
            label.text = "页面资源加载失败"
            label.textAlignment = .center
            view.addSubview(label)
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    // ---------- 原生 HTTP 桥接 ----------
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "nativeHttp",
              let d = message.body as? [String: Any],
              let urlString = d["url"] as? String,
              let headersJson = d["headers"] as? String,
              let bodyJson = d["body"] as? String,
              let callbackId = d["callbackId"] as? String else { return }

        guard let url = URL(string: urlString) else {
            callbackJS(callbackId, err: "无效的接口地址", resp: nil)
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyJson.data(using: .utf8)
        req.timeoutInterval = 90
        if let hdata = headersJson.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: hdata, options: []),
           let headers = obj as? [String: String] {
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        }

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self else { return }
            if let e = error {
                self.callbackJS(callbackId, err: e.localizedDescription, resp: nil)
                return
            }
            guard let http = response as? HTTPURLResponse else {
                self.callbackJS(callbackId, err: "无 HTTP 响应", resp: nil)
                return
            }
            let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
            if http.statusCode < 200 || http.statusCode >= 300 {
                let snippet = String(text.prefix(160))
                self.callbackJS(callbackId, err: "HTTP \(http.statusCode) \(snippet)", resp: nil)
                return
            }
            self.callbackJS(callbackId, err: nil, resp: text)
        }.resume()
    }

    private func callbackJS(_ callbackId: String, err: String?, resp: String?) {
        let e = err == nil ? "null" : "'\(escapeJS(err!))'"
        let r = resp == nil ? "null" : "'\(escapeJS(resp!))'"
        let js = "try{window.__nativeCb && window.__nativeCb['\(callbackId)'](\(e),\(r));}catch(ex){}"
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    private func escapeJS(_ s: String) -> String {
        return s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "")
    }

    // ---------- 原生设置 ----------
    @objc func showSettings() {
        let vc = SettingsViewController()
        vc.onSave = { [weak self] cfg in
            self?.applyConfig(cfg)
        }
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    private func applyConfig(_ cfg: [String: String]) {
        // 写 UserDefaults 持久保存
        let d = UserDefaults.standard
        for (k, v) in cfg { d.set(v, forKey: "cfg_" + k) }
        // 同步写入网页 localStorage
        applySavedConfigToStorage()
        // 重新加载让配置生效
        loadPage()
    }

    private func applySavedConfigToStorage() {
        let d = UserDefaults.standard
        func val(_ k: String, _ def: String) -> String {
            return d.string(forKey: "cfg_" + k) ?? def
        }
        let keys = ["ocrProvider": "siliconflow", "ocrKey": "", "ocrEndpoint": "", "ocrModel": "",
                    "aiProvider": "siliconflow", "aiKey": "", "aiEndpoint": "", "aiModel": ""]
        var pairs: [String] = []
        for (k, def) in keys {
            pairs.append("'\(k)':\"\(escapeJS(val(k, def)))\"")
        }
        let json = "{" + pairs.joined(separator: ",") + "}"
        let js = "try{localStorage.setItem('pq_config_v1',\(json));}catch(e){}"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // ---------- 拍照 / 选图（WKWebView file input）----------
    // WKOpenPanelParameters 在新 SDK 里被标为 iOS 18.4+，用 @available 满足编译期检查。
    // Swift 的 @available 只影响编译检查，不会移除 Objective-C selector；
    // 因此 iOS 14.5+ 的 WKWebView 仍会通过 respondsToSelector 找到此方法并回调，拍照照常可用。
    @available(iOS 18.4, *)
    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        self.openPanelCompletion = completionHandler
        let sheet = UIAlertController(title: "选择图片", message: nil, preferredStyle: .actionSheet)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            sheet.addAction(UIAlertAction(title: "拍照", style: .default) { [weak self] _ in
                self?.presentPicker(.camera)
            })
        }
        sheet.addAction(UIAlertAction(title: "从相册选择", style: .default) { [weak self] _ in
            self?.presentPicker(.photoLibrary)
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            self?.openPanelCompletion?(nil)
            self?.openPanelCompletion = nil
        })
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = self.view
            pop.sourceRect = CGRect(x: self.view.bounds.midX,
                                    y: self.view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        present(sheet, animated: true)
    }

    private func presentPicker(_ source: UIImagePickerController.SourceType) {
        let picker = UIImagePickerController()
        picker.sourceType = source
        picker.delegate = self
        // iPad 上相册选择需要指定 popover 位置，否则会崩溃
        if let pop = picker.popoverPresentationController {
            pop.sourceView = self.view
            pop.sourceRect = CGRect(x: self.view.bounds.midX,
                                    y: self.view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        present(picker, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        guard let img = info[.originalImage] as? UIImage,
              let data = img.jpegData(compressionQuality: 0.9) else {
            finishPanel(nil); return
        }
        let f = FileManager.default.temporaryDirectory
            .appendingPathComponent("pick_\(Int(Date().timeIntervalSince1970)).jpg")
        try? data.write(to: f)
        finishPanel([f])
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        finishPanel(nil)
    }

    private func finishPanel(_ urls: [URL]?) {
        openPanelCompletion?(urls)
        openPanelCompletion = nil
    }
}

extension UIColor {
    convenience init(hex: Int) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
