import CoreLocation
import Photos
import SwiftUI

// MARK: - 路線照片（走路時拍的照片）

struct RoutePhoto: Identifiable {
    let id: String
    let date: Date
    let coordinate: CLLocationCoordinate2D?
    let thumbnail: UIImage
}

@MainActor
enum RoutePhotoLibrary {
    static var canRead: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    static var notAsked: Bool { PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined }

    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// 路線期間（前後各 5 分鐘）拍的照片，照時間排
    static func photos(for route: SavedRoute, limit: Int = 40) async -> [RoutePhoto] {
        await photos(from: route.start.addingTimeInterval(-300), to: route.end.addingTimeInterval(300), limit: limit)
    }

    /// 某段時間拍的照片（足跡日記用：一整天、只要有拍攝地點的）
    static func photos(from start: Date, to end: Date, limit: Int = 40, locatedOnly: Bool = false) async -> [RoutePhoto] {
        guard canRead else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@ AND mediaType == %d",
                                        start as NSDate, end as NSDate, PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.fetchLimit = limit
        var assets: [PHAsset] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            if !locatedOnly || asset.location != nil { assets.append(asset) }
        }
        var photos: [RoutePhoto] = []
        for asset in assets {
            guard let image = await image(for: asset, side: 240) else { continue }
            photos.append(RoutePhoto(id: asset.localIdentifier, date: asset.creationDate ?? start,
                                     coordinate: asset.location?.coordinate, thumbnail: image))
        }
        return photos
    }

    /// 大張的照片（做路線圖用）
    static func fullImage(id: String, side: CGFloat = 1920) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        return await image(for: asset, side: side)
    }

    private static func image(for asset: PHAsset, side: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            // 高畫質模式只會回呼一次；iCloud 上的照片也會下載
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: side, height: side),
                                                  contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

/// 路線詳細頁的照片列
struct RoutePhotoStrip: View {
    let photos: [RoutePhoto]
    var onSelect: (RoutePhoto) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(photos) { photo in
                    Button { onSelect(photo) } label: {
                        Image(uiImage: photo.thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 84, height: 84)
                            .clipped()
                            .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(photo.date.formatted(date: .omitted, time: .shortened)) 拍的照片")
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// 點照片看大張，可以直接做成路線圖
struct RoutePhotoViewer: View {
    let photo: RoutePhoto
    var onMakeCard: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(uiImage: image ?? photo.thumbnail)
                    .resizable()
                    .scaledToFit()
                    .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 3))
                    .frame(maxHeight: .infinity)
                Text(photo.date.formatted(.dateTime.month().day().hour().minute()))
                    .font(.px(12))
                    .foregroundStyle(Color.soft)
                Button("用這張做路線圖") {
                    dismiss()
                    onMakeCard()
                }
                .buttonStyle(.pixel(.primary, fullWidth: true))
            }
            .padding(16)
            .background(Color.paper)
            .navigationTitle("這趟的照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
        .task { image = await RoutePhotoLibrary.fullImage(id: photo.id, side: 1600) }
    }
}
