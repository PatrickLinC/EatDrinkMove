import SwiftUI

// MARK: - 像素方框

/// 四個角各缺一格的方框，像素遊戲的視窗外形
struct PixelRect: Shape {
    var step: CGFloat = 3

    func path(in r: CGRect) -> Path {
        let s = min(step, r.width / 2, r.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + s, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.minY + s))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + s))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - s))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.maxY - s))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.maxY - s))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - s))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + s))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.minY + s))
        p.closeSubpath()
        return p
    }
}

/// 像素視窗的底：右下硬陰影 + 邊框 + 底色
struct PixelPanel: View {
    var fill: Color = .window
    var border: Color = .ink
    var shadow: Color? = .pxShadow
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            if let shadow {
                PixelRect(step: lineWidth).fill(shadow).offset(x: lineWidth, y: lineWidth)
            }
            PixelRect(step: lineWidth).fill(border)
            PixelRect(step: lineWidth).fill(fill).padding(lineWidth)
        }
    }
}

extension View {
    func pixelPanel(fill: Color = .window, border: Color = .ink, shadow: Color? = .pxShadow,
                    lineWidth: CGFloat = 3) -> some View {
        background { PixelPanel(fill: fill, border: border, shadow: shadow, lineWidth: lineWidth) }
    }
}

// MARK: - 格子進度條

/// 一格一格的血條。超過目標時整條變成警告色（喝水、步數這種越多越好的不會）
struct PixelBar: View {
    var value: Double
    var total: Double
    var color: Color
    var segments: Int = 10
    var height: CGFloat = 12
    var overIsBad = true

    var body: some View {
        let ratio = total > 0 ? max(value, 0) / total : 0
        let filled = value <= 0 ? 0 : min(segments, max(1, Int((ratio * Double(segments)).rounded(.up))))
        let fillColor = overIsBad && ratio > 1 ? Color.danger : color

        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                Rectangle().fill(index < filled ? fillColor : Color.track)
            }
        }
        .frame(height: height)
        .padding(3)
        .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: 2))
        .accessibilityElement()
        .accessibilityValue("\(Int((ratio * 100).rounded()))%")
    }
}

// MARK: - 像素圖示

/// 用字元畫的像素圖：每個字元是一格，「.」是透明
struct PixelArt {
    let rows: [[Character]]

    init(_ rows: [String]) {
        self.rows = rows.map(Array.init)
    }

    /// 把某個字元換成另一個（小夥伴眨眼時把眼睛 e 換成臉的顏色）
    func replacing(_ from: Character, with to: Character) -> PixelArt {
        PixelArt(rows.map { String($0.map { $0 == from ? to : $0 }) })
    }

    /// 一次換好幾個顏色（互換也可以，例如綠換藍、藍換綠）
    func recolored(_ mapping: [Character: Character]) -> PixelArt {
        PixelArt(rows.map { String($0.map { mapping[$0] ?? $0 }) })
    }

    /// 字元對應的顏色：k 邊框、e 眼睛、h 眼睛亮點、w 視窗白、s 次要、b 主色、c 熱量、a 水、g 運動、y 黃、p 紅、t 空格、f 紫
    static func color(for character: Character) -> Color? {
        switch character {
        case "k", "e": .ink
        case "w", "h": .window
        case "s": .soft
        case "b": .brand
        case "c": .calorie
        case "a": .water
        case "g": .move
        case "y": .carbs
        case "p": .protein
        case "t": .track
        case "f": .fat
        default: nil
        }
    }
}

struct PixelSprite: View {
    let art: PixelArt
    var size: CGFloat = 24
    /// 指定時整張圖都畫成這個顏色（圖鑑裡還沒解鎖的剪影）
    var tint: Color?

