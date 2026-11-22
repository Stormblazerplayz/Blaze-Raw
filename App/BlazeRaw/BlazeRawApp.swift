import SwiftUI

enum AppTab: Hashable {
    case create, library, about
}

/// Lets one screen jump to another (for example "Remix" in the library opens Create).
@MainActor
final class Router: ObservableObject {
    @Published var tab: AppTab = .create
}

@main
struct BlazeRawApp: App {
    @StateObject private var library = SongLibrary()
    @StateObject private var player = AudioPlayerModel()
    @StateObject private var generator = GeneratorModel()
    @StateObject private var router = Router()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(generator)
                .environmentObject(router)
                .preferredColorScheme(.dark)
                .tint(Theme.orange)
        }
    }
}
