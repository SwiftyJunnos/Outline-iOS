import SwiftUI

struct ConnectionView: View {
    @Bindable var store: SessionStore

    @State private var serverURL = ""
    @State private var apiKey = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case serverURL
        case apiKey
    }

    var body: some View {
        Form {
            switch store.state {
            case .disconnected, .connecting:
                connectionForm
            case let .connected(serverURL, collections):
                connectedContent(serverURL: serverURL, collections: collections)
            }
        }
        .navigationTitle("Outline")
    }

    @ViewBuilder
    private var connectionForm: some View {
        Section("Connection") {
            LabeledContent("Server URL") {
                TextField("https://outline.example.com", text: $serverURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .serverURL)
                    .onSubmit { focusedField = .apiKey }
                    .accessibilityLabel("Server URL")
            }

            LabeledContent("API key") {
                SecureField("Paste API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focusedField, equals: .apiKey)
                    .onSubmit(connect)
                    .accessibilityLabel("API key")
            }
        }
        .disabled(store.isConnecting)

        errorContent

        Section {
            Button(action: connect) {
                if store.isConnecting {
                    HStack {
                        ProgressView()
                        Text("Connecting…")
                    }
                } else {
                    Text("Connect")
                }
            }
            .disabled(store.isConnecting)
            .accessibilityLabel(store.isConnecting ? "Connecting" : "Connect")
        }
    }

    @ViewBuilder
    private func connectedContent(serverURL: URL, collections: [OutlineCollection]) -> some View {
        Section("Connected server") {
            LabeledContent("Server URL") {
                Text(serverURL.absoluteString)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }

        Section("Collections") {
            if collections.isEmpty {
                Text("No collections found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(collections, id: \.id) { collection in
                    Text(collection.name)
                }
            }
        }

        errorContent

        Section {
            Button("Disconnect", action: store.disconnect)
        }
    }

    @ViewBuilder
    private var errorContent: some View {
        if let errorMessage = store.errorMessage {
            Section {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Error. \(errorMessage)")
            }
        }
    }

    private func connect() {
        guard !store.isConnecting else { return }

        Task {
            await store.connect(serverURL: serverURL, token: apiKey)
            if case .connected = store.state {
                apiKey = ""
                focusedField = nil
            }
        }
    }
}
