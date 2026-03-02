import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let dropBridgeService = ShareDropBridgeService()

    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let doneButton = UIButton(type: .system)

    private var hasCompleted = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()

        Task {
            await startShareFlow()
        }
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = "Send to Canvascope"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center

        statusLabel.text = "Preparing…"
        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textAlignment = .center
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        doneButton.setTitle("Done", for: .normal)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.isHidden = true

        activityIndicator.startAnimating()

        let stack = UIStackView(arrangedSubviews: [titleLabel, activityIndicator, statusLabel, doneButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        statusLabel.setContentHuggingPriority(.required, for: .vertical)

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @MainActor
    private func setStatus(_ text: String, isError: Bool = false, isWorking: Bool = true) {
        statusLabel.text = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabel
        doneButton.isHidden = isWorking

        if isWorking {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
    }

    @MainActor
    private func startShareFlow() async {
        do {
            setStatus("Checking Lectra account…")
            try await dropBridgeService.assertAuthenticated()

            setStatus("Reading shared file…")
            let fileURL = try await resolveSharedFileURL()

            setStatus("Sending to Canvascope…")
            _ = try await dropBridgeService.uploadSharedFile(fileURL: fileURL)

            setStatus("Sent to Canvascope.", isWorking: false)
            completeAfterDelay()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            setStatus(message, isError: true, isWorking: false)
        }
    }

    private func completeAfterDelay() {
        guard !hasCompleted else { return }
        hasCompleted = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    @objc
    private func doneTapped() {
        guard !hasCompleted else { return }
        hasCompleted = true
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func resolveSharedFileURL() async throws -> URL {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }

        guard !providers.isEmpty else {
            throw ShareDropBridgeError.server("No file received from the share sheet.")
        }

        for provider in providers {
            if let fileURL = try await loadFromFileRepresentation(provider: provider) {
                return fileURL
            }
            if let fileURL = try await loadFromItem(provider: provider) {
                return fileURL
            }
        }

        throw ShareDropBridgeError.server("Could not read the shared file.")
    }

    private func loadFromFileRepresentation(provider: NSItemProvider) async throws -> URL? {
        guard let typeIdentifier = provider.registeredTypeIdentifiers.first else {
            return nil
        }

        if !provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
            return nil
        }

        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] sourceURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sourceURL, let self else {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    let copied = try self.copyIntoTemporaryDirectory(sourceURL: sourceURL, fallbackName: suggestedName)
                    continuation.resume(returning: copied)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func loadFromItem(provider: NSItemProvider) async throws -> URL? {
        let preferredType = preferredTypeIdentifier(for: provider)
        guard let typeIdentifier = preferredType else {
            return nil
        }

        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    if let url = item as? URL {
                        let copied = try self.copyIntoTemporaryDirectory(sourceURL: url, fallbackName: suggestedName)
                        continuation.resume(returning: copied)
                        return
                    }

                    if let data = item as? Data {
                        let fileURL = try self.persistDataToTemporaryFile(
                            data,
                            suggestedName: suggestedName,
                            typeIdentifier: typeIdentifier
                        )
                        continuation.resume(returning: fileURL)
                        return
                    }

                    if let nsData = item as? NSData {
                        let fileURL = try self.persistDataToTemporaryFile(
                            nsData as Data,
                            suggestedName: suggestedName,
                            typeIdentifier: typeIdentifier
                        )
                        continuation.resume(returning: fileURL)
                        return
                    }

                    continuation.resume(returning: nil)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func preferredTypeIdentifier(for provider: NSItemProvider) -> String? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return UTType.fileURL.identifier
        }

        if let itemType = provider.registeredTypeIdentifiers.first(where: { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .item)
        }) {
            return itemType
        }

        return provider.registeredTypeIdentifiers.first
    }

    private func copyIntoTemporaryDirectory(sourceURL: URL, fallbackName: String?) throws -> URL {
        let originalName = sourceURL.lastPathComponent
        let fileName = originalName.isEmpty ? (fallbackName ?? "SharedFile") : originalName

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ShareImport", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let targetURL = tempDir.appendingPathComponent("\(UUID().uuidString)-\(fileName)")

        let needsScopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if needsScopedAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try FileManager.default.copyItem(at: sourceURL, to: targetURL)
        return targetURL
    }

    private func persistDataToTemporaryFile(_ data: Data, suggestedName: String?, typeIdentifier: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ShareImport", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let ext: String = {
            guard let type = UTType(typeIdentifier), let preferredExt = type.preferredFilenameExtension else {
                return "bin"
            }
            return preferredExt
        }()

        let baseName = (suggestedName?.isEmpty == false) ? suggestedName! : "SharedFile"
        let fileName: String
        if URL(fileURLWithPath: baseName).pathExtension.isEmpty {
            fileName = "\(baseName).\(ext)"
        } else {
            fileName = baseName
        }

        let targetURL = tempDir.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
        try data.write(to: targetURL, options: .atomic)
        return targetURL
    }
}
