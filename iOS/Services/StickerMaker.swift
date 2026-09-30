import CoreImage
import UIKit
import Vision

/// 把餐點照片做成貼紙：
/// 用 iOS 17 的「主體擷取」在手機上把食物從背景剪下來（免費、照片不會上傳），
/// 擷取不到時改成圓形貼紙。
enum StickerMaker {
    static func makeSticker(from image: UIImage) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            let source = image.resized(maxDimension: 640)
            return cutout(source) ?? circle(source)
        }.value
    }

    private static func cutout(_ image: UIImage) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true
            )
            let masked = CIImage(cvPixelBuffer: buffer)
            guard let output = CIContext().createCGImage(masked, from: masked.extent) else { return nil }
            return UIImage(cgImage: output).pngData()
        } catch {
            return nil // 模擬器或舊機型不支援時會走到這裡
        }
    }

    private static func circle(_ image: UIImage) -> Data? {
        let side = min(image.size.width, image.size.height)
        let origin = CGPoint(x: -(image.size.width - side) / 2, y: -(image.size.height - side) / 2)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let size = CGSize(width: side, height: side)
        let output = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
            image.draw(at: origin)
        }
        return output.pngData()
    }
}

/// 沒有照片的食物，依名稱或分類配一個 emoji（畫面上會轉成像素圖）
enum FoodEmoji {
    static let fallback = "🍽️"

    struct Group: Identifiable {
        let title: String
        let emojis: [String]
        var id: String { title }
    }

    /// Apple 內建的所有食物與飲料 emoji，選圖示、選頭像時用
    static let catalog: [Group] = [
        Group(title: "水果", emojis: ["🍎", "🍏", "🍐", "🍊", "🍋", "🍋‍🟩", "🍌", "🍉", "🍇", "🍓", "🫐", "🍈",
                                     "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🫒"]),
        Group(title: "蔬菜與豆類", emojis: ["🥑", "🍆", "🥔", "🥕", "🌽", "🌶️", "🫑", "🥒", "🥬", "🥦", "🧄", "🧅",
                                        "🍄", "🍄‍🟫", "🫚", "🫛", "🫘", "🥜", "🌰", "🫜"]),
        Group(title: "麵包與主餐", emojis: ["🍞", "🥐", "🥖", "🫓", "🥨", "🥯", "🥞", "🧇", "🧀", "🍖", "🍗", "🥩",
                                        "🥓", "🍔", "🍟", "🍕", "🌭", "🥪", "🌮", "🌯", "🫔", "🥙", "🧆", "🥚",
                                        "🍳", "🥘", "🍲", "🫕", "🥣", "🥗", "🍿", "🧈", "🧂", "🥫"]),
        Group(title: "飯麵與亞洲料理", emojis: ["🍱", "🍘", "🍙", "🍚", "🍛", "🍜", "🍝", "🍠", "🍢", "🍣", "🍤", "🍥",
                                           "🥮", "🍡", "🥟", "🥠", "🥡"]),
        Group(title: "海鮮", emojis: ["🐟", "🐠", "🦀", "🦞", "🦐", "🦑", "🐙", "🦪"]),
        Group(title: "甜點零食", emojis: ["🍦", "🍧", "🍨", "🍩", "🍪", "🎂", "🍰", "🧁", "🥧", "🍫", "🍬", "🍭",
                                       "🍮", "🍯"]),
        Group(title: "飲料", emojis: ["🍼", "🥛", "☕", "🫖", "🍵", "🧋", "🧃", "🥤", "🧉", "🧊", "🍶", "🍾",
                                     "🍷", "🍸", "🍹", "🍺", "🍻", "🥂", "🥃", "🫗", "💧"]),
        Group(title: "餐具", emojis: ["🍽️", "🍴", "🥢", "🥄", "🫙"]),
    ]

