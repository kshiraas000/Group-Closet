import SwiftUI

struct PhotoCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onCrop: (UIImage) -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let cropDiameter: CGFloat = 280

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: cropDiameter, height: cropDiameter)
                .scaleEffect(scale)
                .offset(offset)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .contentShape(Circle())
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = max(1, lastScale * value)
                                offset = clampedOffset(offset)
                            }
                            .onEnded { _ in
                                lastScale = scale
                                offset = clampedOffset(offset)
                                lastOffset = offset
                            },
                        DragGesture()
                            .onChanged { value in
                                offset = clampedOffset(CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                ))
                            }
                            .onEnded { _ in lastOffset = offset }
                    )
                )

            Spacer()

            Text("Drag to reposition, pinch to zoom")
                .font(Theme.Font.body(13))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .top) {
            HStack {
                Button("Cancel", action: onCancel)
                    .foregroundStyle(.white)
                Spacer()
                Text("Move and Scale")
                    .font(Theme.Font.body(15, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                Button("Use Photo") {
                    onCrop(renderCroppedImage())
                }
                .foregroundStyle(.white)
                .fontWeight(.semibold)
            }
            .font(Theme.Font.body(16))
            .padding(.horizontal, 20)
            .padding(.top, UIApplication.keyWindowSafeAreaInsets.top + 12)
            .padding(.bottom, 12)
            .background(Color.black)
        }
    }

    private func clampedOffset(_ proposed: CGSize) -> CGSize {
        let maxOffset = cropDiameter * (scale - 1) / 2
        return CGSize(
            width: min(max(proposed.width, -maxOffset), maxOffset),
            height: min(max(proposed.height, -maxOffset), maxOffset)
        )
    }

    private func renderCroppedImage() -> UIImage {
        let renderSize: CGFloat = 600
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: renderSize, height: renderSize))
        return renderer.image { _ in
            let scaleFactor = renderSize / cropDiameter
            let imageSize = image.size
            let fillScale = max(cropDiameter / imageSize.width, cropDiameter / imageSize.height) * scale
            let drawWidth = imageSize.width * fillScale * scaleFactor
            let drawHeight = imageSize.height * fillScale * scaleFactor
            let drawX = (renderSize - drawWidth) / 2 + offset.width * scaleFactor
            let drawY = (renderSize - drawHeight) / 2 + offset.height * scaleFactor
            image.draw(in: CGRect(x: drawX, y: drawY, width: drawWidth, height: drawHeight))
        }
    }
}
