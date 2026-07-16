import UIKit

final class ShareViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let urlLabel = UILabel()
    private let messageLabel = UILabel()
    private let saveButton = UIButton(type: .system)

    private var catalog: SharedFolderCatalog?
    private var folders: [SharedFolder] = []
    private var selectedFolder: SharedFolder?
    private var sharedURL: String?
    private var sharedText: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        loadCatalog()
        loadSharedContent()
    }

    private func configureView() {
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.text = "Salva in SaveIn!"

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Annulla", for: .normal)
        cancelButton.addTarget(
            self,
            action: #selector(closeExtension),
            for: .touchUpInside
        )

        saveButton.setTitle("Salva", for: .normal)
        saveButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        saveButton.addTarget(
            self,
            action: #selector(saveShare),
            for: .touchUpInside
        )
        saveButton.isEnabled = false

        let header = UIStackView(arrangedSubviews: [
            cancelButton,
            UIView(),
            titleLabel,
            UIView(),
            saveButton,
        ])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8

        urlLabel.font = .preferredFont(forTextStyle: .footnote)
        urlLabel.textColor = .secondaryLabel
        urlLabel.numberOfLines = 2
        urlLabel.text = "Lettura del link…"

        messageLabel.font = .preferredFont(forTextStyle: .footnote)
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0
        messageLabel.text = "Caricamento cartelle…"

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 50

        let stack = UIStackView(arrangedSubviews: [
            header,
            urlLabel,
            messageLabel,
            tableView,
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 16
            ),
            stack.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -16
            ),
            stack.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 16
            ),
            stack.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -12
            ),
            tableView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])
    }

    private func loadCatalog() {
        do {
            catalog = try AppGroupShareStore.loadCatalog()
            guard let catalog else {
                messageLabel.text =
                    "Apri SaveIn! almeno una volta per sincronizzare le cartelle."
                updateSaveButton()
                return
            }

            folders = catalog.folders.sorted { left, right in
                if left.isDefault != right.isDefault {
                    return left.isDefault
                }
                return left.displayPath.localizedCaseInsensitiveCompare(
                    right.displayPath
                ) == .orderedAscending
            }
            selectedFolder = folders.first { $0.id == catalog.defaultFolderId }
                ?? folders.first
            messageLabel.text = folders.isEmpty
                ? "Nessuna cartella disponibile."
                : "Scegli la cartella di destinazione:"
            tableView.reloadData()
            updateSaveButton()
        } catch {
            messageLabel.text =
                "Impossibile caricare le cartelle. Apri SaveIn! e riprova."
            updateSaveButton()
        }
    }

    private func loadSharedContent() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []

        guard !providers.isEmpty else {
            showContentError("Nessun link web ricevuto.")
            return
        }

        if let urlProvider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier("public.url")
        }) {
            loadValue(from: urlProvider, typeIdentifier: "public.url") {
                [weak self] value in
                self?.consumeSharedValue(value, originalText: nil)
            }
            return
        }

        if let textProvider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier("public.plain-text")
        }) {
            loadValue(
                from: textProvider,
                typeIdentifier: "public.plain-text"
            ) { [weak self] value in
                let text = value as? String
                self?.consumeSharedValue(value, originalText: text)
            }
            return
        }

        showContentError("Nessun link web riconosciuto.")
    }

    private func loadValue(
        from provider: NSItemProvider,
        typeIdentifier: String,
        completion: @escaping (NSSecureCoding?) -> Void
    ) {
        provider.loadItem(
            forTypeIdentifier: typeIdentifier,
            options: nil
        ) { [weak self] value, error in
            DispatchQueue.main.async {
                guard error == nil else {
                    self?.showContentError("Impossibile leggere il link.")
                    return
                }
                completion(value)
            }
        }
    }

    private func consumeSharedValue(
        _ value: NSSecureCoding?,
        originalText: String?
    ) {
        let rawValue: String
        if let url = value as? URL {
            rawValue = url.absoluteString
        } else if let url = value as? NSURL {
            rawValue = url.absoluteString ?? ""
        } else if let string = value as? String {
            rawValue = string
        } else {
            showContentError("Link non riconosciuto.")
            return
        }

        guard let extractedURL = extractWebURL(from: rawValue) else {
            showContentError("Il contenuto condiviso non contiene un link web.")
            return
        }

        sharedURL = extractedURL
        sharedText = originalText
        urlLabel.text = extractedURL
        updateSaveButton()
    }

    private func extractWebURL(from value: String) -> String? {
        if
            let directURL = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = directURL.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        {
            return directURL.absoluteString
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        )
        return detector?
            .firstMatch(in: value, options: [], range: range)?
            .url
            .flatMap { url in
                guard
                    let scheme = url.scheme?.lowercased(),
                    scheme == "http" || scheme == "https"
                else {
                    return nil
                }
                return url.absoluteString
            }
    }

    private func showContentError(_ message: String) {
        sharedURL = nil
        urlLabel.text = message
        updateSaveButton()
    }

    private func updateSaveButton() {
        saveButton.isEnabled =
            sharedURL != nil && selectedFolder != nil && catalog != nil
    }

    @objc private func saveShare() {
        guard
            let catalog,
            let selectedFolder,
            let sharedURL
        else {
            return
        }

        saveButton.isEnabled = false
        do {
            let item = PendingShare(
                id: UUID().uuidString,
                userId: catalog.userId,
                url: sharedURL,
                sharedText: sharedText,
                folderId: selectedFolder.id,
                folderDisplayPath: selectedFolder.displayPath,
                enqueuedAt: ISO8601DateFormatter().string(from: Date()),
                source: "ios_share_extension"
            )
            try AppGroupShareStore.enqueue(item)
            messageLabel.text =
                "Salvato in \(selectedFolder.displayPath). Apri SaveIn! per completare l’importazione."
            tableView.isUserInteractionEnabled = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        } catch {
            messageLabel.text =
                "Salvataggio non riuscito. Riprova tra poco."
            updateSaveButton()
        }
    }

    @objc private func closeExtension() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

extension ShareViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        folders.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let identifier = "FolderCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        let folder = folders[indexPath.row]

        cell.textLabel?.text = folder.name
        cell.detailTextLabel?.text = folder.isDefault
            ? "Tutti i post"
            : folder.displayPath
        cell.indentationLevel = folder.isDefault ? 0 : folder.level
        cell.indentationWidth = 18
        cell.accessoryType =
            selectedFolder?.id == folder.id ? .checkmark : .none
        return cell
    }

    func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        selectedFolder = folders[indexPath.row]
        tableView.reloadData()
        updateSaveButton()
    }
}
