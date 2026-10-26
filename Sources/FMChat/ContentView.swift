import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var showingImageImporter = false
    @State private var imageImportError: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 255)

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)

            conversationArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                Text("FM Chat")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            .padding(.top, 8)

            Button(action: store.newConversation) {
                Label("新しいチャット", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            VStack(alignment: .leading, spacing: 8) {
                Text("最近のチャット")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)

                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(store.conversations) { conversation in
                            conversationRow(conversation)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Image(systemName: "apple.logo")
                Text("Apple Foundation Models")
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .padding(16)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        let isSelected = store.selectedConversationID == conversation.id

        return Button {
            store.selectConversation(conversation.id)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(conversation.title.isEmpty ? "新しいチャット" : conversation.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isSelected ? Color.primary.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("チャットを削除", role: .destructive) {
                store.deleteConversation(conversation.id)
            }
        }
    }

    private var conversationArea: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.selectedConversation?.title ?? "FM Chat")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if store.isGenerating {
                    Label("生成中", systemImage: "circle.dotted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 52)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
            }

            if let availabilityMessage = store.availabilityMessage {
                Label(availabilityMessage, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 760, alignment: .leading)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 16)
            }

            if let conversation = store.selectedConversation, !conversation.messages.isEmpty {
                messageList(conversation)
            } else {
                welcome
            }

            if let errorMessage = store.errorMessage ?? imageImportError {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }

            composer
        }
    }

    private func messageList(_ conversation: Conversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(conversation.messages) { message in
                        messageView(message)
                            .id(message.id)
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 30)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: conversation.messages.count) { _, _ in
                scrollToLatestMessage(in: conversation, using: proxy)
            }
            .onChange(of: conversation.messages.last?.content) { _, _ in
                scrollToLatestMessage(in: conversation, using: proxy)
            }
        }
    }

    private func scrollToLatestMessage(in conversation: Conversation, using proxy: ScrollViewProxy) {
        guard let lastMessage = conversation.messages.last else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }

    private func messageView(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user

        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: isUser ? "person.fill" : "sparkle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isUser ? Color.primary : Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 5) {
                Text(isUser ? "あなた" : "FM Chat")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(message.content.isEmpty && !isUser ? " " : message.content)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let attachments = message.attachments, !attachments.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 190), alignment: .leading)],
                              alignment: .leading, spacing: 8) {
                        ForEach(attachments) { attachment in
                            attachmentCard(attachment, removable: false)
                        }
                    }
                    .padding(.top, 5)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var welcome: some View {
        VStack(spacing: 15) {
            Image(systemName: "sparkle")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 58, height: 58)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))

            Text("今日は何をお手伝いしましょうか？")
                .font(.system(size: 23, weight: .semibold))
            Text("Apple Foundation Models と会話できます。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !store.pendingAttachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(store.pendingAttachments) { attachment in
                            attachmentCard(attachment, removable: true)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, 5)
                .padding(.top, 5)
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    showingImageImporter = true
                } label: {
                    Group {
                        if store.isImporting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "paperclip")
                                .font(.system(size: 15, weight: .medium))
                        }
                    }
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!supportsImageInput || store.isImporting || store.isGenerating)
                .help(imagePickerHelp)

                TextField("メッセージを入力…", text: $store.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .font(.system(size: 14))
                    .padding(.vertical, 11)
                    .onSubmit(store.send)
                    .disabled(store.isGenerating)

                if store.isGenerating {
                    Button(action: store.stop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.primary.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .help("生成を停止")
                    .padding(5)
                } else {
                    Button(action: store.send) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(canSend ? Color.accentColor : Color.secondary.opacity(0.35),
                                        in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!canSend)
                    .help("送信 (⌘↩)")
                    .padding(5)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 12, y: 3)
        .frame(maxWidth: 760)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .fileImporter(isPresented: $showingImageImporter,
                      allowedContentTypes: [.image],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                imageImportError = nil
                store.addImages(urls)
            case .failure(let error):
                imageImportError = "画像を開けませんでした: \(error.localizedDescription)"
            }
        }
    }

    private func attachmentCard(_ attachment: ChatAttachment, removable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topTrailing) {
                attachmentPreview(attachment)
                    .frame(width: 112, height: 74)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if removable {
                    Button {
                        store.removePendingAttachment(attachment.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(.black.opacity(0.7), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("画像を削除")
                    .padding(4)
                }
            }

            Text(attachment.fileName)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 112, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func attachmentPreview(_ attachment: ChatAttachment) -> some View {
        if let image = NSImage(contentsOf: attachment.url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color.primary.opacity(0.06)
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var canSend: Bool {
        (!store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !store.pendingAttachments.isEmpty)
            && !store.isGenerating
            && !store.isImporting
            && store.availabilityMessage == nil
    }

    private var supportsImageInput: Bool {
        if #available(macOS 27.0, *) { return true }
        return false
    }

    private var imagePickerHelp: String {
        supportsImageInput ? "画像を添付" : "画像入力は macOS 27 以降で利用できます"
    }
}
