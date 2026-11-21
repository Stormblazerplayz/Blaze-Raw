import SwiftUI

struct RootView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var player: AudioPlayerModel

    var body: some View {
        TabView(selection: $router.tab) {
            CreateView()
                .tabItem { Label("Create", systemImage: "slider.horizontal.3") }
                .tag(AppTab.create)
            LibraryView()
                .tabItem { Label("My Songs", systemImage: "music.note.list") }
                .tag(AppTab.library)
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(AppTab.about)
        }
        .alert("Oops", isPresented: playerErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(player.errorMessage ?? "")
        }
    }

    private var playerErrorBinding: Binding<Bool> {
        Binding(
            get: { player.errorMessage != nil },
            set: { if !$0 { player.errorMessage = nil } }
        )
    }
}
