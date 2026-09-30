import PhotosUI
import SwiftUI
import UIKit

/// 記錄飲食：選餐別 → 選取得方式（拍照、相簿、標示、條碼、描述）或從道具清單挑 → 放進背包一次送出
struct AddFoodView: View {
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable, Identifiable {
        case all = "全部", recent = "近期", favorites = "收藏", custom = "自訂"
        var id: String { rawValue }
    }

    /// 拍好、等使用者補充說明的照片
    struct PendingPhoto: Identifiable {
        let id = UUID()
        let image: UIImage
        let apiData: Data?
    }

    @State private var meal: MealType
    @State private var date: Date
    @State private var tab: Tab = .all
    @State private var searchText = ""
    @State private var drafts: [FoodDraft] = []
    @State private var editingDraftID: UUID?

    // 拍照辨識
    @State private var photoThumbnail: Data?
    @State private var stickerData: Data?
    /// 用照片貼紙的那一項（送出時排到第一個）
    @State private var stickerDraftID: UUID?
    /// 這一項改用 emoji 圖示時為 false（照片還是會存）
    @State private var usePhotoSticker = true
    @State private var aiNote: String?
    @State private var aiConfidence: String?
    @State private var aiUsed: AIProvider?
    @State private var lastAIInput: (imageData: Data?, text: String)?
    @State private var isWorking = false
    @State private var workingText = ""
    @State private var errorMessage: String?
    /// 相機關掉後才跳出補充說明，避免兩個畫面同時切換
    @State private var stagedPhoto: PendingPhoto?
    @State private var pendingPhoto: PendingPhoto?

    // 各種畫面
    @State private var showCamera = false
    @State private var cameraForLabel = false
    @State private var showScanner = false
    /// 查不到的條碼：問要不要拍營養標示新增
    @State private var unknownBarcode: String?
    /// 讀完營養標示後要存到這個條碼底下
    @State private var labelBarcode: String?
    /// 品牌商品與食藥署資料庫的搜尋結果（打完字才算，不用每次畫面更新都重算）
    @State private var searchResults: [FoodOption] = []
    @State private var showLibrary = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showLabelLibrary = false
    @State private var labelPhotoItem: PhotosPickerItem?
    @State private var showDescribe = false
    @State private var describeText = ""
    @State private var showCustomEditor = false
    @State private var portionItem: PortionItem?

    // 清單
    @State private var frequent: [QuickFood] = []
    @State private var recent: [QuickFood] = []
    @State private var favorites: [QuickFood] = []
    @State private var customFoods: [QuickFood] = []
    @State private var savedLabels: [NutritionLabel] = []
    @State private var didHandleStart = false
    private let start: AddFoodRequest.Start

