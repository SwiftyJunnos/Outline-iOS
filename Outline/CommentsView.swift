import Foundation
import OutlineCore
import SwiftUI

private let fractionalCommentTimestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
private let commentTimestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

struct CommentsView: View {
    let store: SessionStore
    let documentID: String
    let documentURL: URL?

    @Environment(\.dismiss) private var dismiss

    @State private var loadState = LoadState.loading
    @State private var loadRequest = 0
    @State private var draft = ""
    @State private var isSubmitting = false
    @State private var errorAlert: CommentsAlert?

    private let characterLimit = 1_000

    var body: some View {
        NavigationStack {
            Group {
                switch loadState {
                case .loading:
                    ProgressView("Loading comments…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .loaded(comments):
                    commentsList(comments)
                case let .failed(notice):
                    ContentUnavailableView {
                        Label("Unable to load comments", systemImage: "exclamationmark.circle")
                    } description: {
                        Text(notice.message)
                    } actions: {
                        if notice.recovery == .reconnect {
                            Button("Reconnect", action: store.disconnect)
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button("Try again") {
                                loadRequest += 1
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            .task(id: loadRequest) {
                _ = await loadComments()
            }
            .alert(item: $errorAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.notice.message),
                    primaryButton: alert.notice.recovery == .reconnect
                        ? .destructive(Text("Reconnect"), action: store.disconnect)
                        : .default(Text("Try again")) { retry(alert.operation) },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private func commentsList(_ comments: [OutlineComment]) -> some View {
        List(comments) { comment in
            CommentRow(comment: comment, documentURL: documentURL, store: store)
        }
        .listStyle(.plain)
        .overlay {
            if comments.isEmpty {
                ContentUnavailableView(
                    "No comments yet",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Start the conversation below.")
                )
                .allowsHitTesting(false)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            if let notice = await loadComments(showLoading: false) {
                errorAlert = CommentsAlert(operation: .refresh, notice: notice)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Add a comment")
                    .font(.headline)
                Spacer(minLength: 8)
                Text("\(draft.count)/\(characterLimit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Character count")
                    .accessibilityValue("\(draft.count) of \(characterLimit)")
            }

            TextEditor(text: $draft)
                .frame(minHeight: 96, maxHeight: 160)
                .padding(4)
                .scrollContentBackground(.hidden)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                }
                .disabled(isSubmitting)
                .accessibilityLabel("Comment")
                .accessibilityHint("Enter up to 1,000 characters")
                .onChange(of: draft) { _, value in
                    if value.count > characterLimit {
                        draft = String(value.prefix(characterLimit))
                    }
                }

            HStack {
                Spacer()
                Button(action: submitComment) {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityHidden(true)
                        }
                        Text(isSubmitting ? "Posting…" : "Post")
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting || trimmedDraft.isEmpty)
                .accessibilityLabel(isSubmitting ? "Posting comment" : "Post comment")
                .accessibilityValue(isSubmitting ? "In progress" : "")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadComments(showLoading: Bool = true) async -> SessionErrorNotice? {
        if showLoading {
            loadState = .loading
        }

        do {
            loadState = .loaded(try await store.comments(in: documentID))
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            let notice = SessionErrorNotice(error: error)
            if showLoading {
                loadState = .failed(notice)
            }
            return notice
        }
    }

    private func submitComment() {
        let text = draft
        guard !trimmedDraft.isEmpty, !isSubmitting else { return }

        isSubmitting = true
        Task { @MainActor in
            defer { isSubmitting = false }
            do {
                let comment = try await store.createComment(in: documentID, text: text)
                if case let .loaded(comments) = loadState {
                    loadState = .loaded(comments + [comment])
                }
                draft = ""
            } catch is CancellationError {
                return
            } catch {
                errorAlert = CommentsAlert(
                    operation: .submit,
                    notice: SessionErrorNotice(error: error)
                )
            }
        }
    }

    private func retry(_ operation: CommentsAlert.Operation) {
        switch operation {
        case .refresh:
            Task { @MainActor in
                if let notice = await loadComments(showLoading: false) {
                    errorAlert = CommentsAlert(operation: .refresh, notice: notice)
                }
            }
        case .submit:
            submitComment()
        }
    }

    private enum LoadState {
        case loading
        case loaded([OutlineComment])
        case failed(SessionErrorNotice)
    }
}

private struct CommentRow: View {
    let comment: OutlineComment
    let documentURL: URL?
    let store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(comment.createdBy.name)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            Text(metadata)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ProseMirrorDocumentView(
                document: OutlineRichDocument(
                    id: comment.id,
                    title: "Comment",
                    url: documentURL?.absoluteString ?? "",
                    data: comment.data
                ),
                baseURL: documentURL,
                assetLoader: { source in
                    try await store.assetData(for: source)
                }
            )
        }
        .padding(.vertical, 4)
    }

    private var metadata: String {
        let timestamp = formattedCommentTimestamp(comment.createdAt)
        return comment.resolvedAt == nil ? timestamp : "\(timestamp) · Resolved"
    }
}

private struct CommentsAlert: Identifiable {
    enum Operation: String {
        case refresh
        case submit
    }

    let operation: Operation
    let notice: SessionErrorNotice

    var id: String {
        "\(operation.rawValue):\(notice.id)"
    }

    var title: String {
        switch operation {
        case .refresh:
            "Unable to refresh"
        case .submit:
            "Unable to post comment"
        }
    }
}

private func formattedCommentTimestamp(_ value: String) -> String {
    let date = (try? fractionalCommentTimestamp.parse(value))
        ?? (try? commentTimestamp.parse(value))
    return date?.formatted(date: .abbreviated, time: .shortened) ?? value
}
