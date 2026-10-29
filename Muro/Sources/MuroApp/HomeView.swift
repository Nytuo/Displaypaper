import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MuroPageBackground()
                VStack(spacing: 0) {
                    hero
                        .frame(height: geometry.size.height * 0.58)
                    Spacer(minLength: 10)
                    recentSection
                        .padding(.horizontal, 48)
                        .padding(.bottom, 22)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - Hero

    @ViewBuilder private var hero: some View {
        if let item = store.heroItem {
            ZStack(alignment: .bottomLeading) {
                // The video and its scrim fade to nothing at the bottom edge,
                // so whatever the page background happens to be there shows
                // through and the hero has no edge at all.
                //
                // It used to fade to a colour instead, and that is what drew a
                // hard line across the window. A colour can only match a
                // background that is flat, and this one is not: the blooms sit
                // behind the hero's bottom edge and shift with the window
                // size, so there is no single value that is ever right.
                // Transparent matches everything, at every size, for free.
                ZStack {
                    heroMedia(item)
                    // Darkening only, for the title and buttons to read
                    // against. Black rather than a background colour, because
                    // this fades out with everything else.
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.15), location: 0),
                            .init(color: .clear, location: 0.35),
                            .init(color: .black.opacity(0.30), location: 0.75),
                            .init(color: .black.opacity(0.45), location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                // Four stops rather than two: a straight ramp still reads as a
                // line where it begins, because the eye finds the point the
                // slope changes. This eases in and then falls away.
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: 0.50),
                            .init(color: .white.opacity(0.82), location: 0.70),
                            .init(color: .white.opacity(0.35), location: 0.88),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                heroContent(item)
                    .padding(.leading, 64)
                    .padding(.bottom, 44)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        } else {
            emptyLibraryHero
        }
    }

    private func heroMedia(_ item: WallpaperItem) -> some View {
        GeometryReader { proxy in
            Group {
                // The hero only ever plays local files: a downloaded master
                // or the bundled 4K. It never streams (owner, 2026-07-19).
                // It also stops while a full screen preview covers it, since
                // Home stays mounted underneath and two 4K decoders would
                // otherwise run at once.
                if let url = store.heroVideoURL(for: item) {
                    LoopingPlayerView(url: url, isActive: store.previewItem == nil)
                } else if let scene = store.sceneDirectory(for: item) {
                    SceneView(directory: scene, isActive: store.previewItem == nil)
                } else {
                    // Hero-sized, so it gets the full decode.
                    ThumbImage(item: item, maxPixels: ImageCache.fullPixels)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private func heroContent(_ item: WallpaperItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FEATURED")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2.4)
                .foregroundStyle(Color.muroAccent)
            Text(item.title)
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 10)
            HStack(spacing: 12) {
                Text(item.metaLine)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.muroSecondary)
                FPSChip(text: item.fps > 40 ? "\(Int(item.fps)) FPS" : "\(item.resolutionLabel) · \(Int(item.fps))")
                if let label = store.appliedChipLabel(for: item.id) {
                    AppliedChip(label: "APPLIED · " + label)
                }
            }
            .padding(.top, 14)
            HStack(spacing: 12) {
                Button {
                    store.openPreview(item)
                } label: {
                    HStack(spacing: 8) {
                        Text("View Wallpaper")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .glassCapsule(fill: 0.12, stroke: 0.2)
                }
                .buttonStyle(.plain)
                HeartButton(item: item, size: 44)
            }
            .padding(.top, 20)
        }
    }

    private var emptyLibraryHero: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 42))
                .foregroundStyle(Color.muroSecondary)
            Text("Your library is empty")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
            Text("Import your own videos with the + button, or browse Explore to download wallpapers.")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.muroSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recently Set")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(store.recentItems.isEmpty ? "Wallpapers you set will appear here" : "\(store.recentItems.count) recent")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.muroSecondary)
            }
            if store.recentItems.isEmpty {
                Text("Wallpapers you apply will appear here.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.muroSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            } else {
                HStack(spacing: 18) {
                    ForEach(Array(store.recentItems.prefix(4))) { item in
                        WallpaperCard(item: item)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

}
