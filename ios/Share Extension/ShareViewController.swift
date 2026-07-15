import UIKit
import MobileCoreServices

final class ShareViewController: UIViewController {
    private let appGroupId = "group.eu.savein.app.share"
    private let sharedMediaKey = "ShareKey"
    private var didFinish = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        receiveSharedContent()
    }

    private func receiveSharedContent() {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let providers = item.attachments,
            let provider = providers.first
        else {
            finish()
            return
        }

        if provider.hasItemConformingToTypeIdentifier(kUTTypeURL as String) {
            provider.loadItem(forTypeIdentifier: kUTTypeURL as String, options: nil) {
                [weak self] value, _ in
                let url = (value as? URL)?.absoluteString ?? value as? String
                self?.saveAndOpenHost(value: url, type: "url")
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(kUTTypeText as String) {
            provider.loadItem(forTypeIdentifier: kUTTypeText as String, options: nil) {
                [weak self] value, _ in
                self?.saveAndOpenHost(value: value as? String, type: "text")
            }
            return
        }

        finish()
    }

    private func saveAndOpenHost(value: String?, type: String) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            finish()
            return
        }

        let payload: [[String: Any]] = [[
            "path": value,
            "type": type
        ]]

        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            let defaults = UserDefaults(suiteName: appGroupId)
            defaults?.set(data, forKey: sharedMediaKey)
            defaults?.synchronize()
        }

        DispatchQueue.main.async { [weak self] in
            self?.openHostApp()
        }
    }

    private func openHostApp() {
        guard let url = URL(string: "ShareMedia-eu.savein.app:share") else {
            finish()
            return
        }

        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector) {
                _ = current.perform(selector, with: url)
                break
            }
            responder = current.next
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.finish()
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        extensionContext?.completeRequest(returningItems: nil)
    }
}
