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
        view.backgroundColor = ShareCanvascopePalette.background

        let panelView = UIView()
        panelView.backgroundColor = ShareCanvascopePalette.surfaceElevated
        panelView.layer.cornerRadius = 28
        panelView.layer.cornerCurve = .continuous
        panelView.layer.borderColor = ShareCanvascopePalette.edgeStroke.cgColor
        panelView.layer.borderWidth = 1
        panelView.layer.shadowColor = ShareCanvascopePalette.shadow.cgColor
        panelView.layer.shadowOpacity = 1
        panelView.layer.shadowRadius = 22
        panelView.layer.shadowOffset = CGSize(width: 0, height: 14)
        panelView.translatesAutoresizingMaskIntoConstraints = false

        let markLabel = UILabel()
        markLabel.text = "C"
        markLabel.font = .systemFont(ofSize: 24, weight: .bold)
        markLabel.textAlignment = .center
        markLabel.textColor = ShareCanvascopePalette.textPrimary

        let markView = UIView()
        markView.backgroundColor = ShareCanvascopePalette.accent
        markView.layer.cornerRadius = 16
        markView.layer.cornerCurve = .continuous
        markView.layer.borderColor = ShareCanvascopePalette.innerHighlight.cgColor
        markView.layer.borderWidth = 1
        markView.translatesAutoresizingMaskIntoConstraints = false
        markLabel.translatesAutoresizingMaskIntoConstraints = false
        markView.addSubview(markLabel)

        let titleLabel = UILabel()
        titleLabel.text = "Send to Canvascope"
        titleLabel.font = .preferredFont(forTextStyle: .title3)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.textColor = ShareCanvascopePalette.textPrimary

        statusLabel.text = "Preparing..."
        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textAlignment = .center
        statusLabel.textColor = ShareCanvascopePalette.textSecondary
        statusLabel.numberOfLines = 0

        var doneButtonConfiguration = UIButton.Configuration.plain()
        doneButtonConfiguration.title = "Done"
        doneButtonConfiguration.baseForegroundColor = ShareCanvascopePalette.textPrimary
        doneButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(
            top: 10,
            leading: 18,
            bottom: 10,
            trailing: 18
        )
        doneButtonConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .preferredFont(forTextStyle: .headline)
            return outgoing
        }

        var doneButtonBackground = UIBackgroundConfiguration.clear()
        doneButtonBackground.backgroundColor = ShareCanvascopePalette.surfaceFloating
        doneButtonBackground.cornerRadius = 13
        doneButtonBackground.strokeColor = ShareCanvascopePalette.edgeStroke
        doneButtonBackground.strokeWidth = 1
        doneButtonConfiguration.background = doneButtonBackground

        doneButton.configuration = doneButtonConfiguration
        doneButton.layer.cornerCurve = .continuous
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.isHidden = true

        activityIndicator.startAnimating()
        activityIndicator.color = ShareCanvascopePalette.accentSoft

        let statusStack = UIStackView(arrangedSubviews: [activityIndicator, statusLabel])
        statusStack.axis = .vertical
        statusStack.spacing = 10
        statusStack.alignment = .center

        let stack = UIStackView(arrangedSubviews: [markView, titleLabel, statusStack, doneButton])
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        statusLabel.setContentHuggingPriority(.required, for: .vertical)

        panelView.addSubview(stack)
        view.addSubview(panelView)

        NSLayoutConstraint.activate([
            panelView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            panelView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            panelView.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            stack.leadingAnchor.constraint(equalTo: panelView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: panelView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: panelView.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: panelView.bottomAnchor, constant: -28),

            markView.widthAnchor.constraint(equalToConstant: 54),
            markView.heightAnchor.constraint(equalToConstant: 54),
            markLabel.centerXAnchor.constraint(equalTo: markView.centerXAnchor),
            markLabel.centerYAnchor.constraint(equalTo: markView.centerYAnchor)
        ])
    }

    @MainActor
    private func setStatus(_ text: String, isError: Bool = false, isWorking: Bool = true) {
        statusLabel.text = text
        statusLabel.textColor = isError
            ? ShareCanvascopePalette.destructive
            : ShareCanvascopePalette.textSecondary
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
            setStatus("Checking Canvascope account...")
            try await dropBridgeService.assertAuthenticated()

            setStatus("Reading shared file...")
            let fileURL = try await resolveSharedFileURL()

            setStatus("Sending to Canvascope...")
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

        // Brief beat so the success state registers, then dismiss promptly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
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

private enum ShareCanvascopePalette {
    static let background = UIColor(red: 0.051, green: 0.039, blue: 0.035, alpha: 1.0)
    static let surfaceElevated = UIColor(red: 0.106, green: 0.075, blue: 0.071, alpha: 0.94)
    static let surfaceFloating = UIColor(red: 0.090, green: 0.063, blue: 0.059, alpha: 0.96)
    static let accent = UIColor(red: 0.878, green: 0.145, blue: 0.125, alpha: 1.0)
    static let accentSoft = UIColor(red: 1.0, green: 0.416, blue: 0.361, alpha: 1.0)
    static let destructive = UIColor(red: 1.0, green: 0.478, blue: 0.455, alpha: 1.0)
    static let textPrimary = UIColor(red: 0.965, green: 0.945, blue: 0.906, alpha: 1.0)
    static let textSecondary = UIColor(red: 0.851, green: 0.824, blue: 0.769, alpha: 1.0)
    static let edgeStroke = UIColor(red: 0.965, green: 0.945, blue: 0.906, alpha: 0.16)
    static let innerHighlight = UIColor(red: 0.965, green: 0.945, blue: 0.906, alpha: 0.10)
    static let shadow = UIColor(red: 0.020, green: 0.014, blue: 0.012, alpha: 0.36)
}
