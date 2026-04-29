import SwiftUI

@main
struct MLXWhisperAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .commands {
            SidebarCommands()
        }
    }
}
