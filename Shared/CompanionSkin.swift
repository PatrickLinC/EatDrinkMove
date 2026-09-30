import SwiftUI

// iPhone 與 Apple Watch 共用：精靈的名字與像素圖（喚醒條件、特性等只在 iPhone）

/// 精靈造型（自己畫的像素圖，會眨眼）
enum CompanionSkin: String, CaseIterable, Identifiable {
    case onigiri, boba, bun, egg, goblin, slime, cat, dog, parrot
    case mimic, griffin, mushroom, ghost, wizard, skeleton, knight, dwarf, dragon
    // 聖泉湖、靜心塔、開拓區
    case frog, mermaid, unicorn, owl, monk, gargoyle, fox, bard, archer
    // 節慶精靈
    case nian, zongzi, goldfish, rabbit, pumpkin, snowman

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onigiri: "飯糰精靈"
        case .boba: "珍奶精靈"
        case .bun: "小籠包"
        case .egg: "荷包蛋"
        case .goblin: "哥布林"
        case .slime: "水滴史萊姆"
        case .cat: "貓咪"
        case .dog: "小狗"
        case .parrot: "小鳥"
        case .mimic: "寶箱怪"
        case .griffin: "獅鷲"
        case .mushroom: "蘑菇怪"
        case .ghost: "小幽靈"
        case .wizard: "見習巫師"
        case .skeleton: "骷髏兵"
        case .knight: "見習騎士"
        case .dwarf: "矮人鐵匠"
        case .dragon: "龍寶寶"
        case .frog: "青蛙王子"
        case .mermaid: "小人魚"
        case .unicorn: "獨角獸"
        case .owl: "貓頭鷹"
        case .monk: "見習僧侶"
        case .gargoyle: "石像鬼"
        case .fox: "斥候狐狸"
        case .bard: "吟遊詩人"
        case .archer: "精靈弓箭手"
        case .nian: "年獸寶寶"
        case .zongzi: "粽子精靈"
        case .goldfish: "小金魚"
        case .rabbit: "玉兔"
        case .pumpkin: "南瓜精靈"
        case .snowman: "小雪人"
        }
    }

    var art: PixelArt {
        switch self {
        case .onigiri: .companion
        case .boba: .companionBoba
        case .bun: .companionBun
        case .egg: .companionEgg
        case .goblin: .companionGoblin
        case .slime: .companionSlime
        case .cat: .companionCat
        case .dog: .companionDog
        case .parrot: .companionParrot
        case .mimic: .companionMimic
        case .griffin: .companionGriffin
        case .mushroom: .companionMushroom
        case .ghost: .companionGhost
        case .wizard: .companionWizard
        case .skeleton: .companionSkeleton
        case .knight: .companionKnight
        case .dwarf: .companionDwarf
        case .dragon: .companionDragon
        case .frog: .companionFrog
        case .mermaid: .companionMermaid
        case .unicorn: .companionUnicorn
        case .owl: .companionOwl
        case .monk: .companionMonk
        case .gargoyle: .companionGargoyle
        case .fox: .companionFox
        case .bard: .companionBard
        case .archer: .companionArcher
        case .nian: .companionNian
        case .zongzi: .companionZongzi
        case .goldfish: .companionGoldfish
        case .rabbit: .companionRabbit
        case .pumpkin: .companionPumpkin
        case .snowman: .companionSnowman
        }
    }

    /// 眨眼：把眼睛上半格換成臉的顏色
    var blinkArt: PixelArt {
        switch self {
        case .onigiri: .companionBlink
        case .boba: art.replacing("e", with: "b")
        case .bun: art.replacing("e", with: "w")
        case .egg: art.replacing("e", with: "y")
        case .goblin, .parrot, .dragon, .zongzi: art.replacing("e", with: "g")
        case .slime: art.replacing("e", with: "a")
        case .cat, .fox, .goldfish: art.replacing("e", with: "c")
        case .dog: art.replacing("e", with: "y").replacing("h", with: "y")
        case .mimic: art.replacing("e", with: "b")
        case .griffin, .mushroom, .ghost, .wizard, .knight, .dwarf, .frog, .mermaid, .unicorn, .owl, .monk, .bard, .archer,
             .nian, .rabbit, .snowman:
            art.replacing("e", with: "w")
        case .gargoyle: art.replacing("e", with: "t")
        case .skeleton, .pumpkin: art // 骷髏沒有眼皮，南瓜的眼睛是刻出來的
        }
    }

    /// 閃光版的換色（左邊的顏色換成右邊）
    var shinyColors: [Character: Character] {
        switch self {
        case .onigiri: ["w": "y"]
        case .boba: ["b": "g"]
        case .bun: ["w": "y", "t": "c"]
        case .egg: ["w": "y", "y": "c"]
        case .dog: ["y": "w", "b": "s"]
        case .cat: ["c": "s", "b": "a"]
        case .parrot: ["g": "a", "a": "g"]
        case .slime: ["a": "y"]
        case .goblin: ["g": "a", "b": "p"]
        case .mimic: ["b": "y", "y": "c"]
        case .griffin: ["c": "s", "y": "a"]
        case .mushroom: ["p": "f"]
        case .ghost: ["w": "a", "p": "f"]
        case .wizard: ["f": "a"]
        case .skeleton: ["w": "y"]
        case .knight: ["s": "y", "a": "p"]
        case .dwarf: ["c": "w", "s": "y"]
        case .dragon: ["g": "p", "c": "y"]
        case .frog: ["g": "a"]
        case .mermaid: ["f": "y", "a": "f"]
        case .unicorn: ["f": "a", "y": "p"]
        case .owl: ["b": "s"]
        case .monk: ["c": "f", "f": "y"]
        case .gargoyle: ["t": "y", "f": "p"]
        case .fox: ["c": "s", "g": "p"]
        case .bard: ["f": "c", "y": "a"]
        case .archer: ["g": "a"]
        case .nian: ["p": "y", "y": "p"]
        case .zongzi: ["g": "y", "b": "p"]
        case .goldfish: ["c": "f"]
        case .rabbit: ["w": "y"]
        case .pumpkin: ["c": "w", "y": "a"]
        case .snowman: ["p": "g", "s": "p"]
        }
    }

    func art(shiny: Bool, blink: Bool = false) -> PixelArt {
        let base = blink ? blinkArt : art
        return shiny ? base.recolored(shinyColors) : base
    }
}
