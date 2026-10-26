import SwiftUI

@main
struct FMChatApp: App {
    @StateObject private var chatStore = ChatStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(chatStore)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 1100, height: 760)
    }
}