    init(request: AddFoodRequest) {
        let date = request.date ?? .now
        _meal = State(initialValue: request.meal ?? .suggested(for: date))
        _date = State(initialValue: date)
        start = request.start
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    mealSelector
                    sourceWindow
                    itemWindow
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.paper)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomTray }
            .navigationTitle("記錄\(meal.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: {
                if let stagedPhoto {
                    pendingPhoto = stagedPhoto
                    self.stagedPhoto = nil
                }
            }) {
                CameraPicker { image in
                    if cameraForLabel { readLabel(image) } else { handlePhoto(image, fromCamera: true) }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showScanner) { scannerScreen }
            .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
            .photosPicker(isPresented: $showLabelLibrary, selection: $labelPhotoItem, matching: .images)
            .onChange(of: photoItem) { _, item in loadPhoto(item, forLabel: false) }
            .onChange(of: labelPhotoItem) { _, item in loadPhoto(item, forLabel: true) }
            .sheet(item: $pendingPhoto) { photo in
                PhotoNoteSheet(image: photo.image, providerName: FoodAnalyzer.provider.shortName) { note in
                    runAI(imageData: photo.apiData, text: note)
                } onCancel: {
                    photoThumbnail = nil
                    stickerData = nil
                }
            }
            .sheet(item: $portionItem) { item in
                PortionSheet(item: item) { drafts.append($0) }
            }
            .sheet(isPresented: $showDescribe) {
                DescribeSheet(text: $describeText, providerName: FoodAnalyzer.provider.shortName) {
                    runAI(imageData: nil, text: describeText)
                }
            }
            .sheet(isPresented: $showCustomEditor) {
                CustomFoodSheet { draft in
                    CustomFoodStore.save(QuickFood(draft: draft))
                    drafts.append(draft)
                    reloadLists()
                }
            }
            .sheet(isPresented: Binding(get: { editingDraftID != nil }, set: { if !$0 { editingDraftID = nil } })) {
                if let id = editingDraftID, let index = drafts.firstIndex(where: { $0.id == id }) {
                    DraftEditSheet(draft: $drafts[index],
                                   photoSticker: id == stickerDraftID ? stickerData : nil,
                                   usesPhoto: $usePhotoSticker)
                }
            }
            .task {
                reloadLists()
                handleStartAction()
                // 先在背景載好搜尋用的資料庫，第一次打字就不用等
                Task.detached(priority: .utility) {
                    _ = BrandFoodDatabase.shared
                    _ = FoodDatabase.shared
                }
            }
            .task(id: searchText) {
                let text = query
                guard !text.isEmpty else {
                    searchResults = []
                    return
                }
                // 注音還在組字（還沒選字）時先不搜
                guard !Self.isComposingZhuyin(text) else { return }
                try? await Task.sleep(for: .milliseconds(200)) // 打字停一下再搜
                guard !Task.isCancelled else { return }
                // 一萬多筆資料在背景比對，不卡鍵盤
                let results = await Task.detached(priority: .userInitiated) { Self.search(text) }.value
                guard !Task.isCancelled else { return }
                searchResults = results
            }
            .confirmationDialog("資料庫找不到這個商品", isPresented: Binding(get: { unknownBarcode != nil },
                                                                          set: { if !$0 { unknownBarcode = nil } }),
                                titleVisibility: .visible) {
                let code = unknownBarcode
                Button("拍營養標示新增") {
                    labelBarcode = code
                    cameraForLabel = true
                    showCamera = true
                }
                .disabled(!CameraPicker.isAvailable)
                Button("從相簿選營養標示") {
                    labelBarcode = code
                    showLabelLibrary = true
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("條碼 \(unknownBarcode ?? "")。拍下包裝上的營養標示，讀完會存起來，下次掃同一個條碼就直接帶出。")
            }
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
    }

    // MARK: - 餐別與取得方式

    private var mealSelector: some View {
        HStack(spacing: 8) {
            ForEach(MealType.allCases) { item in
                Button(item.title) { meal = item }
                    .buttonStyle(.pixel(meal == item ? .primary : .secondary, fullWidth: true, fontSize: 12))
                    .accessibilityAddTraits(meal == item ? .isSelected : [])
            }
        }
    }

    private var sourceWindow: some View {
        PixelWindow(title: "怎麼記？") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                source("拍照", art: .camera) {
                    cameraForLabel = false
                    showCamera = true
                }
                .disabled(!CameraPicker.isAvailable)
                source("相簿", art: .photo) { showLibrary = true }
                source("說／打字", art: .star) { showDescribe = true }
                source("營養標示", art: .label) {
                    labelBarcode = nil
                    if CameraPicker.isAvailable {
                        cameraForLabel = true
                        showCamera = true
                    } else {
                        showLabelLibrary = true
                    }
                }
                source("標示相簿", art: .photo) { showLabelLibrary = true }
                source("條碼", art: .barcode) { showScanner = true }
                    .disabled(!BarcodeScannerView.isAvailable)
            }
        }
        .disabled(isWorking)
    }

    private func source(_ title: String, art: PixelArt, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                PixelSprite(art: art, size: 28)
                Text(title).font(.px(12)).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.pixel(.secondary, fullWidth: true, fontSize: 12))
        .accessibilityLabel(title)
    }

    // MARK: - 道具清單

    private var itemWindow: some View {
        PixelWindow(title: "食物清單", spacing: 12) {
            HStack(spacing: 8) {
                PixelSprite(art: .search, size: 20)
                TextField("搜尋食物或品牌，例如：全家 雞胸、拿鐵", text: $searchText)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !searchText.isEmpty {
                    Button("清除") { searchText = "" }
                        .font(.px(12))
                        .foregroundStyle(Color.soft)
                }
            }
            .pixelField()

            HStack(spacing: 6) {
                ForEach(Tab.allCases) { item in
                    Button(item.rawValue) { tab = item }
                        .buttonStyle(.pixel(tab == item ? .primary : .secondary, fullWidth: true, fontSize: 12))
                }
            }

            LazyVStack(alignment: .leading, spacing: 0) {
                listHeader
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    if index > 0 { PixelDivider() }
                    FoodOptionRow(
                        option: option,
                        isFavorite: favoriteNames.contains(option.name),
                        onAdd: { add(option) },
                        onToggleFavorite: {
                            FavoriteStore.toggle(option.quickFood)
                            reloadLists()
                        },
                        onDelete: deleteAction(for: option)
                    )
                }
                emptyHint
            }
        }
    }

    private var favoriteNames: Set<String> { Set(favorites.map(\.name)) }

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func matches(_ name: String) -> Bool {
        query.isEmpty || FuzzyMatcher.bestScore(FuzzyMatcher.normalize(query), in: FuzzyMatcher.normalize(name)) != nil
    }

    /// 注音符號（ㄅ–ㄩ、聲調）出現在字串裡，代表輸入法還在組字
    private nonisolated static func isComposingZhuyin(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3100...0x312F).contains($0.value) || (0x31A0...0x31BF).contains($0.value)
            || "ˊˇˋ˙".unicodeScalars.contains($0) }
    }

    /// 品牌商品和食藥署資料庫依相符程度一起排
    private nonisolated static func search(_ query: String) -> [FoodOption] {
        var scored: [(option: FoodOption, score: Int)] = []
        scored += BrandFoodDatabase.shared.search(query, limit: 80).map { (FoodOption(brand: $0.food), $0.score) }
        scored += FoodDatabase.shared.searchScored(query, limit: 40).map { (FoodOption(database: $0.food), $0.score + 5) }
        return scored.sorted { $0.score > $1.score }.map(\.option)
    }

    private var options: [FoodOption] {
        switch tab {
        case .all:
            guard !query.isEmpty else { return frequent.map(FoodOption.init(quick:)) }
            var seen = Set<String>()
            var result: [FoodOption] = []
            for food in favorites + customFoods + recent where matches(food.name) && seen.insert(food.name).inserted {
                result.append(FoodOption(quick: food))
            }
            for label in savedLabels where matches(label.productName) && seen.insert(label.productName).inserted {
                result.append(FoodOption(label: label))
            }
            for option in searchResults where seen.insert(option.name).inserted {
                result.append(option)
            }
            return Array(result.prefix(120))
        case .recent:
            return recent.filter { matches($0.name) }.map(FoodOption.init(quick:))
        case .favorites:
            return favorites.filter { matches($0.name) }.map(FoodOption.init(quick:))
        case .custom:
            return customFoods.filter { matches($0.name) }.map(FoodOption.init(quick:))
                + savedLabels.filter { matches($0.productName) }.map(FoodOption.init(label:))
        }
    }

    @ViewBuilder private var listHeader: some View {
        switch tab {
        case .all where query.isEmpty && !frequent.isEmpty:
            Text("常吃的食物").font(.px(12)).foregroundStyle(Color.soft).padding(.bottom, 4)
        case .custom:
            Button("＋ 新增自訂食物") { showCustomEditor = true }
                .buttonStyle(.pixel(.secondary, fullWidth: true, fontSize: 12))
                .padding(.bottom, 8)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var emptyHint: some View {
        if options.isEmpty {
            Text(emptyText)
                .font(.px(12))
                .foregroundStyle(Color.soft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        }
    }

    private var emptyText: String {
        switch tab {
        case .all: query.isEmpty
            ? "可以搜尋食物，也可以搜品牌商品（全家、星巴克、麥當勞…），\n或用上面的拍照、說／打字讓 AI 估算。"
            : "找不到「\(query)」。\n可以拍照、用說／打字讓 AI 估算，或到「自訂」新增。"
        case .recent: "還沒有記錄過的食物。"
        case .favorites: "長按任何食物，就能加入收藏。"
        case .custom: "自己常煮的菜、讀過的營養標示會在這裡。"
        }
    }

    private func deleteAction(for option: FoodOption) -> (() -> Void)? {
        guard tab == .custom else { return nil }
        switch option.kind {
        case .quick(let food): return { CustomFoodStore.remove(food); reloadLists() }
        case .label(let label): return { LabelStore.remove(label); reloadLists() }
        case .database, .brand: return nil
        }
    }

    private func add(_ option: FoodOption) {
        switch option.kind {
        case .quick(let food): drafts.append(FoodDraft(quick: food))
        case .database(let food): portionItem = PortionItem(food: food)
        case .label(let label): portionItem = PortionItem(label: label)
        case .brand: drafts.append(FoodDraft(quick: option.quickFood, source: .database))
        }
    }

    private func reloadLists() {
        frequent = LogService.shared.frequentFoods(limit: 20)
        recent = LogService.shared.recentFoods()
        favorites = FavoriteStore.all()
        customFoods = CustomFoodStore.all()
        savedLabels = LabelStore.all()
    }

    private func handleStartAction() {
        guard !didHandleStart else { return }
        didHandleStart = true
        switch start {
        case .camera:
            if CameraPicker.isAvailable {
                cameraForLabel = false
                showCamera = true
            }
        case .library:
            showLibrary = true
        case .label:
            if CameraPicker.isAvailable {
                cameraForLabel = true
                showCamera = true
            } else {
                showLabelLibrary = true
            }
        case .describe:
            showDescribe = true
        case .none:
            break
        }
    }

    // MARK: - 背包（下方托盤）

    private var hasStatus: Bool { isWorking || errorMessage != nil || aiNote != nil }

    @ViewBuilder private var bottomTray: some View {
        if !drafts.isEmpty || hasStatus {
            VStack(alignment: .leading, spacing: 12) {
                statusBanner

                if !drafts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(drafts) { draft in
                                DraftTile(draft: draft,
                                          sticker: draft.id == stickerDraftID && usePhotoSticker ? stickerData : nil) {
                                    editingDraftID = draft.id
                                } onDelete: {
                                    drafts.removeAll { $0.id == draft.id }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("背包 \(drafts.count) 樣").font(.px(12)).foregroundStyle(Color.soft)
                            Text("\(drafts.sum(\.calories).rounded0) 大卡").font(.px(20)).monospacedDigit()
                        }
                        DatePicker("時間", selection: $date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                        Spacer(minLength: 0)
                        Button("吃下去！") { save() }
                            .buttonStyle(.pixel(.primary))
                            .disabled(!canSave)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.window.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(Color.ink).frame(height: 3) }
        }
    }

    @ViewBuilder private var statusBanner: some View {
        if isWorking {
            HStack(spacing: 10) {
                PixelLoadingDots()
                Text(workingText).font(.px(12)).foregroundStyle(Color.soft)
            }
        }
        if let errorMessage {
            HStack(alignment: .top) {
                Text("！\(errorMessage)")
                    .font(.px(12))
                    .foregroundStyle(Color.danger)
                Spacer()
                Button("關閉") { self.errorMessage = nil }
                    .font(.px(12))
                    .foregroundStyle(Color.soft)
            }
        }
        if let aiNote, !isWorking {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let aiUsed { Badge(text: aiUsed.shortName, color: .brand) }
                    if let aiConfidence { confidenceBadge(aiConfidence) }
                    Spacer()
                    Button("關閉") { self.aiNote = nil }
                        .font(.px(12))
                        .foregroundStyle(Color.soft)
                }
                Text(aiNote).font(.px(12)).foregroundStyle(Color.soft)
                if aiUsed == .apple, AIProvider.gemini.apiKey != nil, let input = lastAIInput {
                    Button("不準？用 Gemini 再算一次") {
                        runAI(imageData: input.imageData, text: input.text, preferred: .gemini)
                    }
                    .buttonStyle(.pixel(.secondary, fontSize: 12))
                }
            }
        }
    }

    private func confidenceBadge(_ level: String) -> some View {
        switch level {
        case "high": Badge(text: "把握度高", color: .move)
        case "low": Badge(text: "把握度低，請檢查", color: .danger)
        default: Badge(text: "把握度中", color: .carbs)
        }
    }

    private var scannerScreen: some View {
        NavigationStack {
            BarcodeScannerView { code in
                showScanner = false
                lookupBarcode(code)
            }
            .ignoresSafeArea()
            .navigationTitle("掃描商品條碼")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showScanner = false }
                }
            }
        }
    }

    // MARK: - 動作

    private var canSave: Bool {
        !isWorking && drafts.contains { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func save() {
        var valid = drafts.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        // 照片和照片貼紙要跟著拍照辨識出來的那一項
        var photo: Data?
        var sticker: Data?
        if let id = stickerDraftID, let index = valid.firstIndex(where: { $0.id == id }) {
            valid.insert(valid.remove(at: index), at: 0)
            photo = photoThumbnail
            sticker = usePhotoSticker ? stickerData : nil
        }
        LogService.shared.logFoods(valid, meal: meal, date: date, photo: photo, sticker: sticker)
        dismiss()
    }

    private func loadPhoto(_ item: PhotosPickerItem?, forLabel: Bool) {
        guard let item else { return }
        Task { @MainActor in
            defer {
                if forLabel { labelPhotoItem = nil } else { photoItem = nil }
            }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "無法讀取這張照片。"
                return
            }
            if forLabel {
                readLabel(image)
            } else {
                // 等相簿畫面完全收起來，再跳出補充說明
                try? await Task.sleep(for: .milliseconds(400))
                handlePhoto(image, fromCamera: false)
            }
        }
    }

    private func notReadyMessage() -> String {
        let error: FoodAnalyzerError = FoodAnalyzer.provider == .apple ? .appleAIUnavailable : .missingKey
        return error.localizedDescription
    }

    /// 拍餐點：先在手機上做貼紙，再問要不要補充說明（打字或用說的），最後交給 AI
    private func handlePhoto(_ image: UIImage, fromCamera: Bool) {
        photoThumbnail = image.resized(maxDimension: 480).jpegData(compressionQuality: 0.6)
        stickerData = nil
        stickerDraftID = nil
        usePhotoSticker = true
        Task { @MainActor in
            stickerData = await StickerMaker.makeSticker(from: image)
        }
        let photo = PendingPhoto(image: image.resized(maxDimension: 1200),
                                 apiData: image.resized(maxDimension: 1568).jpegData(compressionQuality: 0.8))
        if fromCamera { stagedPhoto = photo } else { pendingPhoto = photo }
    }

    /// - Parameter preferred: 指定這次用哪個 AI（「用 Gemini 再算一次」），會取代上次 AI 的結果
    private func runAI(imageData: Data?, text: String, preferred: AIProvider? = nil) {
        guard preferred != nil || FoodAnalyzer.isReady else {
            errorMessage = notReadyMessage()
            return
        }
        let name = (preferred ?? FoodAnalyzer.provider).shortName
        isWorking = true
        workingText = imageData == nil ? "\(name) 正在估算…" : "\(name) 正在辨識照片…"
        errorMessage = nil
        lastAIInput = (imageData, text)

        Task { @MainActor in
            defer { isWorking = false }
            do {
                let result = try await FoodAnalyzer().analyze(imageData: imageData, description: text,
                                                              preferred: preferred)
                let analysis = result.analysis
                guard !analysis.items.isEmpty else {
                    errorMessage = analysis.notes.isEmpty ? "沒有辨識到食物。" : analysis.notes
                    return
                }
                if preferred != nil { drafts.removeAll { $0.source == .ai } }
                let newDrafts = analysis.items.map(FoodDraft.init(aiItem:))
                drafts.append(contentsOf: newDrafts)
                if imageData != nil { stickerDraftID = newDrafts.first?.id }
                aiNote = analysis.notes.isEmpty ? "已加入 \(newDrafts.count) 項，點貼紙可以修改。" : analysis.notes
                aiConfidence = analysis.confidence
                aiUsed = result.provider
                if imageData == nil { describeText = "" }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 營養標示：讀出每份數值 → 選份量
    private func readLabel(_ image: UIImage) {
        guard FoodAnalyzer.isReady else {
            errorMessage = notReadyMessage()
            return
        }
        // 標示上的字很小，保留較高解析度
        guard let imageData = image.resized(maxDimension: 2000).jpegData(compressionQuality: 0.85) else { return }
        isWorking = true
        workingText = "\(FoodAnalyzer.provider.shortName) 正在讀營養標示…"
        errorMessage = nil

        Task { @MainActor in
            defer { isWorking = false }
            do {
                let outcome = try await FoodAnalyzer().readLabel(imageData: imageData)
                LabelStore.save(outcome.label)
                if let code = labelBarcode {
                    BarcodeStore.save(outcome.label, for: code)
                    labelBarcode = nil
                }
                reloadLists()
                portionItem = PortionItem(label: outcome.label)
            } catch {
                errorMessage = error.localizedDescription
                labelBarcode = nil
            }
        }
    }

    /// 條碼：先查自己存過的 → Open Food Facts → 都沒有就問要不要拍營養標示新增
    private func lookupBarcode(_ code: String) {
        if let saved = BarcodeStore.label(for: code) {
            portionItem = PortionItem(label: saved)
            return
        }
        if let food = BrandFoodDatabase.shared.food(barcode: code) {
            if let grams = food.grams, grams > 0 {
                portionItem = PortionItem(brand: food, grams: grams)
            } else {
                drafts.append(FoodDraft(quick: FoodOption(brand: food).quickFood, source: .barcode))
            }
            return
        }
        isWorking = true
        workingText = "查詢條碼 \(code)…"
        errorMessage = nil
        Task { @MainActor in
            defer { isWorking = false }
            do {
                if let product = try await ProductLookup.lookup(barcode: code) {
                    BarcodeStore.save(NutritionLabel(product: product), for: code)
                    portionItem = PortionItem(product: product)
                } else {
                    unknownBarcode = code
                }
            } catch is ProductLookup.LookupError {
                unknownBarcode = code // 有這個商品但沒有營養資料
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - 清單的一列

/// 清單裡的一個選項：常吃／近期／收藏／自訂食物、營養資料庫、讀過的營養標示
struct FoodOption: Identifiable {
    enum Kind {
        case quick(QuickFood)
        case database(TWFood)
        case label(NutritionLabel)
        case brand(BrandFood)
    }

    let id: String
    let kind: Kind
    let name: String
    let emoji: String
    let detail: String

    init(quick food: QuickFood) {
        id = "q-\(food.name)"
        kind = .quick(food)
        name = food.name
        emoji = food.emoji.isEmpty ? FoodEmoji.guess(name: food.name) : food.emoji
        detail = "\(food.calories.rounded0) 大卡, \(food.portion.isEmpty ? "1 份" : food.portion)"
    }

    init(database food: TWFood) {
        id = "d-\(food.id)"
        kind = .database(food)
        name = food.name
        emoji = FoodEmoji.guess(name: food.name, category: food.category)
        if let unit = food.unitGrams {
            let kcal = food.per100.scaled(grams: unit).kcal
            detail = "\(kcal.rounded0) 大卡, 1 份（\(unit.rounded0) g）, \(food.category)"
        } else {
            detail = "\(food.per100.kcal.rounded0) 大卡, 100 g, \(food.category)"
        }
    }

    init(label: NutritionLabel) {
        id = "l-\(label.productName)"
        kind = .label(label)
        name = label.productName
        emoji = label.emoji.isEmpty ? FoodEmoji.guess(name: label.productName) : label.emoji
        detail = "\(label.calories.rounded0) 大卡, 1 份（\(label.servingSize.formatted()) \(label.isLiquid ? "ml" : "g")）, 營養標示"
    }

    init(brand food: BrandFood) {
        id = "b-\(food.id)"
        kind = .brand(food)
        name = food.displayName
        emoji = FoodEmoji.guess(name: food.name)
        let serving = (food.serving ?? "").isEmpty ? "1 份" : food.serving ?? "1 份"
        detail = "\(food.kcal.rounded0) 大卡, \(serving)・\(food.sourceLabel)"
    }

    /// 加入收藏時存的內容（資料庫食物以 1 份或 100 g 計）
    var quickFood: QuickFood {
        switch kind {
        case .quick(let food):
            return food
        case .database(let food):
            let grams = food.unitGrams ?? 100
            let n = food.per100.scaled(grams: grams)
            return QuickFood(name: food.name, emoji: emoji, portion: "\(grams.rounded0) g", calories: n.kcal,
                             protein: n.protein, carbs: n.carbs, fat: n.fat, sodium: n.sodium, sugar: n.sugar)
        case .label(let label):
            return QuickFood(name: label.productName, emoji: emoji,
                             portion: "1 份（\(label.servingSize.formatted()) \(label.isLiquid ? "ml" : "g")）",
                             calories: label.calories, protein: label.protein, carbs: label.carbs,
                             fat: label.fat, sodium: label.sodium, sugar: label.sugar)
        case .brand(let food):
            return QuickFood(name: food.displayName, emoji: emoji,
                             portion: (food.serving ?? "").isEmpty ? "1 份" : food.serving ?? "1 份",
                             calories: food.kcal, protein: food.protein ?? 0, carbs: food.carbs ?? 0,
                             fat: food.fat ?? 0, sodium: food.sodium ?? 0, sugar: food.sugar ?? 0)
        }
    }
}

struct FoodOptionRow: View {
    let option: FoodOption
    let isFavorite: Bool
    let onAdd: () -> Void
    let onToggleFavorite: () -> Void
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            StickerView(stickerData: nil, emoji: option.emoji, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(option.name).lineLimit(2)
                    if isFavorite { PixelSprite(art: .heart, size: 12) }
                }
                Text(option.detail).font(.px(12)).foregroundStyle(Color.soft).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("＋", action: onAdd)
                .buttonStyle(.pixel(.primary, fontSize: 16))
                .accessibilityLabel("加入\(option.name)")
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onAdd)
        .contextMenu {
            Button(action: onToggleFavorite) {
                Label(isFavorite ? "移除收藏" : "加入收藏", systemImage: isFavorite ? "heart.slash" : "heart")
            }
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("刪除", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - 背包裡的一項

struct DraftTile: View {
    let draft: FoodDraft
    let sticker: Data?
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(action: onTap) {
                StickerView(stickerData: sticker,
                            emoji: draft.emoji.isEmpty ? FoodEmoji.guess(name: draft.name) : draft.emoji,
                            size: 48)
                    .padding(6)
                    .pixelPanel(fill: .paper, shadow: nil, lineWidth: 2)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) {
                Button(action: onDelete) {
                    Text("×")
                        .font(.px(12))
                        .foregroundStyle(Color.onBrand)
                        .frame(width: 18, height: 18)
                        .background(Rectangle().fill(Color.ink))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .accessibilityLabel("移除\(draft.name)")
            }
            Text(draft.name.isEmpty ? "（未命名）" : draft.name)
                .font(.px(12))
                .lineLimit(1)
                .frame(width: 76)
            Text("\(draft.calories.rounded0) 大卡")
                .font(.px(12))
                .foregroundStyle(Color.soft)
        }
        .padding(.top, 6)
    }
}

/// 編輯背包裡的一項（AI 認錯、份量不對時）
struct DraftEditSheet: View {
    @Binding var draft: FoodDraft
    /// 拍照辨識的那一項才有照片像素圖
    var photoSticker: Data?
    @Binding var usesPhoto: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showIconPicker = false

    private var emoji: String { draft.emoji.isEmpty ? FoodEmoji.guess(name: draft.name) : draft.emoji }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        FoodIconRow(sticker: usesPhoto ? photoSticker : nil, emoji: emoji) { showIconPicker = true }
                    }
                    Section {
                        TextField("名稱", text: $draft.name)
                        TextField("份量（例如 1 碗、約 200 g）", text: $draft.portion)
                    }
                    Section {
                        NumberField(title: "熱量", unit: "kcal", value: $draft.calories)
                        NumberField(title: "蛋白質", unit: "g", value: $draft.protein)
                        NumberField(title: "碳水化合物", unit: "g", value: $draft.carbs)
                        NumberField(title: "脂肪", unit: "g", value: $draft.fat)
                        NumberField(title: "糖", unit: "g", value: $draft.sugar)
                        NumberField(title: "鈉", unit: "mg", value: $draft.sodium)
                    } header: {
                        Text("營養").font(.px(12))
                    }
                    Section {
                        HStack(spacing: 8) {
                            ForEach([0.5, 1.5, 2.0], id: \.self) { factor in
                                Button(factor == 0.5 ? "吃一半" : "×\(factor.formatted())") {
                                    draft.scale(by: factor)
                                }
                                .buttonStyle(.pixel(.secondary, fullWidth: true, fontSize: 12))
                            }
                        }
                    } header: {
                        Text("份量調整").font(.px(12))
                    }
                }
                .pixelRows()
            }
            .pixelForm()
            .navigationTitle("修改")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showIconPicker) {
                FoodIconPicker(current: emoji, photoAvailable: photoSticker != nil,
                               usingPhoto: photoSticker != nil && usesPhoto) { choice in
                    switch choice {
                    case .emoji(let picked):
                        draft.emoji = picked
                        if photoSticker != nil { usesPhoto = false }
                    case .photo:
                        usesPhoto = true
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 用說的或打字描述這一餐，讓 AI 估算
struct DescribeSheet: View {
    @Binding var text: String
    let providerName: String
    let onSubmit: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PixelWindow(title: "描述這一餐") {
                        TextField("例如：一碗牛肉麵加一份燙青菜、中杯無糖綠茶", text: $text, axis: .vertical)
                            .lineLimit(3...6)
                            .pixelField()
                        DictationButton(text: $text)
                        Text("會用 \(providerName) 估算熱量與營養，估算完可以再修改。")
                            .font(.px(12))
                            .foregroundStyle(Color.soft)
                    }
                    Button("估算") {
                        onSubmit()
                        dismiss()
                    }
                    .buttonStyle(.pixel(.primary, fullWidth: true))
                    .disabled(isEmpty)
                }
                .padding(16)
            }
            .background(Color.paper)
            .navigationTitle("用說的或打字")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
        .presentationDetents([.medium, .large])
    }
}

/// 拍完餐點照片後：補充照片看不出來的事（打字或用說的），讓 AI 判讀得更準
struct PhotoNoteSheet: View {
    let image: UIImage
    let providerName: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @FocusState private var focused: Bool

    private static let quickNotes = ["飯只吃半碗", "去皮", "少油", "半糖", "無糖", "大份", "小份",
                                     "只吃一半", "加一顆蛋", "醬料沒吃", "兩人分食", "湯沒喝"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PixelWindow(title: "這一餐") {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                            .clipped()
                            .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
                            .accessibilityLabel("剛拍的餐點照片")
                    }

                    PixelWindow(title: "補充說明（選填）") {
                        Text("告訴 AI 照片看不出來的事，例如份量、做法、有沒有吃完，會算得更準。")
                            .font(.px(12))
                            .foregroundStyle(Color.soft)
                        TextField("例如：飯只吃半碗、雞腿去皮、飲料半糖", text: $note, axis: .vertical)
                            .lineLimit(2...5)
                            .focused($focused)
                            .pixelField()
                        DictationButton(text: $note)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                            ForEach(Self.quickNotes, id: \.self) { quick in
                                Button(quick) { append(quick) }
                                    .buttonStyle(.pixel(.secondary, fullWidth: true, fontSize: 12))
                            }
                        }
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.paper)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 10) {
                    Button("直接辨識") { submit("") }
                        .buttonStyle(.pixel(.secondary, fullWidth: true))
                    Button("送出辨識") { submit(note) }
                        .buttonStyle(.pixel(.primary, fullWidth: true))
                        .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.window.ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) { Rectangle().fill(Color.ink).frame(height: 3) }
            }
            .navigationTitle("\(providerName) 辨識前")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("不要這張") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
        .font(.px(16))
        .foregroundStyle(Color.ink)
        .interactiveDismissDisabled()
    }

    private func append(_ text: String) {
        let current = note.trimmingCharacters(in: .whitespacesAndNewlines)
        note = current.isEmpty ? text : current + "、" + text
    }

    private func submit(_ text: String) {
        onSubmit(text.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

/// 「用說的」按鈕：說的話會接在輸入框原本的文字後面
struct DictationButton: View {
    @Binding var text: String
    @StateObject private var dictation = SpeechDictation()
    @State private var base = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    if dictation.isRecording {
                        dictation.stop()
                    } else {
                        base = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { await dictation.start() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        PixelSprite(art: .mic, size: 20)
                        Text(dictation.isRecording ? "說完了" : "用說的")
                    }
                }
                .buttonStyle(.pixel(dictation.isRecording ? .tinted(.danger) : .secondary, fontSize: 12))
                .accessibilityLabel(dictation.isRecording ? "停止語音輸入" : "用說的輸入")

                if dictation.isRecording {
                    PixelLoadingDots(color: .danger)
                    Text("聆聽中，說完按「說完了」").font(.px(12)).foregroundStyle(Color.soft)
                }
            }
            if let error = dictation.errorMessage {
                Text(error).font(.px(12)).foregroundStyle(Color.danger)
            }
        }
        .onChange(of: dictation.transcript) { _, spoken in
            guard !spoken.isEmpty else { return }
            text = base.isEmpty ? spoken : base + "，" + spoken
        }
        .onDisappear { dictation.stop() }
    }
}

/// 新增自訂食物
struct CustomFoodSheet: View {
    let onSave: (FoodDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft = FoodDraft(name: "", source: .manual)
    @State private var showIconPicker = false

    private var emoji: String { draft.emoji.isEmpty ? FoodEmoji.guess(name: draft.name) : draft.emoji }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        FoodIconRow(sticker: nil, emoji: emoji) { showIconPicker = true }
                    }
                    Section {
                        TextField("名稱，例如：媽媽的番茄炒蛋", text: $draft.name)
                        TextField("份量，例如：1 盤", text: $draft.portion)
                    }
                    Section {
                        NumberField(title: "熱量", unit: "kcal", value: $draft.calories)
                        NumberField(title: "蛋白質", unit: "g", value: $draft.protein)
                        NumberField(title: "碳水化合物", unit: "g", value: $draft.carbs)
                        NumberField(title: "脂肪", unit: "g", value: $draft.fat)
                        NumberField(title: "糖", unit: "g", value: $draft.sugar)
                        NumberField(title: "鈉", unit: "mg", value: $draft.sodium)
                    } header: {
                        Text("一份的營養").font(.px(12))
                    }
                }
                .pixelRows()
            }
            .pixelForm()
            .navigationTitle("新增自訂食物")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showIconPicker) {
                FoodIconPicker(current: emoji) { choice in
                    if case .emoji(let picked) = choice { draft.emoji = picked }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存並加入") {
                        var saved = draft
                        saved.emoji = emoji
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - 資料庫 / 條碼 / 營養標示的份量選擇

struct PortionItem: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    /// 每 100 公克（或毫升）的營養
    let per100: Nutrition100
    /// 一份的重量
    let unitGrams: Double?
    /// 整包的重量（營養標示有「本包裝含 N 份」時才有）
    let packageGrams: Double?
    /// "g" 或 "ml"
    let unitSymbol: String
    let source: EntrySource
    let emoji: String
    /// 數字可能讀錯時的提醒
    let warning: String?

    init(food: TWFood) {
        name = food.name
        subtitle = [food.category, food.detail].filter { !$0.isEmpty }.joined(separator: " · ")
        per100 = food.per100
        unitGrams = food.unitGrams
        packageGrams = nil
        unitSymbol = "g"
        source = .database
        emoji = FoodEmoji.guess(name: food.name, category: food.category)
        warning = nil
    }

    /// 內建資料的數值是「每份」（grams 公克），換算成每 100 公克
    init(brand food: BrandFood, grams: Double) {
        let factor = 100 / grams
        name = food.displayName
        subtitle = [food.serving ?? "", food.sourceLabel].filter { !$0.isEmpty }.joined(separator: " · ")
        per100 = Nutrition100(kcal: food.kcal * factor, protein: (food.protein ?? 0) * factor,
                              carbs: (food.carbs ?? 0) * factor, fat: (food.fat ?? 0) * factor,
                              sodium: (food.sodium ?? 0) * factor, sugar: (food.sugar ?? 0) * factor)
        unitGrams = grams
        packageGrams = nil
        unitSymbol = "g"
        source = .barcode
        emoji = FoodEmoji.guess(name: food.name)
        warning = nil
    }

    init(product: ProductLookup.Product) {
        name = product.name
        subtitle = product.brand
        per100 = product.per100
        unitGrams = product.servingGrams
        packageGrams = nil
        unitSymbol = "g"
        source = .barcode
        emoji = FoodEmoji.guess(name: product.name)
        warning = nil
    }

    /// 營養標示的數值是「每份」，換算成每 100 公克（毫升）後就能用同一個份量畫面
    init(label: NutritionLabel) {
        let serving = label.servingSize > 0 ? label.servingSize : 100
        let factor = 100 / serving
        let symbol = label.isLiquid ? "ml" : "g"
        let servings = label.servingsPerPackage

        name = label.productName
        subtitle = "每份 \(serving.formatted()) \(symbol)"
            + (servings > 1 ? " · 本包裝 \(servings.formatted()) 份" : "")
            + " · 讀自營養標示"
        per100 = Nutrition100(kcal: label.calories * factor, protein: label.protein * factor,
                              carbs: label.carbs * factor, fat: label.fat * factor,
                              sodium: label.sodium * factor, sugar: label.sugar * factor)
        unitGrams = serving
        packageGrams = servings > 1 ? serving * servings : nil
        unitSymbol = symbol
        source = .label
        emoji = label.emoji.isEmpty ? FoodEmoji.guess(name: label.productName) : label.emoji
        warning = label.looksInconsistent
            ? "熱量和蛋白質、碳水、脂肪對不太起來，可能有數字讀錯。加入後可以點貼紙核對。"
            : nil
    }
}

struct PortionSheet: View {
    let item: PortionItem
    var onAdd: (FoodDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var grams: Double

    init(item: PortionItem, onAdd: @escaping (FoodDraft) -> Void) {
        self.item = item
        self.onAdd = onAdd
        _grams = State(initialValue: item.unitGrams ?? 100)
    }

    private struct Preset: Identifiable {
        let label: String
        let grams: Double
        var id: String { label }
    }

    private var unitName: String { item.unitSymbol == "ml" ? "毫升" : "公克" }

    private var presets: [Preset] {
        let symbol = item.unitSymbol
        var list: [Preset] = []
        if let unit = item.unitGrams {
            list += [Preset(label: "半份", grams: unit / 2),
                     Preset(label: "1 份（\(unit.rounded0) \(symbol)）", grams: unit),
                     Preset(label: "2 份", grams: unit * 2)]
        }
        if let package = item.packageGrams {
            list.append(Preset(label: "整包（\(package.rounded0) \(symbol)）", grams: package))
        }
        list += [Preset(label: "100 \(symbol)", grams: 100), Preset(label: "200 \(symbol)", grams: 200)]
        return list
    }

    var body: some View {
        let n = item.per100.scaled(grams: grams)
        NavigationStack {
            Form {
                Group {
                Section {
                    HStack(spacing: 12) {
                        StickerView(stickerData: nil, emoji: item.emoji, size: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                            if !item.subtitle.isEmpty {
                                Text(item.subtitle).font(.px(12)).foregroundStyle(Color.soft)
                            }
                        }
                    }
                    if let warning = item.warning {
                        Text("！\(warning)")
                            .font(.px(12))
                            .foregroundStyle(Color.danger)
                    }
                }
                Section {
                    HStack {
                        TextField(unitName, value: $grams, format: .number.precision(.fractionLength(0)))
                            .keyboardType(.numberPad)
                            .font(.px(24))
                        Text(unitName).foregroundStyle(Color.soft)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presets) { preset in
                                Button(preset.label) { grams = preset.grams }
                                    .buttonStyle(.pixel(.secondary, fontSize: 12))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("吃了多少").font(.px(12))
                }
                Section {
                    LabeledContent("熱量", value: "\(n.kcal.rounded0) kcal")
                    LabeledContent("蛋白質", value: "\(n.protein.formatted(.number.precision(.fractionLength(1)))) g")
                    LabeledContent("碳水化合物", value: "\(n.carbs.formatted(.number.precision(.fractionLength(1)))) g")
                    LabeledContent("脂肪", value: "\(n.fat.formatted(.number.precision(.fractionLength(1)))) g")
                    LabeledContent("糖", value: "\(n.sugar.formatted(.number.precision(.fractionLength(1)))) g")
                    LabeledContent("鈉", value: "\(n.sodium.rounded0) mg")
                } header: {
                    Text("營養（依份量換算）").font(.px(12))
                }
                }
                .pixelRows()
            }
            .pixelForm()
            .navigationTitle("選擇份量")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("加入") {
                        onAdd(FoodDraft(name: item.name, portion: portionText, calories: n.kcal,
                                        protein: n.protein, carbs: n.carbs, fat: n.fat,
                                        sodium: n.sodium, sugar: n.sugar, source: item.source, emoji: item.emoji))
                        dismiss()
                    }
                    .disabled(grams <= 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var portionText: String {
        let symbol = item.unitSymbol
        if let package = item.packageGrams, abs(grams - package) < 0.5 {
            return "整包（\(package.rounded0) \(symbol)）"
        }
        if let unit = item.unitGrams, unit > 0, abs(grams - unit) < 0.5 {
            return "1 份（\(unit.rounded0) \(symbol)）"
        }
        if let unit = item.unitGrams, unit > 0, abs(grams - unit / 2) < 0.5 {
            return "半份（\(grams.rounded0) \(symbol)）"
        }
        return "\(grams.rounded0) \(symbol)"
    }
}

extension QuickFood {
    init(draft: FoodDraft) {
        self.init(name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                  emoji: draft.emoji.isEmpty ? FoodEmoji.guess(name: draft.name) : draft.emoji,
                  portion: draft.portion, calories: draft.calories, protein: draft.protein,
                  carbs: draft.carbs, fat: draft.fat, sodium: draft.sodium, sugar: draft.sugar)
    }
}
