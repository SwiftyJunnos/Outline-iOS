import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            Text("Outline")
                .font(.largeTitle.bold())
                .navigationTitle("Outline")
        }
    }
}

#Preview {
    ContentView()
}
