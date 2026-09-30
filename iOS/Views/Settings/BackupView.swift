import SwiftUI
import UniformTypeIdentifiers

/// 資料備份：匯出成一個檔案（可以存到「檔案」或 iCloud 雲碟），換手機、重裝後匯入還原
struct BackupView: View {
    @State private var backupFile: URL?
    @State private var backupSize: String?
    @State private var working = false
    @State private var importing = false
    @State private var pendingFile: URL?
    @State private var stagedDate: Date?
    @State private var errorMessage: String?
    @State private var lastBackup = UserDefaults.standard.object(forKey: BackupService.lastBackupKey) as? Date

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let stagedDate {
                    restartWindow(stagedDate)
                }
                exportWindow
                importWindow
                PixelWindow(title: "備份裡有什麼", tint: .soft) {
                    Text("包含：飲食、喝水、運動、體重紀錄和照片、精靈與閃光版、元氣幣、營地、每週任務、路線、世界迷霧、目標與偏好設定。")
                        .font(.px(12))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("不包含：AI 金鑰（安全起見要重新輸入）、「健康」App 裡的資料（本來就存在「健康」，換手機會跟著 iCloud 走）。")
                        .font(.px(12))
                        .foregroundStyle(Color.soft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
        .background(Color.paper)
        .navigationTitle("資料備份")
        .navigationBarTitleDisplayMode(.inline)
        .font(.px(16))
        .foregroundStyle(Color.ink)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.propertyList, .data]) { result in
            if case .success(let url) = result { pendingFile = url }
        }
        .confirmationDialog("用這個備份覆蓋目前的資料？", isPresented: Binding(get: { pendingFile != nil }, set: { if !$0 { pendingFile = nil } }),
                            titleVisibility: .visible) {
            Button("覆蓋並還原", role: .destructive) {
                if let pendingFile { Task { await stage(pendingFile) } }
            }
            Button("取消", role: .cancel) { pendingFile = nil }
        } message: {
            Text("這支 iPhone 上目前的紀錄、精靈和設定都會被備份裡的內容取代。")
        }
        .alert("沒辦法完成", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var exportWindow: some View {
        PixelWindow(title: "匯出備份", tint: .brand) {
            Text("把所有資料打包成一個檔案，建議存到 iCloud 雲碟，換手機或刪掉 App 也找得回來。")
                .font(.px(12))
                .foregroundStyle(Color.soft)
                .fixedSize(horizontal: false, vertical: true)
            if let backupFile {
                ShareLink(item: backupFile) {
                    Text("存到「檔案」或分享")
                }
                .buttonStyle(.pixel(.primary, fullWidth: true))
                if let backupSize {
                    Text("備份檔大小 \(backupSize)").font(.px(12)).foregroundStyle(Color.soft)
                }
            } else {
                Button(working ? "打包中…" : "建立備份檔") { Task { await export() } }
                    .buttonStyle(.pixel(.primary, fullWidth: true))
                    .disabled(working)
            }
            if let lastBackup {
                Text("上次備份：\(lastBackup.formatted(.dateTime.year().month().day().hour().minute()))")
                    .font(.px(12))
                    .foregroundStyle(Color.soft)
            }
        }
    }

    private var importWindow: some View {
        PixelWindow(title: "從備份還原", tint: .protein) {
            Text("選一個之前匯出的備份檔。還原會覆蓋這支 iPhone 上目前的資料，重新打開 App 後生效。")
                .font(.px(12))
                .foregroundStyle(Color.soft)
                .fixedSize(horizontal: false, vertical: true)
            Button(working ? "讀取中…" : "選擇備份檔") { importing = true }
                .buttonStyle(.pixel(.secondary, fullWidth: true))
                .disabled(working)
        }
    }

    private func restartWindow(_ date: Date) -> some View {
        PixelWindow(title: "還原準備好了", tint: .move) {
            Text("\(date.formatted(.dateTime.year().month().day().hour().minute())) 的備份已經讀好。")
            Text("從多工畫面把 App 關掉再重新打開，就會換成備份的資料。")
                .font(.px(12))
                .foregroundStyle(Color.soft)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("現在關閉 App") { exit(0) }
                    .buttonStyle(.pixel(.primary, fullWidth: true, fontSize: 12))
                Button("取消還原") {
                    BackupService.cancelPendingRestore()
                    stagedDate = nil
                }
                .buttonStyle(.pixel(.secondary, fullWidth: true, fontSize: 12))
            }
        }
    }

    private func export() async {
        working = true
        defer { working = false }
        do {
            let url = try await BackupService.makeBackup()
            backupFile = url
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            backupSize = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            lastBackup = .now
        } catch {
            errorMessage = "打包失敗：\(error.localizedDescription)"
        }
    }

    private func stage(_ url: URL) async {
        pendingFile = nil
        working = true
        defer { working = false }
        do {
            stagedDate = try await BackupService.stageRestore(from: url)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "這個檔案不是卡路里大作戰的備份。"
        }
    }
}
