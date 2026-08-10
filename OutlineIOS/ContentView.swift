import SwiftUI

struct ContentView: View {
    @State private var store = SessionStore()

    var body: some View {
        NavigationStack {
            ConnectionView(store: store)
        }
        .task {
            await store.restore()
        }
    }
}

#Preview {
    ContentView()
}
