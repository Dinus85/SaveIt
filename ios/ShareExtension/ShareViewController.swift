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
    private var folderDrafts: [SharedFolderDraft] = []
    private var selectedTags: [String] = []
    private var sharedURL: String?
    private var sharedText: String?
    private var isSaving = false

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
            !isSaving &&
            sharedURL != nil &&
            selectedFolder != nil &&
            catalog != nil
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

    private func isDraft(_ folder: SharedFolder) -> Bool {
        folderDrafts.contains { $0.id == folder.id }
    }

    private func draft(for folder: SharedFolder) -> SharedFolderDraft? {
        folderDrafts.first { $0.id == folder.id }
    }

    private func discardAllDrafts() {
        let draftIds = Set(folderDrafts.map(\.id))
        folders.removeAll { draftIds.contains($0.id) }
        expandedFolderIds.subtract(draftIds)
        folderDrafts.removeAll()
    }

    private func discardDraftAndDescendants(_ draftId: String) {
        var idsToRemove: Set<String> = [draftId]
        var foundChild = true
        while foundChild {
            foundChild = false
            for draft in folderDrafts
            where draft.parentDraftId.map(idsToRemove.contains) == true {
                if idsToRemove.insert(draft.id).inserted {
                    foundChild = true
                }
            }
        }
        folderDrafts.removeAll { idsToRemove.contains($0.id) }
        folders.removeAll { idsToRemove.contains($0.id) }
        expandedFolderIds.subtract(idsToRemove)

        if let selectedFolder, idsToRemove.contains(selectedFolder.id) {
            self.selectedFolder =
                folders.first { $0.id == catalog?.defaultFolderId }
                ?? folders.first
        }
    }

    private func updateDestinationMessage() {
        guard let selectedFolder else { return }
        if isDraft(selectedFolder) {
            messageLabel.text =
                "Destinazione temporanea: \(selectedFolder.displayPath). "
                + "Le cartelle verranno create solo quando tocchi Salva."
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
                let safeName = String(name.prefix(100))
                let siblingParentId = parentCandidate.isDefault
                    ? nil
                    : parentCandidate.id
                let duplicate = self.folders.contains {
                    !$0.isDefault &&
                        $0.parentId == siblingParentId &&
                        $0.name.compare(
                            safeName,
                            options: [.caseInsensitive, .diacriticInsensitive]
                        ) == .orderedSame
                }
                if duplicate {
                    self.messageLabel.text =
                        "Esiste già una cartella con questo nome qui."
                    return
                }
                let draftId = UUID().uuidString
                let parentDraft = parent.flatMap { self.draft(for: $0) }
                let displayPath = parent.map {
                    "\($0.displayPath) › \(safeName)"
                } ?? safeName
                let level = parent.map { $0.level + 1 } ?? 0
                let draft = SharedFolderDraft(
                    id: draftId,
                    name: safeName,
                    parentFolderId: parentDraft == nil ? parent?.id : nil,
                    parentDraftId: parentDraft?.id,
                    parentDisplayPath: parent?.displayPath,
                    displayPath: displayPath,
                    level: level,
                    color: "#BB86FC"
                )
                self.folderDrafts.append(draft)
                let temporaryFolder = SharedFolder(
                    id: draft.id,
                    name: draft.name,
                    parentId: siblingParentId,
                    color: draft.color,
                    isDefault: false,
                    displayPath: draft.displayPath,
                    level: draft.level
                )
                self.folders.append(temporaryFolder)
                self.selectedFolder = temporaryFolder
                if let parent {
                    self.expandedFolderIds.insert(parent.id)
                }
                self.expandedFolderIds.insert(temporaryFolder.id)
                self.updateDestinationMessage()
                self.updateSaveButton()
                self.tableView.reloadData()
            }
        )
        present(alert, animated: true)
    }

    private func discardAbandonedDrafts(keepingPathTo folder: SharedFolder) {
        let keepIds = draftAncestorIds(for: folder)
        let abandoned = folderDrafts.filter { !keepIds.contains($0.id) }
        for draft in abandoned {
            discardDraftAndDescendants(draft.id)
        }
    }

    private func draftAncestorIds(for folder: SharedFolder) -> Set<String> {
        var keepIds = Set<String>()
        guard isDraft(folder) else { return keepIds }

        var currentId: String? = folder.id
        while let id = currentId {
            keepIds.insert(id)
            currentId = folderDrafts.first { $0.id == id }?.parentDraftId
        }
        return keepIds
    }

    private func draftsRequiredForSave(
        destination: SharedFolder
    ) -> [SharedFolderDraft] {
        let keepIds = draftAncestorIds(for: destination)
        return folderDrafts.filter { keepIds.contains($0.id) }
    }

    @objc private func saveShare() {
        guard
            let catalog,
            let selectedFolder,
            let sharedURL
        else {
            return
        }

        isSaving = true
        saveButton.isEnabled = false
        tableView.isUserInteractionEnabled = false
        tagsButton.isEnabled = false
        messageLabel.text = "Salvataggio in corso…"
        saveButton.setTitle("Salvo…", for: .normal)

        let drafts = draftsRequiredForSave(destination: selectedFolder)
        let destinationDraftId = isDraft(selectedFolder)
            ? selectedFolder.id
            : nil
        let destinationFolderId = isDraft(selectedFolder)
            ? nil
            : selectedFolder.id
        let requestId = UUID().uuidString
        let tags = parsedTags()
        let sharedTextValue = sharedText

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                guard let session = try AppGroupShareStore.loadAuthSession(),
                      session.isUsable,
                      session.userId == catalog.userId
                else {
                    throw SaveError.authRequired
                }

                var body: [String: Any] = [
                    "clientRequestId": requestId,
                    "url": sharedURL,
                    "tags": tags,
                    "folderDrafts": drafts.map { draft -> [String: Any] in
                        var item: [String: Any] = [
                            "id": draft.id,
                            "name": draft.name,
                            "displayPath": draft.displayPath,
                            "level": draft.level,
                            "color": draft.color,
                        ]
                        if let parentFolderId = draft.parentFolderId {
                            item["parentFolderId"] = parentFolderId
                        }
                        if let parentDraftId = draft.parentDraftId {
                            item["parentDraftId"] = parentDraftId
                        }
                        if let parentDisplayPath = draft.parentDisplayPath {
                            item["parentDisplayPath"] = parentDisplayPath
                        }
                        return item
                    },
                ]
                if let sharedTextValue, !sharedTextValue.isEmpty {
                    body["sharedText"] = sharedTextValue
                }
                if let destinationDraftId {
                    body["destinationDraftId"] = destinationDraftId
                }
                if let destinationFolderId {
                    body["destinationFolderId"] = destinationFolderId
                }

                let createdFolderCount = try Self.postShareSave(
                    endpoint: session.saveEndpoint,
                    token: session.idToken,
                    body: body
                )

                DispatchQueue.main.async {
                    self?.finishSaveSuccess(
                        destination: selectedFolder.displayPath,
                        createdFolders: createdFolderCount
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self?.finishSaveFailure(error)
                }
            }
        }
    }

    private func finishSaveSuccess(
        destination: String,
        createdFolders: Int
    ) {
        isSaving = false
        folderDrafts.removeAll()
        let folderNote = createdFolders > 0
            ? " Cartelle create: \(createdFolders)."
            : ""
        messageLabel.text =
            "Salvato in \(destination).\(folderNote)"
        saveButton.setTitle("Fatto", for: .normal)
        saveButton.isEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func finishSaveFailure(_ error: Error) {
        isSaving = false
        tableView.isUserInteractionEnabled = true
        updateTagsButton()
        updateDestinationMessage()
        if let saveError = error as? SaveError {
            messageLabel.text = saveError.localizedDescription
        } else {
            messageLabel.text =
                "Salvataggio non riuscito. Riprova tra poco."
        }
        updateSaveButton()
    }

    private static func postShareSave(
        endpoint: String,
        token: String,
        body: [String: Any]
    ) throws -> Int {
        guard let url = URL(string: endpoint) else {
            throw SaveError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "Bearer \(token)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.timeoutInterval = 45
        request.httpBody = try JSONSerialization.data(
            withJSONObject: body,
            options: []
        )

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseError: Error?
        var statusCode = 0

        let task = URLSession.shared.dataTask(with: request) {
            data, response, error in
            responseData = data
            responseError = error
            statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 50) == .timedOut {
            throw SaveError.timeout
        }
        if let responseError {
            throw responseError
        }
        guard let responseData else {
            throw SaveError.invalidResponse
        }
        let object = try JSONSerialization.jsonObject(with: responseData)
        guard let json = object as? [String: Any] else {
            throw SaveError.invalidResponse
        }
        if statusCode >= 200 && statusCode < 300, json["ok"] as? Bool == true {
            let created = json["createdFolderIds"] as? [Any] ?? []
            return created.count
        }
        let message = (json["message"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw SaveError.server(
            message?.isEmpty == false
                ? message!
                : "Salvataggio non riuscito."
        )
    }

    @objc private func closeExtension() {
        discardAllDrafts()
        extensionContext?.completeRequest(returningItems: nil)
    }

    private enum SaveError: LocalizedError {
        case authRequired
        case invalidEndpoint
        case invalidResponse
        case timeout
        case server(String)

        var errorDescription: String? {
            switch self {
            case .authRequired:
                return "Apri SaveIn! e resta connesso, poi riprova."
            case .invalidEndpoint:
                return "Endpoint di salvataggio non valido."
            case .invalidResponse:
                return "Risposta server non valida."
            case .timeout:
                return "Timeout di salvataggio. Riprova."
            case .server(let message):
                return message
            }
        }
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
            : (isDraft(folder)
                ? "Temporanea"
                : (folder.level == 0 ? nil : folder.displayPath))
        cell.indentationLevel = folder.isDefault ? 0 : folder.level
        cell.indentationWidth = 18
        let isSelected = selectedFolder?.id == folder.id
        cell.backgroundColor = isSelected
            ? view.tintColor.withAlphaComponent(0.12)
            : .secondarySystemGroupedBackground
        cell.textLabel?.font = isSelected
            ? .preferredFont(forTextStyle: .headline)
            : .preferredFont(forTextStyle: .body)

        let accessoryStack = UIStackView()
        accessoryStack.axis = .horizontal
        accessoryStack.alignment = .center
        accessoryStack.spacing = 10
        accessoryStack.frame = CGRect(
            x: 0,
            y: 0,
            width: isSelected ? 70 : 36,
            height: 36
        )
        if isSelected {
            let checkmark = UIImageView(
                image: UIImage(systemName: "checkmark")
            )
            checkmark.tintColor = view.tintColor
            checkmark.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
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
        NSLayoutConstraint.activate([
            addButton.widthAnchor.constraint(equalToConstant: 30),
            addButton.heightAnchor.constraint(equalToConstant: 30),
        ])
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
        discardAbandonedDrafts(keepingPathTo: folder)
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
