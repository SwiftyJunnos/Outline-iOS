import SwiftUI

struct ZoomableMediaViewer<Content: View, Background: View>: View {
    @Environment(\.dismiss) private var dismiss

    private let accessibilityName: String
    private let content: Content
    private let background: Background

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var magnification: CGFloat = 1
    @GestureState private var translation: CGSize = .zero

    init(
        accessibilityName: String,
        @ViewBuilder background: () -> Background,
        @ViewBuilder content: () -> Content
    ) {
        self.accessibilityName = accessibilityName
        self.background = background()
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let displayedScale = clampedScale(scale * magnification)
            let displayedOffset = clampedOffset(
                translated(offset, by: translation),
                scale: displayedScale,
                size: geometry.size
            )

            ZStack {
                Color.black
                    .ignoresSafeArea()
                    .overlay {
                        background
                            .frame(
                                width: geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing,
                                height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
                            )
                            .offset(
                                x: (geometry.safeAreaInsets.trailing - geometry.safeAreaInsets.leading) / 2,
                                y: (geometry.safeAreaInsets.bottom - geometry.safeAreaInsets.top) / 2
                            )
                            .clipped()
                            .ignoresSafeArea()
                    }

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(displayedScale)
                    .offset(displayedOffset)
                    .contentShape(Rectangle())
                    .accessibilityLabel(accessibilityName)
                    .accessibilityHint("Use the zoom controls to enlarge the content")
                    .gesture(magnificationGesture(in: geometry.size))
                    .simultaneousGesture(panGesture(in: geometry.size))
                    .onTapGesture(count: 2) {
                        setScale(scale > 1 ? 1 : 2, in: geometry.size)
                    }

                VStack {
                    HStack {
                        Spacer()
                        controlButton("xmark", label: "Close viewer") { dismiss() }
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        controlButton("minus.magnifyingglass", label: "Zoom out") {
                            setScale(scale - 1, in: geometry.size)
                        }
                        .disabled(scale <= 1)

                        controlButton("arrow.counterclockwise", label: "Reset zoom") {
                            setScale(1, in: geometry.size)
                        }
                        .disabled(scale == 1 && offset == .zero)

                        controlButton("plus.magnifyingglass", label: "Zoom in") {
                            setScale(scale + 1, in: geometry.size)
                        }
                        .disabled(scale >= 8)
                    }
                }
                .padding()
            }
        }
    }

    private func magnificationGesture(in size: CGSize) -> some Gesture {
        MagnificationGesture()
            .updating($magnification) { value, state, _ in state = value }
            .onEnded { value in setScale(scale * value, in: size) }
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .updating($translation) { value, state, _ in
                if scale > 1 { state = value.translation }
            }
            .onEnded { value in
                guard scale > 1 else { return }
                offset = clampedOffset(translated(offset, by: value.translation), scale: scale, size: size)
            }
    }

    private func setScale(_ proposedScale: CGFloat, in size: CGSize) {
        scale = clampedScale(proposedScale)
        offset = clampedOffset(offset, scale: scale, size: size)
    }

    private func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, 1), 8)
    }

    private func clampedOffset(_ offset: CGSize, scale: CGFloat, size: CGSize) -> CGSize {
        guard scale > 1 else { return .zero }
        let horizontalLimit = size.width * (scale - 1) / 2
        let verticalLimit = size.height * (scale - 1) / 2
        return CGSize(
            width: min(max(offset.width, -horizontalLimit), horizontalLimit),
            height: min(max(offset.height, -verticalLimit), verticalLimit)
        )
    }

    private func translated(_ offset: CGSize, by translation: CGSize) -> CGSize {
        CGSize(width: offset.width + translation.width, height: offset.height + translation.height)
    }

    private func controlButton(
        _ systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(.thinMaterial, in: Circle())
        .accessibilityLabel(label)
    }
}

extension View {
    @ViewBuilder
    func mediaViewerCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #elseif os(macOS)
        sheet(isPresented: isPresented, content: content)
        #endif
    }
}
