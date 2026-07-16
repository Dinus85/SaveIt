import UIKit

final class ShareViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let urlLabel = UILabel()
    private let messageLabel = UILabel()
    private let saveButton = UIButton(type: .system)
    private let tagsButton = UIButton(type: .system)

    private var catalog: SharedFolderCatalog?
    private var folders: [SharedFolder] = []
    private var selectedFolder: SharedFolder?
    private var expandedFolderIds = Set<String>()
    private var pendingNewFolderName: String?
    private var pendingNewFolderParent: SharedFolder?
    private var selectedTags: [String] = []
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

        tagsButton.setTitle("+ Aggiungi tag al post", for: .normal)
        tagsButton.contentHorizontalAlignment = .left
        tagsButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        tagsButton.addTarget(
            self,
            action: #selector(showTagsPrompt),
            for: .touchUpInside
        )
        tagsButton.isEnabled = false

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 50

        let stack = UIStackView(arrangedSubviews: [
            header,
            urlLabel,
            messageLabel,
            tagsButton,
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
            tableView.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),
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
            updateTagsButton()
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
                "“\(pendingNewFolderName)” verrà creata in \(parentPath) "
                + "quando salvi il post."
            saveButton.setTitle("Crea e salva", for: .normal)
        } else {
            messageLabel.text =
                "Destinazione: \(selectedFolder.displayPath)"
            saveButton.setTitle("Salva", for: .normal)
        }
    }

    private func parsedTags() -> [String] {
        selectedTags
    }

    private func parseTags(from text: String) -> [String] {
        var seen = Set<String>()
        return text
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

    private func updateTagsButton() {
        let allowed = catalog?.limits?.manualTagsEnabled == true
        tagsButton.isEnabled = allowed
        if !allowed {
            tagsButton.setTitle(
                "Tag manuali non disponibili per il tuo piano",
                for: .normal
            )
        } else if selectedTags.isEmpty {
            tagsButton.setTitle("+ Aggiungi tag al post", for: .normal)
        } else {
            tagsButton.setTitle(
                "🏷 Tag: \(selectedTags.joined(separator: ", "))",
                for: .normal
            )
        }
    }

    @objc private func showTagsPrompt() {
        guard catalog?.limits?.manualTagsEnabled == true else { return }
        let alert = UIAlertController(
            title: "Aggiungi tag al post",
            message: "Inserisci fino a 20 tag separati da virgola.",
            preferredStyle: .alert
        )
        alert.addTextField { [selectedTags] textField in
            textField.text = selectedTags.joined(separator: ", ")
            textField.placeholder = "es. ricette, dolci, estate"
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Annulla", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "Conferma", style: .default) {
                [weak self, weak alert] _ in
                guard let self else { return }
                self.selectedTags = self.parseTags(
                    from: alert?.textFields?.first?.text ?? ""
                )
                self.updateTagsButton()
            }
        )
        present(alert, animated: true)
    }

    private func folderCreationBlockMessage(
        for parentCandidate: SharedFolder
    ) -> String? {
        guard let limits = catalog?.limits else {
            return "Apri SaveIn! per aggiornare i limiti del tuo piano."
        }

        if parentCandidate.isDefault {
            guard limits.rootFoldersEnabled else {
                return "La creazione di cartelle principali è disabilitata."
            }
            let rootCount = folders.filter {
                !$0.isDefault && $0.parentId == nil
            }.count
            if limits.rootFolderLimit > 0 &&
                rootCount >= limits.rootFolderLimit
            {
                return "Hai raggiunto il limite di cartelle principali."
            }
            return nil
        }

        guard limits.childFoldersEnabled else {
            return "La creazione di sottocartelle è disabilitata."
        }
        guard limits.folderLevelsEnabled else {
            return "La creazione di nuovi livelli è disabilitata."
        }
        let childCount = children(of: parentCandidate).count
        if limits.childFolderLimit > 0 &&
            childCount >= limits.childFolderLimit
        {
            return "Hai raggiunto il limite di sottocartelle."
        }
        if limits.folderLevelLimit > 0 &&
            parentCandidate.level >= limits.folderLevelLimit - 1
        {
            return "Hai raggiunto il limite di livelli delle cartelle."
        }
        return nil
    }

    @objc private func createFolderFromRow(_ sender: UIButton) {
        let currentFolders = visibleFolders
        guard currentFolders.indices.contains(sender.tag) else { return }
        let parentCandidate = currentFolders[sender.tag]
        if let message = folderCreationBlockMessage(for: parentCandidate) {
            let alert = UIAlertController(
                title: "Nuova cartella non disponibile",
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        showNewFolderPrompt(for: parentCandidate)
    }

    private func showNewFolderPrompt(for parentCandidate: SharedFolder) {
        let parent = parentCandidate.isDefault ? nil : parentCandidate
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
            UIAlertAction(title: "Usa questa cartella", style: .default) {
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
                self.selectedFolder = parentCandidate
                self.updateDestinationMessage()
                self.updateSaveButton()
                self.tableView.reloadData()
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
            : (folder.level == 0 ? nil : folder.displayPath)
        cell.indentationLevel = folder.isDefault ? 0 : folder.level
        cell.indentationWidth = 18

        let accessoryStack = UIStackView()
        accessoryStack.axis = .horizontal
        accessoryStack.alignment = .center
        accessoryStack.spacing = 10
        if selectedFolder?.id == folder.id {
            let checkmark = UIImageView(
                image: UIImage(systemName: "checkmark")
            )
            checkmark.tintColor = view.tintColor
            accessoryStack.addArrangedSubview(checkmark)
        }

        let addButton = UIButton(type: .system)
        addButton.setImage(UIImage(systemName: "plus.circle"), for: .normal)
        addButton.tag = indexPath.row
        addButton.accessibilityLabel = folder.isDefault
            ? "Crea cartella principale"
            : "Crea sottocartella in \(folder.name)"
        addButton.addTarget(
            self,
            action: #selector(createFolderFromRow(_:)),
            for: .touchUpInside
        )
        if folderCreationBlockMessage(for: folder) != nil {
            addButton.tintColor = .tertiaryLabel
        }
        accessoryStack.addArrangedSubview(addButton)
        cell.accessoryType = .none
        cell.accessoryView = accessoryStack
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
        saveButton.setTitle("Salva", for: .normal)
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