    var body: some View {
        Canvas { context, canvasSize in
            let height = art.rows.count
            let width = art.rows.map(\.count).max() ?? 0
            guard width > 0, height > 0 else { return }
            let cell = min(canvasSize.width / CGFloat(width), canvasSize.height / CGFloat(height))
            let originX = (canvasSize.width - cell * CGFloat(width)) / 2
            let originY = (canvasSize.height - cell * CGFloat(height)) / 2
            for (y, row) in art.rows.enumerated() {
                for (x, character) in row.enumerated() {
                    guard let original = PixelArt.color(for: character) else { continue }
                    let color = tint ?? original
                    // 多畫一點點，避免格子之間出現細縫
                    let rect = CGRect(x: originX + CGFloat(x) * cell, y: originY + CGFloat(y) * cell,
                                      width: cell + 0.3, height: cell + 0.3)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension PixelArt {
    static let bowl = PixelArt([
        "...s...s....",
        "....s...s...",
        "...s...s....",
        "...kkkkkk...",
        "..kwwwwwwk..",
        ".kwwwwwwwwk.",
        "kkkkkkkkkkkk",
        "kcccccccccck",
        ".kcccccccck.",
        "..kcccccck..",
        "...kkkkkk...",
        "..kkkkkkkk..",
    ])

    static let drop = PixelArt([
        ".....kk.....",
        "....kaak....",
        "....kaak....",
        "...kaaaak...",
        "...kaaaak...",
        "..kaaaaaak..",
        "..kawaaaak..",
        ".kaawaaaaak.",
        ".kaaaaaaaak.",
        ".kaaaaaaaak.",
        "..kaaaaaak..",
        "...kkkkkk...",
    ])

    static let dumbbell = PixelArt([
        "............",
        "............",
        "............",
        ".kk......kk.",
        "kwgk....kwgk",
        "kggkkkkkkggk",
        "kggksssskggk",
        "kggkkkkkkggk",
        "kggk....kggk",
        ".kk......kk.",
        "............",
        "............",
    ])

    static let scale = PixelArt([
        "............",
        ".kkkkkkkkkk.",
        ".kwwwwwwwwk.",
        ".kwkkkkkkwk.",
        ".kwkyyyykwk.",
        ".kwkkkkkkwk.",
        ".kwwwwwwwwk.",
        ".kwwwkkwwwk.",
        ".kwwwwwwwwk.",
        ".kkkkkkkkkk.",
        "..kk....kk..",
        "............",
    ])

    static let camera = PixelArt([
        "............",
        "...kkkk.....",
        "..kbbbbk....",
        "kkkkkkkkkkkk",
        "kbbbbbbbbbbk",
        "kbbbkkkkbbbk",
        "kbbkwaaakbbk",
        "kbbkaaaakbbk",
        "kbbkaaaakbbk",
        "kbbbkkkkbbbk",
        "kbbbbbbbbbbk",
        "kkkkkkkkkkkk",
    ])

    static let photo = PixelArt([
        "kkkkkkkkkkkk",
        "kwwwwwwwwwwk",
        "kwwwwwwwyywk",
        "kwwwwwwwyywk",
        "kwwwwwwwwwwk",
        "kwwwgwwwwwwk",
        "kwwgggwwgwwk",
        "kwgggggggggk",
        "kggggggggggk",
        "kkkkkkkkkkkk",
        "............",
        "............",
    ])

    static let label = PixelArt([
        "..kkkkkkkk..",
        "..kwwwwwwk..",
        "..kwkkkkwk..",
        "..kwwwwwwk..",
        "..kwkkkwwk..",
        "..kwwwwwwk..",
        "..kwkkkkwk..",
        "..kwwwwwwk..",
        "..kwkkwwwk..",
        "..kwwwwwwk..",
        "..kkkkkkkk..",
        "............",
    ])

    static let barcode = PixelArt([
        "............",
        "kkkkkkkkkkkk",
        "kwwwwwwwwwwk",
        "kwkwkkwkwkwk",
        "kwkwkkwkwkwk",
        "kwkwkkwkwkwk",
        "kwkwkkwkwkwk",
        "kwkwkkwkwkwk",
        "kwwwwwwwwwwk",
        "kkkkkkkkkkkk",
        "............",
        "............",
    ])

    static let search = PixelArt([
        "............",
        "..kkkk......",
        ".kwwwwk.....",
        "kwwwwwwk....",
        "kwwwwwwk....",
        "kwwwwwwk....",
        "kwwwwwwk....",
        ".kwwwwk.....",
        "..kkkkkk....",
        "......kkk...",
        ".......kkk..",
        "........kk..",
    ])

    static let star = PixelArt([
        ".....kk.....",
        ".....kk.....",
        "....kyyk....",
        "kkkkyyyykkkk",
        ".kyyyyyyyyk.",
        "..kyyyyyyk..",
        "...kyyyyk...",
        "..kyykkyyk..",
        ".kyyk..kyyk.",
        ".kkk....kkk.",
        "............",
        "............",
    ])

    /// 睡眠：彎月
    static let moon = PixelArt([
        "....kkkk....",
        "..kkyyyk....",
        ".kyyyyk.....",
        ".kyyyk......",
        "kyyyyk......",
        "kyyyyk......",
        "kyyyyyk.....",
        "kyyyyyykkkk.",
        ".kyyyyyyyyk.",
        ".kkyyyyyykk.",
        "...kkkkkk...",
        "............",
    ])

    /// 步數：腳印
    static let footprint = PixelArt([
        "......k.k.k.",
        "............",
        ".......kkk..",
        "k.k.k.kgggk.",
        "......kgggk.",
        ".kkk..kgggk.",
        "kgggk..kgk..",
        "kgggk..kkk..",
        "kgggk.......",
        ".kgk........",
        ".kkk........",
        "............",
    ])

    /// 還沒解鎖：鎖頭
    static let lock = PixelArt([
        "............",
        "....kkkk....",
        "...kssssk...",
        "..ks....sk..",
        "..ks....sk..",
        ".kkkkkkkkkk.",
        ".kyyyyyyyyk.",
        ".kyyykkyyyk.",
        ".kyyykkyyyk.",
        ".kyyyyyyyyk.",
        ".kkkkkkkkkk.",
        "............",
    ])

    /// 元氣幣
    static let coin = PixelArt([
        "....kkkk....",
        "..kkyyyykk..",
        ".kywyyyyyck.",
        ".kwyyycyyck.",
        "kyyyyycyyyck",
        "kyyyyycyyyck",
        "kyyyyycyyyck",
        "kyyyyycyyyck",
        ".kyyyycyyck.",
        ".kyyyyyycck.",
        "..kkccccck..",
        "....kkkk....",
    ])

    /// 睡前營火（和 campfireFlicker 輪流顯示）
    static let campfire = PixelArt([
        "................",
        ".......kk.......",
        "......kpk.......",
        "......kpk..k....",
        ".....kpcpk.kk...",
        "..k..kpccpk.pk..",
        "..kk.kpcyccpkpk.",
        ".kpkkpcyyycpcpk.",
        ".kpcpcyywyycpck.",
        ".kpccyywwwyyccpk",
        "..kpcyywwwyyck..",
        "...kkkkkkkkkk...",
        ".kkbbbkkkkbbbkk.",
        "kbbbbbbkkbbbbbbk",
        ".kkkbbbbbbbbkkk.",
        "....kkkkkkkk....",
    ])

    /// 營火的第二格
    static let campfireFlicker = PixelArt([
        "................",
        "........kk......",
        "........kpk.....",
        "...k....kpk.....",
        "..kk...kpcpk....",
        "..kpk.kpccpk..k.",
        ".kpk.kpccycpkkk.",
        ".kpckpcyycccpck.",
        ".kpcpcyyywycpck.",
        "kpccyywwwyyyccpk",
        "..kcyywwwwyyck..",
        "...kkkkkkkkkk...",
        ".kkbbbkkkkbbbkk.",
        "kbbbbbbkkbbbbbbk",
        ".kkkbbbbbbbbkkk.",
        "....kkkkkkkk....",
    ])

    /// 地圖：米糧村
    static let landmarkHouse = PixelArt([
        "................",
        ".......kk.......",
        "......kppk......",
        ".....kppppk..kk.",
        "....kppppppk.kbk",
        "...kppppppppkkbk",
        "..kppppppppppkbk",
        ".kkkkkkkkkkkkkkk",
        "..kwwwwwwwwwwk..",
        "..kwkkkwwkkkwk..",
        "..kwkakwwkakwk..",
        "..kwkkkwwkkkwk..",
        "..kwwwwkkwwwwk..",
        "..kwwwwkbkwwwk..",
        "..kwwwwkbkwwwk..",
        ".kkkkkkkkkkkkkk.",
    ])

    /// 地圖：步道山谷
    static let landmarkMountain = PixelArt([
        "................",
        ".......kk.......",
        "......kwwk......",
        ".....kwwwwk.....",
        "....kwgwwgwk....",
        "....kgggggk.k...",
        "...kgggggggkwk..",
        "...kggggggkwwwk.",
        "..kgggggggkgwgk.",
        "..kggggggggggggk",
        ".kgggbgggggggggk",
        ".kggbbbggggggggk",
        "kgggbbbggggggggk",
        "kggbbbbbgggggggk",
        "kgbbbbbbbggggggk",
        "kkkkkkkkkkkkkkkk",
    ])

    /// 地圖：晨光丘
    static let landmarkDawn = PixelArt([
        "................",
        "......kkkk......",
        "..k..kyyyyk..k..",
        "...kkyyyyyykk...",
        "....kyyyyyyk....",
        "kk.kyyyyyyyyk.kk",
        "...kyyyyyyyyk...",
        "..kkkkkkkkkkkk..",
        ".kggggggggggggk.",
        "kggggggggggggggk",
        "kgggggggggggcggk",
        "kggcggggggggggk.",
        "kgggggggcgggggk.",
        ".kgggggggggggk..",
        "..kkkkkkkkkkk...",
        "................",
    ])

    /// 地圖：夢之森
    static let landmarkTree = PixelArt([
        "................",
        "......kkkk......",
        "....kkggggkk....",
        "...kggggggggk...",
        "..kgggggwggggk..",
        "..kggwggggggak..",
        ".kgggggggggggak.",
        ".kgggggggwggggk.",
        ".kggwgggggggggk.",
        "..kggggggggagk..",
        "...kkggggggkk...",
        ".....kkbbkk.....",
        "......kbbk......",
        "......kbbk......",
        ".....kbbbbk.....",
        "....kkkkkkkk....",
    ])

    /// 地圖：月影沼澤
    static let landmarkMarsh = PixelArt([
        "................",
        "...........kk...",
        "..........kyyk..",
        "..........kyk...",
        "...k.......kk...",
        "..kgk...k.......",
        "..kgk..kgk......",
        "..kgk..kgk..k...",
        "..kgk..kgk.kgk..",
        "kkkgkkkkgkkkgkkk",
        "kffffffffffffffk",
        "kfffwffffffwfffk",
        "kffffffffffffffk",
        "kfffffwffffffffk",
        ".kffffffffffffk.",
        "..kkkkkkkkkkkk..",
    ])

    /// 地圖：王城
    static let landmarkCastle = PixelArt([
        "................",
        "..kk........kk..",
        "..kpk.......kpk.",
        "..kppk......kppk",
        "..kk........kk..",
        ".kkkk......kkkk.",
        ".kssk......kssk.",
        ".kssk.kkkk.kssk.",
        ".ksskkkaakkkssk.",
        ".kssssssssssssk.",
        ".kskssssssssksk.",
        ".kssssssssssssk.",
        ".ksssskkkkssssk.",
        ".ksssskbbkssssk.",
        ".ksssskbbkssssk.",
        "kkkkkkkkkkkkkkkk",
    ])

    /// 壞習慣怪物：熬夜蝠
    static let monsterBat = PixelArt([
        "................",
        "................",
        "....kk....kk....",
        "...kfk....kfk...",
        "k..kfkkkkkkfk..k",
        "kk.kffffffffk.kk",
        "kfkkfeffffefkkfk",
        "kffkfkffffkfkffk",
        "kfffkfpffpfkfffk",
        "kffffkfwwfkffffk",
        ".kfffkffffkfffk.",
        "..kffkffffkffk..",
        "...kk.kffk.kk...",
        "......kffk......",
        ".......kk.......",
        "................",
    ])

    /// 壞習慣怪物：沙發怪
    static let monsterSofa = PixelArt([
        "................",
        "................",
        "..kkkkkkkkkkkk..",
        ".kbbbbbbbbbbbbk.",
        ".kbbebbbbbbebbk.",
        ".kbbkbbbbbbkbbk.",
        ".kbbbbbkkbbbbbk.",
        "kkkbbbbbbbbbbkkk",
        "kbkkkkkkkkkkkkbk",
        "kbkppppppppppkbk",
        "kbkppppppppppkbk",
        "kbkkkkkkkkkkkkbk",
        "kbbbbbbbbbbbbbbk",
        "kkkkkkkkkkkkkkkk",
        ".kk..........kk.",
        "................",
    ])

    /// 壞習慣怪物：焦慮霧
    static let monsterFog = PixelArt([
        "................",
        "................",
        "....kkkkkkkk....",
        "..kkttttttttkk..",
        ".kttttttttttttk.",
        "kttssttttttssttk",
        "ktttettttttetttk",
        "ktttkttttttktttk",
        "kttttttttttttttk",
        "kttttskkkksttttk",
        ".kttttsttsttttk.",
        "..kkkkkkkkkkkk..",
        "................",
        "................",
        "................",
        "................",
    ])

    /// 旅途見聞：寶箱
    static let chest = PixelArt([
        "................",
        "................",
        "..kkkkkkkkkkkk..",
        ".kbbbbbbbbbbbbk.",
        ".kbbbbbbbbbbbbk.",
        ".kyyyyyyyyyyyyk.",
        ".kkkkkkykkkkkkk.",
        ".kbbbbkyykbbbbk.",
        ".kbbbbkkkkbbbbk.",
        ".kbbbbbbbbbbbbk.",
        ".kyybbbbbbbbyyk.",
        ".kkkkkkkkkkkkkk.",
        "................",
        "................",
        "................",
        "................",
    ])

    /// 營地：帳篷
    static let campTent = PixelArt([
        "................",
        ".......kk.......",
        "......kcck......",
        ".....kcccck.....",
        "....kcccccck....",
        "...kcccccccck...",
        "...kcccccccck...",
        "..kcccccccccck..",
        "..kcccccccccck..",
        ".kcccccccccccck.",
        ".kccccckkccccck.",
        "kccccckbbkccccck",
        "kcccckbbbbkcccck",
        "kccckbbbbbbkccck",
        "kccckbbbbbbkccck",
        "kkkkkkkkkkkkkkkk",
    ])

    /// 營地：小木屋
    static let campCabin = PixelArt([
        "................",
        ".......kk.......",
        "......kbbk......",
        ".....kbbbbk.....",
        "....kbbbbbbk....",
        "...kbbbbbbbbk...",
        "..kbbbbbbbbbbk..",
        ".kkkkkkkkkkkkkk.",
        "..kbbbbbbbbbbk..",
        "..kbkkkbbbbbbk..",
        "..kbkakbbkkkbk..",
        "..kbkkkbbkykbk..",
        "..kbbbbbbkkkbk..",
        "..kbbbbbbkykbk..",
        "..kbbbbbbkykbk..",
        "kkkkkkkkkkkkkkkk",
    ])

    /// 營地：石屋
    static let campStone = PixelArt([
        "................",
        ".......kk.......",
        "......kppk......",
        ".....kppppk.....",
        "....kppppppk....",
        "...kppppppppk...",
        "..kppppppppppk..",
        ".kkkkkkkkkkkkkk.",
        "..kssssssssssk..",
        "..kskkkssssssk..",
        "..kskaksskkksk..",
        "..kskkksskbksk..",
        "..ksssssskkksk..",
        "..ksssssskbksk..",
        "..ksssssskbksk..",
        "kkkkkkkkkkkkkkkk",
    ])

    /// 營地：菜園
    static let campGarden = PixelArt([
        "................",
        "................",
        "...g...g...g....",
        "..kgk.kgk.kgk...",
        "..gkg.gkg.gkg...",
        "...k...k...k....",
        "kkkkkkkkkkkkkkkk",
        "kbbbbbbbbbbbbbbk",
        "kbbpbbbcbbbpbbbk",
        "kbkgkbkgkbkgkbbk",
        "kbbbbbbbbbbbbbbk",
        "kbbgbbbpbbbgbbbk",
        "kbkgkbkgkbkgkbbk",
        "kbbbbbbbbbbbbbbk",
        "kkkkkkkkkkkkkkkk",
        "................",
    ])

    /// 營地：聖泉
    static let campWell = PixelArt([
        "................",
        "..kkkkkkkkkkkk..",
        "..kbbbbbbbbbbk..",
        ".kbbbbbbbbbbbbk.",
        "..kb........bk..",
        "..kb........bk..",
        "..kb..kkkk..bk..",
        "..kb.kaaaak.bk..",
        "kkkkkkkkkkkkkkkk",
        "kssksssssssskssk",
        "ksssssskkssssssk",
        "kaaaaaaaaaaaaaak",
        "kawaaaaaaaaaawak",
        "ksssssskkssssssk",
        "kssksssssssskssk",
        "kkkkkkkkkkkkkkkk",
    ])

    /// 營地：瞭望台
    static let campTower = PixelArt([
        ".......kk.......",
        "......kppk......",
        "......kppk......",
        ".....kkkkkk.....",
        "..kkkkkkkkkkkk..",
        "..kbbbbbbbbbbk..",
        "...kbbbbbbbbk...",
        "...kbbkkkkbbk...",
        "...kbbkawkbbk...",
        "...kbbkkkkbbk...",
        "...kbbbbbbbbk...",
        "...kbkbbbbkbk...",
        "...kbbbbbbbbk...",
        "..kbbbkbbkbbbk..",
        "..kbbbbbbbbbbk..",
        "kkkkkkkkkkkkkkkk",
    ])

    /// 營地：精靈小屋
    static let campSpiritHouse = PixelArt([
        "................",
        "................",
        ".....kkkkkk.....",
        "....kffffffk....",
        "...kffffffffk...",
        "..kffffffffffk..",
        ".kkkkkkkkkkkkkk.",
        "..kwwwwwwwwwwk..",
        "..kwwkkkkkkwwk..",
        "..kwkyyyyyykwk..",
        "..kwkykyykykwk..",
        "..kwkyyyyyykwk..",
        "..kwwkkkkkkwwk..",
        "..kwwwwwwwwwwk..",
        "..kwwwwwwwwwwk..",
        "kkkkkkkkkkkkkkkk",
    ])

    /// 營地：花圃
    static let campFlowers = PixelArt([
        "................",
        "................",
        "................",
        "..k...k.....k...",
        ".kpk.kyk...kfk..",
        "..k...k.....k...",
        "..g.k.g..k..g...",
        "..gkpkg.kyk.g...",
        "..g.k.g..k..g...",
        ".ggg.ggg.g.ggg..",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
    ])

    /// 營地：旗幟
    static let campBanner = PixelArt([
        "...k............",
        "..kyk...........",
        "...kkkkkkkkk....",
        "...kkppppppk....",
        "...kkppyyppk....",
        "...kkpyyyypk....",
        "...kkppyyppk....",
        "...kkppppppk....",
        "...kkppkkppk....",
        "...kkpk..kpk....",
        "...kkk....k.....",
        "...kk...........",
        "...kk...........",
        "...kk...........",
        "..kkkk..........",
        "................",
    ])

    /// 營地：路燈
    static let campLamp = PixelArt([
        "......kkkk......",
        ".....kyyyyk.....",
        ".....kywwyk.....",
        ".....kyyyyk.....",
        "......kkkk......",
        ".......kk.......",
        ".......kk.......",
        ".......kk.......",
        ".......kk.......",
        ".......kk.......",
        ".......kk.......",
        ".......kk.......",
        ".......kk.......",
        "......kkkk......",
        ".....kkkkkk.....",
        "................",
    ])

    /// 壞習慣怪物：旱地仙人掌（水喝太少）
    static let monsterCactus = PixelArt([
        "................",
        ".....kkkkkk.....",
        "....kggwgggk....",
        "....kggggggkkk..",
        "..kkkkkggkkgggk.",
        ".kggggeggeggggk.",
        ".kggggggggggggk.",
        ".kggggkggkgkkkk.",
        ".kkkkggkkggk....",
        "....kggggggk....",
        "....kggggggk....",
        "...kkkkkkkkkk...",
        "...kcccccccck...",
        "...kcccccccck...",
        "...kcccccccck...",
        "....kkkkkkkk....",
    ])

    /// 壞習慣怪物：健忘書蟲（忘記記錄）
    static let monsterWorm = PixelArt([
        "............kk..",
        "...........k..k.",
        "..............k.",
        "......kkkk...k..",
        ".....kppppk.....",
        "....kpeppepk.k..",
        "....kpkppkpk....",
        "....kppkkppk....",
        ".....kppppk.....",
        "kkkkkkkppkkkkkkk",
        "kwwwwwwkkwwwwwwk",
        "kwssswwkkwssswwk",
        "kwwwwwwkkwwwwwwk",
        "kwssswwkkwssswwk",
        "kkkkkkkkkkkkkkkk",
        "................",
    ])

    static let mic = PixelArt([
        "....kkkk....",
        "...kbbbbk...",
        "...kbbbbk...",
        "...kbbbbk...",
        "...kbbbbk...",
        ".k.kbbbbk.k.",
        ".k..kkkk..k.",
        "..k......k..",
        "...kkkkkk...",
        ".....kk.....",
        "...kkkkkk...",
        "............",
    ])

    static let home = PixelArt([
        ".....kk.....",
        "....kbbk....",
        "...kbbbbk...",
        "..kbbbbbbk..",
        ".kbbbbbbbbk.",
        "kkkkkkkkkkkk",
        ".kwwwwwwwwk.",
        ".kwkkwwwwwk.",
        ".kwkkwwkkwk.",
        ".kwwwwwkkwk.",
        ".kwwwwwkkwk.",
        ".kkkkkkkkkk.",
    ])

    static let book = PixelArt([
        "............",
        ".kkkkkkkkkk.",
        ".kbbbbbbbbk.",
        ".kbwwwwwwbk.",
        ".kbwkkkkwbk.",
        ".kbwwwwwwbk.",
        ".kbwkkkwwbk.",
        ".kbwwwwwwbk.",
        ".kbbbbbbbbk.",
        ".kwwwwwwwwk.",
        ".kkkkkkkkkk.",
        "............",
    ])

    static let trophy = PixelArt([
        "............",
        "..kkkkkkkk..",
        "kkkyyyyyykkk",
        "k.kyyyyyyk.k",
        "k.kyyyyyyk.k",
        ".kkyyyyyykk.",
        "...kyyyyk...",
        "....kyyk....",
        ".....kk.....",
        "....kyyk....",
        "...kkkkkk...",
        "...kbbbbk...",
    ])

    static let hero = PixelArt([
        "....kkkk....",
        "...kbbbbk...",
        "..kbbbbbbk..",
        "..kwwwwwwk..",
        "..kwkwwkwk..",
        "..kwwwwwwk..",
        "...kkkkkk...",
        "..kcccccck..",
        ".kwkcccckwk.",
        "..kcccccck..",
        "...kk..kk...",
        "...kk..kk...",
    ])

    static let bell = PixelArt([
        ".....kk.....",
        "....kyyk....",
        "...kyyyyk...",
        "...kyyyyk...",
        "..kyyyyyyk..",
        "..kyyyyyyk..",
        "..kyyyyyyk..",
        ".kyyyyyyyyk.",
        "kkkkkkkkkkkk",
        "....kyyk....",
        ".....kk.....",
        "............",
    ])

    static let controller = PixelArt([
        "............",
        "..kkkkkkkk..",
        ".kwwwwwwwwk.",
        "kwwkwwwwwpwk",
        "kwkkkwwwpwpk",
        "kwwkwwwwwpwk",
        "kwwwwkkwwwwk",
        ".kwwk..kwwk.",
        "..kk....kk..",
        "............",
        "............",
        "............",
    ])

    /// 左右箭頭（像素字體沒有 ◀ ▶，系統會換成彩色 emoji，所以自己畫）
    static let arrowLeft = PixelArt([
        "....k.",
        "...kk.",
        "..kkk.",
        ".kkkk.",
        "..kkk.",
        "...kk.",
        "....k.",
    ])

    static let arrowRight = PixelArt([
        ".k....",
        ".kk...",
        ".kkk..",
        ".kkkk.",
        ".kkk..",
        ".kk...",
        ".k....",
    ])

    static let cursor = PixelArt([
        ".b....",
        ".bb...",
        ".bbb..",
        ".bbbb.",
        ".bbb..",
        ".bb...",
        ".b....",
    ])

    static let calendar = PixelArt([
        "..k....k....",
        "kkkkkkkkkkkk",
        "kppppppppppk",
        "kkkkkkkkkkkk",
        "kwwwwwwwwwwk",
        "kwkwkwkwkwwk",
        "kwwwwwwwwwwk",
        "kwkwkwkwkwwk",
        "kwwwwwwwwwwk",
        "kwkwkwwwwwwk",
        "kwwwwwwwwwwk",
        "kkkkkkkkkkkk",
    ])

    /// AI 小夥伴「小卡」：會說話的飯糰精靈
    static let companion = PixelArt([
        "......kkkk......",
        ".....kwwwwk.....",
        "....kwwwwwwk....",
        "...kwwwwwwwwk...",
        "...kwwwwwwwwk...",
        "..kwwkwwwwkwwk..",
        "..kwwkwwwwkwwk..",
        ".kwwwwwwwwwwwwk.",
        ".kwpwwwkkwwwpwk.",
        "kwwwwwwwwwwwwwwk",
        "kwwwkkkkkkkkwwwk",
        "kwwwkkkkkkkkwwwk",
        "kwwwkkkkkkkkwwwk",
        ".kwwkkkkkkkkwwk.",
        "..kkkkkkkkkkkk..",
        "................",
    ])

    /// 眨眼的那一格
    static let companionBlink = PixelArt([
        "......kkkk......",
        ".....kwwwwk.....",
        "....kwwwwwwk....",
        "...kwwwwwwwwk...",
        "...kwwwwwwwwk...",
        "..kwwwwwwwwwwk..",
        "..kwkkwwwwkkwk..",
        ".kwwwwwwwwwwwwk.",
        ".kwpwwwkkwwwpwk.",
        "kwwwwwwwwwwwwwwk",
        "kwwwkkkkkkkkwwwk",
        "kwwwkkkkkkkkwwwk",
        "kwwwkkkkkkkkwwwk",
        ".kwwkkkkkkkkwwk.",
        "..kkkkkkkkkkkk..",
        "................",
    ])

    // 小夥伴的其他造型（e 是會眨的眼睛）

    static let companionBoba = PixelArt([
        "..........kk....",
        ".........kpk....",
        "...kkkkkkpkkk...",
        "...kwwwwwpwwk...",
        "...kbbbbbpbbk...",
        "...kbbbbbbbbk...",
        "...kbebbbbebk...",
        "...kbkbbbbkbk...",
        "...kbbbkkbbbk...",
        "...kbbbbbbbbk...",
        "...kbkbbkbbkk...",
        "...kkbkkbkkbk...",
        "....kkkkkkkk....",
        "................",
        "................",
        "................",
    ])

    static let companionBun = PixelArt([
        "................",
        ".......kk.......",
        "......kwwk......",
        "....kkwtwwkk....",
        "...kwwtwwtwwk...",
        "..kwwwwwwwwwwk..",
        "..kwwewwwwewwk..",
        ".kwwwkwwwwkwwwk.",
        ".kwpwwwkkwwwpwk.",
        "kwwwwwwwwwwwwwwk",
        "kttttttttttttttk",
        ".kkkkkkkkkkkkkk.",
        "................",
        "................",
        "................",
        "................",
    ])

    static let companionEgg = PixelArt([
        "................",
        "....kkkkkk......",
        "...kwwwwwwkkk...",
        "..kwwwwwwwwwwk..",
        ".kwwwkkkkkkwwwk.",
        "kwwkkyyyyyykkwwk",
        "kwwkyeyyyyeykwwk",
        "kwwkykyyyykykwwk",
        "kwwkkyykkyykkwwk",
        ".kwwwkkkkkkwwwk.",
        ".kwwwwwwwwwwwk..",
        "..kkwwwwwwwkk...",
        "....kkkkkkk.....",
        "................",
        "................",
        "................",
    ])

    static let companionGoblin = PixelArt([
        "................",
        "......kkkk......",
        ".....kggggk.....",
        "....kggggggk....",
        "k..kggggggggk..k",
        "kgkggeggggeggkgk",
        ".kgggkggggkgggk.",
        "..kkggggggggkk..",
        "...kgkkkkkkkgk..",
        "...kgkwkwkwkgk..",
        "....kgkkkkkgk...",
        ".....kgggggk....",
        "....kbbbbbbbk...",
        "....kbkbbbkbk...",
        "....kgk...kgk...",
        "....kkk...kkk...",
    ])

    static let companionSlime = PixelArt([
        "................",
        "................",
        "................",
        "................",
        "......kkkk......",
        "....kkaaaakk....",
        "...kaaaaaaaak...",
        "..kawaaaaaaaak..",
        "..kaaeaaaaeaak..",
        ".kaaakaaaakaaak.",
        ".kaapaakkaapaak.",
        "kaaaaaaaaaaaaaak",
        "kaaaaaaaaaaaaaak",
        ".kkkkkkkkkkkkkk.",
        "................",
        "................",
    ])

    static let companionCat = PixelArt([
        "................",
        ".kk..........kk.",
        ".kck........kck.",
        ".kcpk......kpck.",
        ".kccpkkkkkkpcck.",
        "kcccccbccbccccck",
        "kccccccbbcccccck",
        "kcccecccccceccck",
        "kccckcccccckccck",
        "kccccwwppwwcccck",
        "kccccwkwwkwcccck",
        ".kccccwwwwcccck.",
        "..kkcccccccckk..",
        "...kcckkkkcck...",
        "...kkk....kkk...",
        "................",
    ])

    static let companionDog = PixelArt([
        "................",
        "....kkkkkkkk....",
        "..kkyyyyyyyykk..",
        ".kbyyyyyyyyyybk.",
        "kbbyyyyyyyyyybbk",
        "kbbyehyyyyehybbk",
        "kbbykkyyyykkybbk",
        "kbbpyyttttyypbbk",
        ".kbyyttkkttyybk.",
        ".kbyyttttttyybk.",
        "..kbyyttttyybk..",
        "...kkyyyyyykk...",
        ".....kyyyyk.....",
        "....kyyyyyyk....",
        "....kykyykyk....",
        "....kkk..kkk....",
    ])

    /// 精靈：寶箱怪
    static let companionMimic = PixelArt([
        "................",
        "...kkkkkkkkkk...",
        "..kbbbbbbbbbbk..",
        ".kbbbbbbbbbbbbk.",
        ".kyyyyyyyyyyyyk.",
        ".kbbebbbbbbebbk.",
        ".kbbkbbyybbkbbk.",
        ".kbbbbbkkbbbbbk.",
        ".kkkkkkkkkkkkkk.",
        ".kwkwkwkkwkwkwk.",
        ".kkkkkppppkkkkk.",
        ".kwkwkwkkwkwkwk.",
        ".kkkkkkkkkkkkkk.",
        ".kbbbbbbbbbbbbk.",
        ".kyybbbbbbbbyyk.",
        ".kkkkkkkkkkkkkk.",
    ])
    /// 精靈：獅鷲
    static let companionGriffin = PixelArt([
        "................",
        "......kkkk......",
        "....kkwwwwkk....",
        "...kwwwwwwwwk...",
        "...kwwewwewwk...",
        "...kwwkyykwwk...",
        "kk..kwwyywwk..kk",
        "kyk..kwwwwk..kyk",
        "kyyk.kcccck.kyyk",
        "kyyykcccccckyyyk",
        ".kyykcccccckyyk.",
        "..kkkcccccckkk..",
        "....kcccccck....",
        "....kckkkkck....",
        "....kck..kck....",
        "....kkk..kkk....",
    ])
    /// 精靈：蘑菇怪
    static let companionMushroom = PixelArt([
        "................",
        ".....kkkkkk.....",
        "...kkppppppkk...",
        "..kppwwppppppk..",
        ".kppwwppppwwppk.",
        ".kpppppppwwpppk.",
        "kppwwppppppppppk",
        "kkkkkkkkkkkkkkkk",
        "...kwwwwwwwwk...",
        "...kwewwwwewk...",
        "...kwkwwwwkwk...",
        "...kwpwkkwpwk...",
        "...kwwwwwwwwk...",
        "....kwwwwwwk....",
        "....kwk..kwk....",
        "....kkk..kkk....",
    ])
    /// 精靈：小幽靈
    static let companionGhost = PixelArt([
        "................",
        "......kkkk......",
        "....kkwwwwkk....",
        "...kwwwwwwwwk...",
        "..kwwwwwwwwwwk..",
        "..kwwewwwwewwk..",
        "..kwwkwwwwkwwk..",
        ".kwwpwwkkwwpwwk.",
        ".kwwwwwkkwwwwwk.",
        "kwkwwwwwwwwwwkwk",
        "kkwwwwwwwwwwwwkk",
        ".kwwwwwwwwwwwwk.",
        ".kwwwwwwwwwwwwk.",
        ".kwwkwwwkwwwkwk.",
        ".kwk.kwk.kwk.kk.",
        "..k...k...k.....",
    ])
    /// 精靈：見習巫師
    static let companionWizard = PixelArt([
        ".......kk.......",
        "......kffk......",
        ".....kfffk......",
        ".....kffffk.....",
        "....kffyfffk....",
        "...kffffffffk...",
        ".kkkkkkkkkkkkkk.",
        "..kwwwwwwwwwwk..",
        "..kwwewwwwewwk..",
        "..kwwkwwwwkwwk..",
        "..kwpwwkkwwpwk..",
        "...kkwwwwwwkk...",
        "..kffkkkkkkffk..",
        ".kfffffyyfffffk.",
        ".kffkffffffkffk.",
        ".kkkkkkkkkkkkkk.",
    ])
    /// 精靈：骷髏兵
    static let companionSkeleton = PixelArt([
        "................",
        ".....kkkkkk.....",
        "....kwwwwwwk....",
        "...kwwwwwwwwk...",
        "...kweewweewk...",
        "...kwkkwwkkwk...",
        "...kwwwkkwwwk...",
        "....kwkwkwkk....",
        ".....kkkkkk.....",
        "...kkkwwwwkkk...",
        "..kwkwkkkkwkwk..",
        "..kwkwwwwwwkwk..",
        "...kkwkkkkwkk...",
        "....kwk..kwk....",
        "....kwk..kwk....",
        "....kkk..kkk....",
    ])
    /// 精靈：見習騎士
    static let companionKnight = PixelArt([
        "................",
        ".......kk.......",
        "......kppk......",
        ".......kpk......",
        ".....kkkkkk.....",
        "....kssssssk....",
        "...kssssssssk...",
        "...kskkkkkksk...",
        "...kswewwewsk...",
        "...kswkwwkwsk...",
        "...kssswwsssk...",
        "....kkkkkkkk....",
        "..kskaayyaaksk..",
        "..kskaaaaaaksk..",
        "...kkkssssskk...",
        "....kkk..kkk....",
    ])
    /// 精靈：矮人鐵匠
    static let companionDwarf = PixelArt([
        "................",
        ".....kkkkkk.....",
        "....kssssssk....",
        "...kssssssssk...",
        "..kkkkkkkkkkkk..",
        "...kwwwwwwwwk...",
        "...kwewwwwewk...",
        "...kwkwppwkwk...",
        "..kcccwwwwccck..",
        "..kccccccccccck.",
        "..kcccccccccck..",
        "...kcccccccck...",
        "..kbkkccccckkbk.",
        "..kbbkkcckkbbk..",
        "...kbk....kbk...",
        "...kkk....kkk...",
    ])
    /// 精靈：龍寶寶
    static let companionDragon = PixelArt([
        "................",
        "..kk........kk..",
        "..kwk......kwk..",
        "...kkkkkkkkkk...",
        "..kggggggggggk..",
        "..kggeggggeggk..",
        "..kggkggggkggk..",
        "..kgggggggggggk.",
        "...kggyyyyggkk..",
        "kk..kkkkkkkk..kk",
        "kck.kgyyyygk.kck",
        "kcckkyyyyyykkcck",
        ".kcckyyyyyykcck.",
        "..kkkyyyyyykkk..",
        "....kgk..kgk....",
        "....kkk..kkk....",
    ])
    /// 晨光丘：太陽
    static let sun = PixelArt([
        ".....kk.....",
        ".k...kk...k.",
        "..k......k..",
        "....kkkk....",
        "...kyyyyk...",
        "kk.kyyyyk.kk",
        "kk.kyyyyk.kk",
        "...kyyyyk...",
        "....kkkk....",
        "..k......k..",
        ".k...kk...k.",
        ".....kk.....",
    ])
    static let companionParrot = PixelArt([
        "................",
        "......kkkk......",
        ".....kggggk.....",
        "....kgeggggk....",
        "...kkgkggggk....",
        "..kyykgggggggk..",
        "..kyyykgggggggk.",
        "...kkkppgggggggk",
        "....kpppggggaggk",
        "....kppppgggaagk",
        ".....kppggggaak.",
        "......kkggggak..",
        ".......kyykgggk.",
        "..........kgggk.",
        "...........kkk..",
        "................",
    ])

    static let heart = PixelArt([
        ".kk..kk.",
        "kppkkppk",
        "kppppppk",
        "kppppppk",
        ".kppppk.",
        "..kppk..",
        "...kk...",
        "........",
    ])

    static let cupFull = PixelArt([
        "kkkkkkkk",
        "kaaaaaak",
        "kawaaaak",
        "kaaaaaak",
        ".kaaaak.",
        ".kaaaak.",
        ".kaaaak.",
        ".kkkkkk.",
    ])

    static let cupEmpty = PixelArt([
        "kkkkkkkk",
        "k......k",
        "k......k",
        "k......k",
        ".k....k.",
        ".k....k.",
        ".k....k.",
        ".kkkkkk.",
    ])
}

// MARK: - 第八階段：新區域精靈、節慶精靈與節慶裝飾

extension PixelArt {
    /// 精靈：青蛙王子
    static let companionFrog = PixelArt([
        "................",
        "......k..k......",
        "..kk.kykkyk.kk..",
        ".kwwkkyyyykkwwk.",
        ".kwekggggggkewk.",
        ".kwkkggggggkkwk.",
        "kgkkggggggggkkgk",
        "kggggggggggggggk",
        "kgpgggkkkkgggpgk",
        "kggggggggggggggk",
        ".kggyyyyyyyyggk.",
        "..kgyyyyyyyygk..",
        ".kggkkkkkkkkggk.",
        "kgggk......kgggk",
        "kkkk........kkkk",
        "................",
    ])
    /// 精靈：小人魚
    static let companionMermaid = PixelArt([
        "................",
        "....kkkkkk......",
        "...kffffffk.....",
        "..kffffffffk....",
        "..kfwwwwwwfk....",
        "..kfwewwewfk....",
        "..kfwkwwkwfk....",
        "..kfpwwwwpfk....",
        "..kffkwwkffk....",
        ".kfkccwwcckfk...",
        ".kfkwwwwwwkfk...",
        "..kkaaaaaakk....",
        "...kaawaaaak.kk.",
        "....kaaaaaakkak.",
        ".....kkaaaaaaak.",
        ".......kkkkkkkk.",
    ])
    /// 精靈：獨角獸
    static let companionUnicorn = PixelArt([
        ".......kk.......",
        "......kyyk......",
        "..k...kyyk...k..",
        ".kwk..kyyk..kwk.",
        ".kwwkkkkkkkkwwk.",
        "..kwwwwwwwwwwk..",
        ".kfwwewwwwewwfk.",
        ".kfwwkwwwwkwwfk.",
        "kffpwwwwwwwwpffk",
        "kffwwwkwwkwwwffk",
        ".kfkwwwwwwwwkfk.",
        "..kkkwwwwwwkkk..",
        "...kwwwwwwwwk...",
        "...kwkwwwwkwk...",
        "...kwk....kwk...",
        "...kkk....kkk...",
    ])
    /// 精靈：貓頭鷹
    static let companionOwl = PixelArt([
        "................",
        "..kk........kk..",
        "..kbk......kbk..",
        "..kbbkkkkkkbbk..",
        ".kbbbbbbbbbbbbk.",
        ".kbwwwbbbbwwwbk.",
        "kbwwewwbbwwewwbk",
        "kbwwkwwbbwwkwwbk",
        "kbbwwwbyybwwwbbk",
        "kbbbbbbkkbbbbbbk",
        "kbbbssssssssbbbk",
        ".kbbsstsstssbbk.",
        "..kbbssssssbbk..",
        "...kkbbbbbbkk...",
        "....kykkkkyk....",
        "....kkk..kkk....",
    ])
    /// 精靈：見習僧侶
    static let companionMonk = PixelArt([
        "................",
        "......kkkk......",
        ".....kwwwwk.....",
        "....kwwwwwwk....",
        "...kwwwwwwwwk...",
        "...kwewwwwewk...",
        "...kwkwwwwkwk...",
        "...kwpwkkwpwk...",
        "....kwwwwwwk....",
        "...kcckwwkcck...",
        "..kcccbkkbccck..",
        "..kcccbwwbccck..",
        ".kcccccbbccccck.",
        "kcccccccccccccck",
        "kffffffffffffffk",
        ".kkkkkkkkkkkkkk.",
    ])
    /// 精靈：石像鬼
    static let companionGargoyle = PixelArt([
        "................",
        "..k..........k..",
        "..kk.kkkkkk.kk..",
        "..ktkttttttktk..",
        "...kttttttttk...",
        "...ktettttetk...",
        "...ktkttttktk...",
        "...kttwkkwttk...",
        "kk..kttttttk..kk",
        "kfk.kkttttkk.kfk",
        "kffkkttttttkkffk",
        "kfffkttttttkfffk",
        "kffktsttttstkffk",
        ".kfkttttttttkfk.",
        "..kkktkkkktkkk..",
        "....kkk..kkk....",
    ])
    /// 精靈：斥候狐狸
    static let companionFox = PixelArt([
        "................",
        ".k............k.",
        ".kk..........kk.",
        ".kck........kck.",
        ".kcwk......kwck.",
        ".kccckkkkkkccck.",
        "kcccccccccccccck",
        "kcceccccccccecck",
        "kcckcccccccckcck",
        "kwwwccccccccwwwk",
        ".kwwwwwkkwwwwwk.",
        "..kwwwwwwwwwwk..",
        "...kkggggggkk...",
        "....kccccccgk...",
        "....kckkkkck....",
        "....kk....kk....",
    ])
    /// 精靈：吟遊詩人
    static let companionBard = PixelArt([
        "..........k.....",
        ".........kyk....",
        "....kkkkkkyk....",
        "...kppppppyk....",
        "..kppppppppkk...",
        ".kkkkkkkkkkkkk..",
        "...kwwwwwwwwk...",
        "...kwewwwwewk...",
        "...kwkwwwwkwk...",
        "...kwpwkkwpwk...",
        "....kwwwwwwk....",
        ".kkkkffffffkk...",
        "kbbbkffffffffk..",
        "kbyykffffffffk..",
        ".kbbkfkkkkkfk...",
        "..kk.kk...kk....",
    ])
    /// 精靈：精靈弓箭手
    static let companionArcher = PixelArt([
        "................",
        "......kkkk......",
        ".....kggggk.....",
        "....kggggggk....",
        "...kggggggggk...",
        "k..kgwwwwwwgk..k",
        "kwkkwewwwwewkkwk",
        ".kwkwkwwwwkwkwk.",
        "..kkwpwkkwpwkk..",
        "...kgwwwwwwgk...",
        "..kggkkkkkkggk..",
        ".kb.kggggggk....",
        "kb.kgbggggggk...",
        "kb..kggggggk....",
        ".kb.kgkkkkgk....",
        "..k.kkk..kkk....",
    ])
    /// 節慶精靈：年獸寶寶（過年）
    static let companionNian = PixelArt([
        "................",
        "..kk........kk..",
        "..kyk......kyk..",
        "..kyykkkkkkyyk..",
        ".kppppppppppppk.",
        "kpyyppppppppyypk",
        "kppweppppppewppk",
        "kppwkppppppkwppk",
        "kpppkkkkkkkkpppk",
        "kpppkwkwwkwkpppk",
        ".kpppkkkkkkpppk.",
        "..kyyppppppyyk..",
        "...kyyppppyyk...",
        "....kpkkkkpk....",
        "....kpk..kpk....",
        "....kkk..kkk....",
    ])
    /// 節慶精靈：粽子精靈（端午）
    static let companionZongzi = PixelArt([
        "................",
        "................",
        ".......kk.......",
        "......kbbk......",
        "......kggk......",
        ".....kgtggk.....",
        "....kgtggggk....",
        "....kggggggk....",
        "...kggeggeggk...",
        "...kggkggkggk...",
        "..kgpggkkggpgk..",
        ".kbbbbbbbbbbbbk.",
        "kggggggggggggggk",
        "kkkkkkkkkkkkkkkk",
        "....kgk..kgk....",
        "....kkk..kkk....",
    ])
    /// 節慶精靈：小金魚（夏日祭）
    static let companionGoldfish = PixelArt([
        "................",
        "............a...",
        "......kk...a.a..",
        ".....kcck...a...",
        "....kkccckk...kk",
        "...kccccccck.kck",
        "..kcwecccccckcck",
        "..kckkcccccckcck",
        ".kccccccccccccck",
        ".kpccccccccckcck",
        "..kcccccccckkcck",
        "...kcccccck..kck",
        "....kkkkkkk...kk",
        "......kck.......",
        ".......k........",
        "................",
    ])
    /// 節慶精靈：玉兔（中秋）
    static let companionRabbit = PixelArt([
        "...kk......kk...",
        "..kwpk....kpwk..",
        "..kwpk....kpwk..",
        "..kwpk....kpwk..",
        "..kwpk....kpwk..",
        "...kwkkkkkkwk...",
        "..kwwwwwwwwwwk..",
        "..kwwewwwwewwk..",
        "..kwwkwwwwkwwk..",
        ".kwpwwwkkwwwpwk.",
        ".kwwwwwwwwwwwwk.",
        "..kkwkyyyykwkk..",
        "...kwkyyyykwk...",
        "...kwwkkkkwwk...",
        "...kwk....kwk...",
        "...kkk....kkk...",
    ])
    /// 節慶精靈：南瓜精靈（萬聖節）
    static let companionPumpkin = PixelArt([
        "................",
        "........kk......",
        ".......kgk......",
        "..kkkkkkgkkkkk..",
        ".kccckcccckccck.",
        "kcccckcccckcccck",
        "kccyyyccccyyycck",
        "kcccyccccccyccck",
        "kcccccccccccccck",
        "kccyyyyyyyyyycck",
        "kccckyykkyykccck",
        ".kcccckcckcccck.",
        "..kkkkkkkkkkkk..",
        "................",
        "................",
        "................",
    ])
    /// 節慶精靈：小雪人（聖誕節）
    static let companionSnowman = PixelArt([
        "......kkkk......",
        ".....kssssk.....",
        "....kkkkkkkk....",
        "....kwwwwwwk....",
        "...kwwewwewwk...",
        "...kwwkcckwwk...",
        "...kwpwwwwpwk...",
        "..kppppppppppk..",
        "..kwwwwwwwppwk..",
        "bkwwwwwkwwppwwkb",
        ".bkwwwwwwwwwwkb.",
        "..kwwwwkwwwwwk..",
        ".kwwwwwwwwwwwwk.",
        ".kwwwwwkwwwwwwk.",
        "..kwwwwwwwwwwk..",
        "...kkkkkkkkkk...",
    ])
    /// 節慶裝飾：紅燈籠
    static let festivalLantern = PixelArt([
        ".......kk.......",
        "......kkkk......",
        "....kkyyyykk....",
        "...kppppppppk...",
        "..kpcppppppcpk..",
        "..kpcppyyppcpk..",
        "..kpcpyyyypcpk..",
        "..kpcppyyppcpk..",
        "..kpcppppppcpk..",
        "...kppppppppk...",
        "....kkyyyykk....",
        "......kkkk......",
        ".......kk.......",
        "......kyyk......",
        "......kyyk......",
        "......kkkk......",
    ])
    /// 節慶裝飾：龍舟
    static let festivalBoat = PixelArt([
        "................",
        "................",
        ".kkk............",
        "kgwgk...........",
        "kgggkk..k..k..k.",
        ".kkgggk.kk.kk.kk",
        "..kgyk.kpkkpkkpk",
        "..kgk..kkkkkkkk.",
        "kkkgkkkkkkkkkkkk",
        "kpppppppppppppgk",
        "kyyyyyyyyyyyyggk",
        ".kpppppppppppgk.",
        "..kkkkkkkkkkkk..",
        ".aa..aaa...aa...",
        "....aa...aaa..aa",
        "................",
    ])
    /// 節慶裝飾：刨冰
    static let festivalIce = PixelArt([
        "................",
        "......kkkk......",
        ".....kwwwwk.....",
        "....kwwpwwwk....",
        "...kwwppwwwwk...",
        "...kwwwwwyywk...",
        "..kwwyywwyywwk..",
        "..kpwyywwwwwpk..",
        "..kkkkkkkkkkkk..",
        "..kaaaaaaaaaak..",
        "...kahaaaaaak...",
        "....kaaaaaak....",
        ".....kkkkkk.....",
        "......kaak......",
        "....kkaaaakk....",
        "....kkkkkkkk....",
    ])
    /// 節慶裝飾：柚子
    static let festivalPomelo = PixelArt([
        "................",
        "........kk......",
        ".......kbk.kk...",
        ".......kbkkggk..",
        ".....kkkbkggk...",
        "...kkyyykkkk....",
        "..kyyyyyyyyyk...",
        ".kyywyyyyyyyyk..",
        ".kywyyyyyyyyyk..",
        ".kyyyyyyyyyyyk..",
        ".kyyyyyyyyyygk..",
        ".kyyyyyyyyyggk..",
        "..kyyyyyyyggk...",
        "...kkyyyyykk....",
        ".....kkkkk......",
        "................",
    ])
    /// 節慶裝飾：稻草人
    static let festivalScarecrow = PixelArt([
        "................",
        "......kkkk......",
        ".....kyyyyk.....",
        "...kkyyyyyykk...",
        "..kyyyyyyyyyyk..",
        "...kkwwwwwwkk...",
        "....kwkwwkwk....",
        "....kwwwwwwk....",
        "....kkwkkwkk....",
        "kkkkkkppppkkkkkk",
        "ybbbkppwwppkbbby",
        "kkkkkpwppwpkkkkk",
        ".....kppppk.....",
        ".....kkbbkk.....",
        "......kbbk......",
        "......kbbk......",
    ])
    /// 節慶裝飾：聖誕樹
    static let festivalTree = PixelArt([
        ".......kk.......",
        "......kyyk......",
        ".......kk.......",
        "......kggk......",
        ".....kggggk.....",
        "....kggpgggk....",
        "...kkkggggkkk...",
        "....kggggygk....",
        "...kgyggggggk...",
        "..kkkggggpgkkk..",
        "...kggpggggggk..",
        "..kggggggyggggk.",
        ".kkkkkkkkkkkkkk.",
        "......kbbk......",
        ".....kbbbbk.....",
        ".....kkkkkk.....",
    ])
}

// MARK: - 第二章的地標

extension PixelArt {
    /// 地圖：聖泉湖
    static let landmarkLake = PixelArt([
        "................",
        ".......aa.......",
        "......a..a......",
        ".....a.aa.a.....",
        ".......aa.......",
        "......kssk......",
        "......kssk......",
        ".g..kkkkkkkk..g.",
        "kgkkaaaaaaaakkgk",
        "kkaaahaaaaaahaak",
        "kaaaaaaaaaaaaaak",
        "kaahaaaaaahaaaak",
        ".kaaaaaaaaaaaak.",
        "..kkaaaaaaaakk..",
        "....kkkkkkkk....",
        "................",
    ])

    /// 地圖：靜心塔
    static let landmarkTower = PixelArt([
        ".......kk.......",
        "......kffk......",
        ".....kffffk.....",
        "....kffffffk....",
        "...kkkkkkkkkk...",
        "....kssyyssk....",
        "....ksskkssk....",
        "....kssssssk....",
        "....ksskkssk....",
        "....ksskkssk....",
        "....kssssssk....",
        "...kssssssssk...",
        "...ksskkkkssk...",
        "...ksskbbkssk...",
        "..kkkkkkkkkkkk..",
        "................",
    ])

    /// 地圖：開拓區（插旗的山丘，旁邊是還沒散的霧）
    static let landmarkFrontier = PixelArt([
        "....k...........",
        "....kppp........",
        "....kpppp.......",
        "....kppp........",
        "....k...........",
        "....k.....tt....",
        "....k...tttttt..",
        "...kkk..........",
        "..kgggk....tt...",
        ".kgggggk.tttttt.",
        "kgggggggk.......",
        "kggggggggkk.....",
        "kgggbgggggggk...",
        "kggbbbgggggggk..",
        "kgbbbbbgggggggk.",
        "kkkkkkkkkkkkkkkk",
    ])
}

extension PixelArt {
    /// 我的餐盤：堅果
    static let plateNut = PixelArt([
        "................",
        "................",
        "......kkkk......",
        ".....kbbbbk.....",
        "....kbbhbbbk....",
        "...kbbhbbbbbk...",
        "...kbbbbbbbbk...",
        "...kbbbsbbbbk...",
        "...kbbbbbsbbk...",
        "...kbbbbbbbbk...",
        "....kbbbsbbk....",
        "....kbbbbbbk....",
        ".....kbbbbk.....",
        "......kkkk......",
        "................",
        "................",
    ])
}
