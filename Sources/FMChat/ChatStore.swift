import Combine
import Foundation
import FoundationModels
import ImageIO

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var conversations: [Conversation]
    @Published var selectedConversationID: UUID?
    @Published var draft = ""
    @Published private(set) var isGenerating = false
    @Published private(set) var availabilityMessage: String?
    @Published var errorMessage: String?
    @Published private(set) var pendingAttachments: [ChatAttachment] = []
    @Published private(set) var isImporting = false

    private var activeSession: LanguageModelSession?
    private var activeSessionConversationID: UUID?
    private var generationTask: Task<Void, Never>?
    private var generationID: UUID?
    private var pendingImportID: UUID?
    private let model = SystemLanguageModel.default
    private let fileURL: URL
    private var attachmentsDirectory: URL { fileURL.deletingLastPathComponent().appendingPathComponent("attachments", isDirectory: true) }
    private let maxAttachmentCount = 4

    var selectedConversation: Conversation? {
        conversations.first { $0.id == selectedConversationID }
    }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("FMChat", isDirectory: true)
        fileURL = directory.appendingPathComponent("conversations.json")

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = saved.sorted { $0.updatedAt > $1.updatedAt }
            selectedConversationID = conversations.first?.id
        } else {
            conversations = []
            selectedConversationID = nil
        }

        refreshAvailability()
    }

    func newConversation() {
        stop()
        clearPendingAttachments()
        let conversation = Conversation(title: "新しいチャット")
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        draft = ""
        errorMessage = nil
        persist()
    }

    func selectConversation(_ id: UUID) {
        guard conversations.contains(where: { $0.id == id }) else { return }
        stop()
        clearPendingAttachments()
        selectedConversationID = id
        draft = ""
        errorMessage = nil
        activeSession = nil
        activeSessionConversationID = nil
    }

    func deleteConversation(_ id: UUID) {
        let deleted = conversations.first { $0.id == id }
        if selectedConversationID == id {
            stop()
            clearPendingAttachments()
            selectedConversationID = nil
            activeSession = nil
            activeSessionConversationID = nil
        }
        conversations.removeAll { $0.id == id }
        deleted?.messages.flatMap { $0.attachments ?? [] }.forEach(removeStoredAttachment)
        if selectedConversationID == nil {
            selectedConversationID = conversations.first?.id
        }
        persist()
    }

    func addImages(_ urls: [URL]) {
        guard !urls.isEmpty, !isImporting else { return }
        guard #available(macOS 27.0, *) else {
            errorMessage = "画像入力にはmacOS 27以降が必要です。"
            return
        }
        let remaining = maxAttachmentCount - pendingAttachments.count
        guard remaining > 0 else {
            errorMessage = "一度に追加できる画像は最大4枚です。"
            return
        }

        isImporting = true
        errorMessage = nil
        let selectedURLs = Array(urls.prefix(remaining))
        let destination = attachmentsDirectory
        let importID = UUID()
        let conversationID = selectedConversationID
        pendingImportID = importID
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = ImageImporter.copy(selectedURLs, to: destination)
            await MainActor.run {
                guard let self else { return }
                guard self.pendingImportID == importID, self.selectedConversationID == conversationID else {
                    result.attachments.forEach(self.removeStoredAttachment)
                    if self.pendingImportID == importID {
                        self.pendingImportID = nil
                        self.isImporting = false
                    }
                    return
                }
                self.pendingAttachments.append(contentsOf: result.attachments)
                self.pendingImportID = nil
                self.isImporting = false
                if !result.errors.isEmpty {
                    self.errorMessage = result.errors.joined(separator: "\n")
                }
            }
        }
    }

    func removePendingAttachment(_ id: UUID) {
        guard let index = pendingAttachments.firstIndex(where: { $0.id == id }) else { return }
        let attachment = pendingAttachments.remove(at: index)
        removeStoredAttachment(attachment)
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!text.isEmpty || !pendingAttachments.isEmpty), !isGenerating, !isImporting else { return }
        guard availabilityMessage == nil else {
            errorMessage = availabilityMessage
            return
        }

        let prompt = text.isEmpty && !pendingAttachments.isEmpty ? "この画像の内容を説明してください。" : text
        let attachments = pendingAttachments.isEmpty ? nil : pendingAttachments

        if selectedConversationID == nil {
            let conversation = Conversation(title: "新しいチャット")
            conversations.insert(conversation, at: 0)
            selectedConversationID = conversation.id
        }
        guard let conversationID = selectedConversationID,
              let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }) else { return }

        draft = ""
        errorMessage = nil

        if conversations[conversationIndex].messages.isEmpty {
            conversations[conversationIndex].title = String((text.isEmpty ? "画像について" : text).prefix(36))
        }
        conversations[conversationIndex].messages.append(ChatMessage(role: .user, content: prompt, attachments: attachments))
        let assistantID = UUID()
        conversations[conversationIndex].messages.append(ChatMessage(id: assistantID, role: .assistant, content: ""))
        conversations[conversationIndex].updatedAt = Date()
        pendingAttachments = []
        persist()

        let currentGenerationID = UUID()
        generationID = currentGenerationID
        isGenerating = true

        generationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generationID == currentGenerationID {
                    self.isGenerating = false
                    self.generationTask = nil
                    self.generationID = nil
                }
            }

            do {
                let session: LanguageModelSession
                if self.activeSessionConversationID == conversationID, let activeSession = self.activeSession {
                    session = activeSession
                } else {
                    guard let currentConversation = self.conversations.first(where: { $0.id == conversationID }) else { return }
                    let history = currentConversation.messages.dropLast(2)
                    session = LanguageModelSession(model: self.model, transcript: try Self.transcript(from: Array(history)))
                    self.activeSession = session
                    self.activeSessionConversationID = conversationID
                }

                let stream: LanguageModelSession.ResponseStream<String>
                if #available(macOS 27.0, *), let attachments, !attachments.isEmpty {
                    stream = session.streamResponse {
                        prompt
                        for attachment in attachments {
                            Attachment<ImageAttachmentContent>(imageURL: attachment.url)
                        }
                    }
                } else {
                    stream = session.streamResponse(to: prompt)
                }
                for try await snapshot in stream {
                    guard self.generationID == currentGenerationID else { return }
                    self.setMessage(id: assistantID, in: conversationID, content: snapshot.content)
                }
                guard self.generationID == currentGenerationID else { return }
                self.touchConversation(conversationID)
                self.persist()
            } catch is CancellationError {
                // Keep any partial response so the user can see what was generated.
                self.persist()
            } catch {
                guard self.generationID == currentGenerationID else { return }
                self.errorMessage = error.localizedDescription
                self.activeSession = nil
                self.activeSessionConversationID = nil
                self.persist()
            }
        }
    }

    func stop() {
        generationID = nil
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        activeSession = nil
        activeSessionConversationID = nil
        persist()
    }

    private func refreshAvailability() {
        switch model.availability {
        case .available:
            availabilityMessage = nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                availabilityMessage = "このMacではApple Intelligenceを利用できません。"
            case .appleIntelligenceNotEnabled:
                availabilityMessage = "システム設定でApple Intelligenceを有効にしてください。"
            case .modelNotReady:
                availabilityMessage = "Apple Intelligenceのモデルを準備中です。しばらくしてからもう一度お試しください。"
            @unknown default:
                availabilityMessage = "Apple Intelligenceを利用できません。"
            }
        }
    }

    private func setMessage(id: UUID, in conversationID: UUID, content: String) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == id }) else { return }
        conversations[conversationIndex].messages[messageIndex].content = content
        conversations[conversationIndex].updatedAt = Date()
    }

    private func touchConversation(_ id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].updatedAt = Date()
        conversations.sort { $0.updatedAt > $1.updatedAt }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(conversations)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            errorMessage = "チャット履歴を保存できませんでした: \(error.localizedDescription)"
        }
    }

    private static func transcript(from messages: [ChatMessage]) throws -> Transcript {
        let entries: [Transcript.Entry] = messages.compactMap { message in
            guard !message.content.isEmpty else { return nil }
            var segments: [Transcript.Segment] = [.text(.init(content: message.content))]
            if #available(macOS 27.0, *) {
                for attachment in message.attachments ?? [] {
                    segments.append(.attachment(.init(content: .image(.init(imageURL: attachment.url)), label: attachment.fileName)))
                }
            }
            switch message.role {
            case .user:
                return .prompt(.init(segments: segments))
            case .assistant:
                return .response(.init(assetIDs: [], segments: segments))
            }
        }
        return Transcript(entries: entries)
    }

    private func clearPendingAttachments() {
        pendingImportID = nil
        isImporting = false
        pendingAttachments.forEach(removeStoredAttachment)
        pendingAttachments = []
    }

    private func removeStoredAttachment(_ attachment: ChatAttachment) {
        try? FileManager.default.removeItem(at: attachment.url)
    }
}

private enum ImageImporter {
    static let maximumFileSize = 20 * 1024 * 1024

    static func copy(_ urls: [URL], to directory: URL) -> (attachments: [ChatAttachment], errors: [String]) {
        var attachments: [ChatAttachment] = []
        var errors: [String] = []
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return ([], ["画像の保存先を作成できませんでした: \(error.localizedDescription)"])
        }

        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                guard let size = values.fileSize, size <= maximumFileSize else {
                    errors.append("\(url.lastPathComponent): 画像は20MB以下にしてください。")
                    continue
                }
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      CGImageSourceGetCount(source) > 0,
                      CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
                    errors.append("\(url.lastPathComponent): 有効な画像ファイルではありません。")
                    continue
                }

                let id = UUID()
                let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension
                let destination = directory.appendingPathComponent(id.uuidString).appendingPathExtension(ext)
                try FileManager.default.copyItem(at: url, to: destination)
                attachments.append(ChatAttachment(id: id, fileName: url.lastPathComponent, filePath: destination.path))
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (attachments, errors)
    }
}
