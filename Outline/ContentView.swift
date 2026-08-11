import SwiftUI

struct ContentView: View {
    @State private var store = SessionStore()

    var body: some View {
        NavigationStack {
            ConnectionView(store: store)
        }
        .id(store.isConnected)
        .task {
            await store.restore()
        }
    }
}

#Preview {
    ContentView()
}
