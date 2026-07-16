import UIKit

final class ShareViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let urlLabel = UILabel()
    private let messageLabel = UILabel()
    private let saveButton = UIButton(type: .system)
    private let newFolderButton = UIButton(type: .system)
    private let tagsTextField = UITextField()

    private var catalog: SharedFolderCatalog?
    private var folders: [SharedFolder] = []
    private var selectedFolder: SharedFolder?
    private var expandedFolderIds = Set<String>()
    private var pendingNewFolderName: String?
    private var pendingNewFolderParent: SharedFolder?
    private var sharedURL: String?
    private var sharedText: String?

    private var visibleFolders: [SharedFolder] {
        let folderIds = Set(folders.map(\.id))
        let defaultFolders = folders.filter(\.isDefault)
        let roots = folders.filter { folder in
            guard !folder.isDefault else { return false }
            guard let parentId = folder.parentId else { return true }
            return !folderIds.contains(parentId)
        }

        var result = sortedFolders(defaultFolders)
        func append(_ folder: SharedFolder) {
            result.append(folder)
            guard expandedFolderIds.contains(folder.id) else { return }
            for child in children(of: folder) {
                append(child)
            }
        }
        for root in sortedFolders(roots) {
            append(root)
        }
        return result
    }

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

        newFolderButton.setTitle("+ Nuova cartella", for: .normal)
        newFolderButton.contentHorizontalAlignment = .left
        newFolderButton.addTarget(
            self,
            action: #selector(showNewFolderPrompt),
            for: .touchUpInside
        )
        newFolderButton.isEnabled = false

        tagsTextField.borderStyle = .roundedRect
        tagsTextField.placeholder = "Tag opzionali, separati da virgola"
        tagsTextField.autocapitalizationType = .none
        tagsTextField.autocorrectionType = .no
        tagsTextField.returnKeyType = .done
        tagsTextField.delegate = self

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 50

        let stack = UIStackView(arrangedSubviews: [
            header,
            urlLabel,
            messageLabel,
            newFolderButton,
            tagsTextField,
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
                : "Tocca una cartella con ▸ per espanderla."
            newFolderButton.isEnabled = !folders.isEmpty
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

    private func sortedFolders(_ values: [SharedFolder]) -> [SharedFolder] {
        values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func children(of folder: SharedFolder) -> [SharedFolder] {
        sortedFolders(
            folders.filter {
                !$0.isDefault && $0.parentId == folder.id
            }
        )
    }

    private func hasChildren(_ folder: SharedFolder) -> Bool {
        folders.contains {
            !$0.isDefault && $0.parentId == folder.id
        }
    }

    private func updateDestinationMessage() {
        guard let selectedFolder else { return }
        if let pendingNewFolderName {
            let parentPath = pendingNewFolderParent?.displayPath ?? "radice"
            messageLabel.text =
                "Nuova cartella “\(pendingNewFolderName)” in \(parentPath)."
        } else {
            messageLabel.text =
                "Destinazione: \(selectedFolder.displayPath)"
        }
    }

    private func parsedTags() -> [String] {
        var seen = Set<String>()
        return (tagsTextField.text ?? "")
            .split(separator: ",")
            .map {
                String($0)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            }
            .filter { tag in
                guard !tag.isEmpty && tag.count <= 30 else { return false }
                return seen.insert(tag.lowercased()).inserted
            }
            .prefix(20)
            .map { $0 }
    }

    @objc private func showNewFolderPrompt() {
        guard let selectedFolder else { return }

        let parent = selectedFolder.isDefault ? nil : selectedFolder
        let alert = UIAlertController(
            title: "Nuova cartella",
            message: parent == nil
                ? "Verrà creata al livello principale."
                : "Verrà creata dentro \(parent!.displayPath).",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "Nome cartella"
            textField.autocapitalizationType = .sentences
            textField.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: "Annulla", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "Crea e seleziona", style: .default) {
                [weak self, weak alert] _ in
                guard
                    let self,
                    let name = alert?.textFields?.first?.text?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    !name.isEmpty
                else {
                    return
                }
                self.pendingNewFolderName = String(name.prefix(100))
                self.pendingNewFolderParent = parent
                self.updateDestinationMessage()
                self.updateSaveButton()
            }
        )
        present(alert, animated: true)
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
                source: "ios_share_extension",
                tags: parsedTags(),
                newFolderName: pendingNewFolderName,
                newFolderParentId: pendingNewFolderParent?.id,
                newFolderParentPath: pendingNewFolderParent?.displayPath
            )
            try AppGroupShareStore.enqueue(item)
            let destination = pendingNewFolderName.map { name in
                pendingNewFolderParent.map {
                    "\($0.displayPath) › \(name)"
                } ?? name
            } ?? selectedFolder.displayPath
            messageLabel.text =
                "Salvato in \(destination). Apri SaveIn! per completare l’importazione."
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
        visibleFolders.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let identifier = "FolderCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        let folder = visibleFolders[indexPath.row]
        let expandable = hasChildren(folder)
        let marker = expandable
            ? (expandedFolderIds.contains(folder.id) ? "▾ " : "▸ ")
            : ""

        cell.textLabel?.text = marker + folder.name
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
        let folder = visibleFolders[indexPath.row]
        selectedFolder = folder
        pendingNewFolderName = nil
        pendingNewFolderParent = nil
        if hasChildren(folder) {
            if expandedFolderIds.contains(folder.id) {
                expandedFolderIds.remove(folder.id)
            } else {
                expandedFolderIds.insert(folder.id)
            }
        }
        updateDestinationMessage()
        tableView.reloadData()
        updateSaveButton()
    }
}

extension ShareViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
