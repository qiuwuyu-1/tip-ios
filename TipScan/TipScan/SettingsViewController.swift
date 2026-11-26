import UIKit

class SettingsViewController: UIViewController {

    var onSave: (([String: String]) -> Void)?

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var fields: [String: UITextField] = [:]

    private let ocrProviders = ["siliconflow", "openrouter", "qwen", "openai", "moonshot", "custom"]
    private let ocrLabels = ["硅基流动（推荐）", "OpenRouter（推荐）", "通义千问 VL", "OpenAI", "Kimi 视觉", "自定义"]
    private let aiProviders = ["siliconflow", "openrouter", "deepseek", "qwen", "moonshot", "openai", "custom"]
    private let aiLabels = ["硅基流动（推荐）", "OpenRouter（推荐）", "DeepSeek", "通义千问", "Kimi", "OpenAI", "自定义"]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(hex: 0xF6F7F9)
        title = "API 设置"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save, target: self, action: #selector(save))

        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -40)
        ])

        addSection("云端 OCR（拍照识别题目）")
        addPicker("OCR 服务商", key: "ocrProvider", items: ocrLabels, values: ocrProviders, def: "siliconflow")
        addField("OCR API Key", key: "ocrKey", placeholder: "sk-...（留空不启用 OCR）", def: "")
        addField("OCR 接口地址（自定义）", key: "ocrEndpoint", placeholder: "留空用预设；自定义填完整地址", def: "")
        addField("OCR 模型名（自定义）", key: "ocrModel", placeholder: "留空用预设；自定义填模型名", def: "")

        addSection("AI 兜底（题库找不到时作答）")
        addPicker("AI 服务商", key: "aiProvider", items: aiLabels, values: aiProviders, def: "siliconflow")
        addField("AI API Key", key: "aiKey", placeholder: "sk-...（留空不启用 AI 兜底）", def: "")
        addField("AI 接口地址（自定义）", key: "aiEndpoint", placeholder: "留空用预设；自定义填完整地址", def: "")
        addField("AI 模型名（自定义）", key: "aiModel", placeholder: "留空用预设；自定义填模型名", def: "")

        let note = UILabel()
        note.text = "选「自定义」时填接口地址与模型名；其他服务商留空即用预设。自定义接口需为 OpenAI 兼容格式（/chat/completions）。密钥只存本机。"
        note.numberOfLines = 0
        note.font = UIFont.systemFont(ofSize: 12)
        note.textColor = UIColor(hex: 0x777777)
        stack.addArrangedSubview(note)
    }

    private func addSection(_ title: String) {
        let l = UILabel()
        l.text = title
        l.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        l.textColor = UIColor(hex: 0x7A4FD6)
        stack.addArrangedSubview(l)
    }

    private func addField(_ label: String, key: String, placeholder: String, def: String) {
        let l = UILabel()
        l.text = label
        l.font = UIFont.systemFont(ofSize: 13)
        l.textColor = UIColor(hex: 0x555555)
        stack.addArrangedSubview(l)

        let tf = UITextField()
        tf.placeholder = placeholder
        tf.borderStyle = .roundedRect
        tf.font = UIFont.systemFont(ofSize: 14)
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.text = UserDefaults.standard.string(forKey: "cfg_" + key) ?? def
        tf.heightAnchor.constraint(equalToConstant: 40).isActive = true
        fields[key] = tf
        stack.addArrangedSubview(tf)
    }

    private func addPicker(_ label: String, key: String, items: [String], values: [String], def: String) {
        let l = UILabel()
        l.text = label
        l.font = UIFont.systemFont(ofSize: 13)
        l.textColor = UIColor(hex: 0x555555)
        stack.addArrangedSubview(l)

        let tf = UITextField()
        tf.borderStyle = .roundedRect
        tf.font = UIFont.systemFont(ofSize: 14)
        let saved = UserDefaults.standard.string(forKey: "cfg_" + key) ?? def
        tf.text = items[values.firstIndex(of: saved) ?? 0]
        tf.heightAnchor.constraint(equalToConstant: 40).isActive = true

        let picker = InlinePicker(items: items, key: key)
        picker.tag = key == "ocrProvider" ? 1 : 2
        // UIPickerView 不是 UIControl，不能用 addTarget；改用 didSelectRow 回调更新输入框
        picker.onSelect = { [weak tf] row in
            guard row < items.count else { return }
            tf?.text = items[row]
        }
        tf.inputView = picker
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(donePick))
        toolbar.items = [flex, done]
        tf.inputAccessoryView = toolbar
        fields[key] = tf
        stack.addArrangedSubview(tf)
    }

    @objc private func donePick() {
        view.endEditing(true)
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    @objc private func save() {
        func pick(_ key: String, _ labels: [String], _ values: [String]) -> String {
            let text = fields[key]?.text ?? ""
            if let i = labels.firstIndex(of: text), i < values.count { return values[i] }
            return text.isEmpty ? values[0] : text
        }
        let cfg: [String: String] = [
            "ocrProvider": pick("ocrProvider", ocrLabels, ocrProviders),
            "ocrKey": fields["ocrKey"]?.text ?? "",
            "ocrEndpoint": fields["ocrEndpoint"]?.text ?? "",
            "ocrModel": fields["ocrModel"]?.text ?? "",
            "aiProvider": pick("aiProvider", aiLabels, aiProviders),
            "aiKey": fields["aiKey"]?.text ?? "",
            "aiEndpoint": fields["aiEndpoint"]?.text ?? "",
            "aiModel": fields["aiModel"]?.text ?? ""
        ]
        onSave?(cfg)
        dismiss(animated: true)
    }
}

private class InlinePicker: UIPickerView, UIPickerViewDataSource, UIPickerViewDelegate {
    let items: [String]
    var pickKey: String?
    var onSelect: ((Int) -> Void)?
    init(items: [String], key: String) {
        self.items = items
        self.pickKey = key
        super.init(frame: .zero)
        self.dataSource = self
        self.delegate = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { items.count }
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return items[row]
    }
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        onSelect?(row)
    }
}