    /// 由上往下比對，越具體的放越前面（例如「茶葉蛋」要先比對到「蛋」而不是「茶」）
    private static let keywords: [(words: [String], emoji: String)] = [
        (["珍珠", "奶茶", "手搖", "奶蓋"], "🧋"),
        (["咖啡", "拿鐵", "美式", "卡布"], "☕"),
        (["果汁"], "🧃"),
        (["可樂", "汽水", "雪碧", "奶昔", "思樂冰"], "🥤"),
        (["啤酒"], "🍺"),
        (["香檳"], "🍾"),
        (["清酒", "米酒"], "🍶"),
        (["威士忌", "高粱", "白蘭地"], "🥃"),
        (["調酒"], "🍸"),
        (["紅酒", "白酒", "葡萄酒"], "🍷"),
        (["剉冰", "刨冰", "雪花冰", "挫冰"], "🍧"),
        (["聖代"], "🍨"),
        (["冰淇淋", "霜淇淋", "雪糕"], "🍦"),
        (["杯子蛋糕", "瑪芬"], "🧁"),
        (["生日蛋糕"], "🎂"),
        (["月餅"], "🥮"),
        (["蛋糕", "乳酪蛋糕", "塔"], "🍰"),
        (["派"], "🥧"),
        (["餅乾"], "🍪"),
        (["巧克力"], "🍫"),
        (["甜甜圈"], "🍩"),
        (["布丁", "豆花", "奶酪"], "🍮"),
        (["蜂蜜"], "🍯"),
        (["棒棒糖"], "🍭"),
        (["爆米花"], "🍿"),
        (["仙貝", "米果"], "🍘"),
        (["糰子", "湯圓", "麻糬", "元宵"], "🍡"),
        (["關東煮", "黑輪", "甜不辣"], "🍢"),
        (["魚板"], "🍥"),
        (["幸運餅"], "🥠"),
        (["便當", "餐盒"], "🍱"),
        (["壽司", "生魚片"], "🍣"),
        (["飯糰"], "🍙"),
        (["咖哩"], "🍛"),
        (["漢堡"], "🍔"),
        (["披薩", "比薩"], "🍕"),
        (["薯條"], "🍟"),
        (["熱狗"], "🌭"),
        (["三明治", "漢堡蛋", "潛艇堡"], "🥪"),
        (["塔可"], "🌮"),
        (["沙威瑪", "口袋餅"], "🥙"),
        (["炸豆丸", "鷹嘴豆泥"], "🧆"),
        (["格子鬆餅"], "🧇"),
        (["鬆餅", "煎餅"], "🥞"),
        (["可頌"], "🥐"),
        (["貝果"], "🥯"),
        (["法國麵包", "法棍"], "🥖"),
        (["蔥油餅", "蔥抓餅", "手抓餅", "烙餅"], "🫓"),
        (["吐司", "麵包", "餐包"], "🍞"),
        (["蛋餅", "捲餅", "潤餅"], "🌯"),
        (["水餃", "鍋貼", "餃", "包子", "小籠", "燒賣", "饅頭"], "🥟"),
        (["義大利麵", "焗烤"], "🍝"),
        (["麵", "米粉", "冬粉", "粄條"], "🍜"),
        (["燉飯", "燴飯"], "🥘"),
        (["粥", "麥片", "穀片"], "🥣"),
        (["火鍋", "湯"], "🍲"),
        (["沙拉"], "🥗"),
        (["荷包蛋", "炒蛋", "蛋捲"], "🍳"),
        (["蛋"], "🥚"),
        (["起司", "乳酪", "芝士"], "🧀"),
        (["奶油"], "🧈"),
        (["豆漿", "牛奶", "鮮乳", "優格", "優酪", "奶"], "🥛"),
        (["香蕉"], "🍌"),
        (["青蘋果"], "🍏"),
        (["蘋果"], "🍎"),
        (["芭樂", "梨"], "🍐"),
        (["橘", "柳丁", "柑", "柚"], "🍊"),
        (["葡萄"], "🍇"),
        (["西瓜"], "🍉"),
        (["哈密瓜", "香瓜"], "🍈"),
        (["草莓"], "🍓"),
        (["藍莓"], "🫐"),
        (["鳳梨"], "🍍"),
        (["芒果"], "🥭"),
        (["奇異果"], "🥝"),
        (["椰子", "椰奶"], "🥥"),
        (["酪梨"], "🥑"),
        (["桃"], "🍑"),
        (["櫻桃"], "🍒"),
        (["萊姆"], "🍋‍🟩"),
        (["檸檬"], "🍋"),
        (["橄欖"], "🫒"),
        (["地瓜", "番薯"], "🍠"),
        (["馬鈴薯", "洋芋"], "🥔"),
        (["玉米"], "🌽"),
        (["番茄"], "🍅"),
        (["茄子"], "🍆"),
        (["紅蘿蔔", "胡蘿蔔"], "🥕"),
        (["花椰菜", "青花菜"], "🥦"),
        (["菇", "蕈"], "🍄"),
        (["小黃瓜", "黃瓜"], "🥒"),
        (["辣椒"], "🌶️"),
        (["青椒", "甜椒"], "🫑"),
        (["洋蔥"], "🧅"),
        (["蒜"], "🧄"),
        (["薑"], "🫚"),
        (["青菜", "高麗菜", "菠菜", "地瓜葉", "空心菜", "蔬菜", "菜"], "🥬"),
        (["栗子"], "🌰"),
        (["堅果", "杏仁", "花生", "核桃", "腰果"], "🥜"),
        (["毛豆", "豌豆", "四季豆", "甜豆"], "🫛"),
        (["豆腐", "豆干", "豆"], "🫘"),
        (["龍蝦"], "🦞"),
        (["蝦"], "🍤"),
        (["蟹"], "🦀"),
        (["蚵", "生蠔", "牡蠣", "蛤蜊", "文蛤"], "🦪"),
        (["章魚"], "🐙"),
        (["花枝", "魷魚", "透抽", "小卷"], "🦑"),
        (["魚", "鮭", "鮪", "鯖"], "🐟"),
        (["雞"], "🍗"),
        (["牛排", "牛"], "🥩"),
        (["培根"], "🥓"),
        (["豬", "排骨", "肉"], "🍖"),
        (["飯", "米"], "🍚"),
        (["茶"], "🍵"),
        (["糖", "糖果"], "🍬"),
        (["鹽"], "🧂"),
        (["罐頭"], "🥫"),
        (["冰塊"], "🧊"),
        (["水"], "💧"),
    ]

    private static let categories: [String: String] = [
        "水果類": "🍎", "蔬菜類": "🥬", "肉類": "🍖", "魚貝類": "🐟", "蛋類": "🥚",
        "乳品類": "🥛", "穀物類": "🍚", "澱粉類": "🥔", "豆類": "🫘", "堅果及種子類": "🥜",
        "飲料類": "🧃", "糕餅點心類": "🍰", "糖類": "🍬", "油脂類": "🧈", "菇類": "🍄",
        "藻類": "🌿", "調味料及香辛料類": "🧂", "加工調理食品及其他類": "🍱",
    ]

    static func guess(name: String, category: String? = nil) -> String {
        for entry in keywords where entry.words.contains(where: { name.contains($0) }) {
            return entry.emoji
        }
        if let category, let emoji = categories[category] { return emoji }
        return fallback
    }
}
