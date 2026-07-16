import UIKit

final class ShareViewController: UIViewController {
    private let urlLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        loadSharedURL()
    }

    private func configureView() {
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.text = "SaveIn!"
        titleLabel.textAlignment = .center

        let statusLabel = UILabel()
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.text = "Estensione pronta per ricevere link web."
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        urlLabel.font = .preferredFont(forTextStyle: .footnote)
        urlLabel.textColor = .secondaryLabel
        urlLabel.textAlignment = .center
        urlLabel.numberOfLines = 3
        urlLabel.text = "Lettura del link…"

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Chiudi", for: .normal)
        closeButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        closeButton.addTarget(self, action: #selector(closeExtension), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            statusLabel,
            urlLabel,
            closeButton,
        ])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
        ])
    }

    private func loadSharedURL() {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let providers = item.attachments
        else {
            urlLabel.text = "Nessun link web ricevuto."
            return
        }

        if let urlProvider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier("public.url")
        }) {
            loadValue(from: urlProvider, typeIdentifier: "public.url")
            return
        }

        if let textProvider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier("public.plain-text")
        }) {
            loadValue(from: textProvider, typeIdentifier: "public.plain-text")
            return
        }

        urlLabel.text = "Nessun link web riconosciuto."
    }

    private func loadValue(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) {
        provider.loadItem(
            forTypeIdentifier: typeIdentifier,
            options: nil
        ) { [weak self] value, error in
            DispatchQueue.main.async {
                if let url = value as? URL {
                    self?.urlLabel.text = url.absoluteString
                } else if let urlString = value as? String {
                    self?.urlLabel.text = urlString
                } else {
                    self?.urlLabel.text = error == nil
                        ? "Link non riconosciuto."
                        : "Impossibile leggere il link."
                }
            }
        }
    }

    @objc private func closeExtension() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
