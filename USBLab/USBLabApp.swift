import SwiftUI

@main
struct USBLabApp: App {
    @State private var showingAbout = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .sheet(isPresented: $showingAbout) {
                    AboutView(showing: $showingAbout)
                }
        }
        .commands {
            // Reemplaza el menú estándar "About"
            CommandGroup(replacing: .appInfo) {
                Button("Acerca de USBLab") {
                    showingAbout = true
                }
            }
        }
    }
}
