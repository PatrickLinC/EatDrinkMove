import Foundation

/// 存在手機裡的一串食物（收藏、自訂食物共用）
private struct QuickFoodList {
    let key: String
    let limit: Int

    func all() -> [QuickFood] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let foods = try? JSONDecoder().decode([QuickFood].self, from: data) else { return [] }
        return foods
    }

    func save(_ foods: [QuickFood]) {
        if let data = try? JSONEncoder().encode(Array(foods.prefix(limit))) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func upsert(_ food: QuickFood) {
        save([food] + all().filter { $0.name != food.name })
    }

    func remove(named name: String) {
        save(all().filter { $0.name != name })
    }
}

/// 收藏的食物（長按食物加入）
enum FavoriteStore {
    private static let list = QuickFoodList(key: "favoriteFoods", limit: 100)

    static func all() -> [QuickFood] { list.all() }

    static func contains(_ name: String) -> Bool { all().contains { $0.name == name } }

    static func toggle(_ food: QuickFood) {
        if contains(food.name) {
            list.remove(named: food.name)
        } else {
            list.upsert(food)
        }
    }
}

/// 自己建立的食物（例如家裡常煮的菜）
enum CustomFoodStore {
    private static let list = QuickFoodList(key: "customFoods", limit: 200)

    static func all() -> [QuickFood] { list.all() }

    static func save(_ food: QuickFood) { list.upsert(food) }

    static func remove(_ food: QuickFood) { list.remove(named: food.name) }
}
