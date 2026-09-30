"""合併 data/*.json → iOS/Resources/brand_foods.json（App 內建的品牌與常見食品資料）

同一品牌同一品名只留一筆：官方來源優先，其次營養師整理，最後才是只有熱量的文章。
"""

import json
import os
import re

ROOT = os.path.dirname(os.path.abspath(__file__))
OUTPUT = os.path.join(ROOT, "..", "..", "iOS", "Resources", "brand_foods.json")
# 數字越小越優先
PRIORITY = {"familymart": 0, "starbucks": 0, "mos": 0, "kfc": 0, "taipei": 0, "ntpc": 0, "missenergy": 0, "seven": 0,
            "dailydietitian": 1, "openfoodfacts": 2, "articles": 2, "ifit": 3}
# 不合併的來源：nutruelife 的表格是圖片，文字辨識後品名錯字、欄位錯位太多，通過熱量驗算的只剩個位數
SKIP = {"nutruelife"}


# 公司登記名稱 → 大家叫的品牌名
BRAND_NAMES = {
    "全家便利商店": "全家", "統一超商": "7-11", "富達零售": "OK mart", "萊爾富國際": "萊爾富",
    "台鋼漢堡王": "漢堡王", "天仁茶業": "天仁茗茶", "王座國際餐飲": "王座", "金色三麥餐飲": "金色三麥",
    "美食達人": "85度C", "安心食品服務": "摩斯", "揚秦國際企業": "麥味登", "路易莎職人咖啡": "路易莎",
    "統一星巴克": "星巴克", "台灣麥當勞餐廳": "麥當勞", "富利餐飲": "肯德基", "深耕茶業": "50嵐",
    # 同一個品牌在不同來源的寫法
    "STARBUCKS": "星巴克", "SUBWAY": "Subway", "路易莎咖啡": "路易莎", "MISTERDONUT": "Mister Donut",
    "饗樂餐飲": "Q Burger", "FamilyMart": "全家", "得正 ": "得正", "丹堤咖啡": "丹堤咖啡", "IPPUDO": "一風堂",
    "全聯福利中心": "全聯", "Taiwan FamilyMart": "全家", "全家便利商店": "全家", "7-Eleven": "7-11", "7-eleven": "7-11",
    "7-ELEVEN": "7-11", "統一超商": "7-11", "Lays": "樂事", "Lay's": "樂事", "Ve Wong": "味王", "Chimei": "奇美",
    "Kuai Kuai": "乖乖", "I-Mei": "義美", "Imei": "義美", "CAMA": "cama café", "cama cafe": "cama café",
}


def clean_brand(brand: str) -> str:
    brand = (brand or "").strip()
    brand = re.sub(r"(股份有限公司|有限公司|[（(]股[)）]公司|企業社|公司)$", "", brand).strip()
    for legal, common in BRAND_NAMES.items():
        if brand.startswith(legal):
            return common
    return brand


def key(item):
    # 有條碼的商品用條碼判斷是不是同一個（同名不同規格的包裝食品很多）
    if item.get("barcode"):
        return ("#", item["barcode"])
    return (item.get("brand", ""), re.sub(r"[\s()（）]", "", item["name"]).lower())


def main():
    # 同品牌同品名：留優先度最高的那個來源；同一個來源裡不同杯型、甜度的都保留
    best: dict = {}
    for file in sorted(os.listdir(os.path.join(ROOT, "data"))):
        if not file.endswith(".json"):
            continue
        with open(os.path.join(ROOT, "data", file), encoding="utf-8") as handle:
            data = json.load(handle)
        if data["source"] in SKIP:
            continue
        for item in data["items"]:
            item["brand"] = clean_brand(item.get("brand", ""))
            # 明顯不合理的資料不收；0 大卡只收官方資料（無糖茶、黑咖啡），其他來源的 0 多半是沒讀到
            official = PRIORITY.get(data["source"], 9) == 0
            if not (0 <= item["kcal"] <= 3000) or (item["kcal"] == 0 and not official) or len(item["name"]) > 40:
                continue
            rank = PRIORITY.get(item["source"], 9)
            current = best.get(key(item))
            if current is None or rank < current["rank"]:
                best[key(item)] = {"rank": rank, "source": item["source"], "items": {}}
                current = best[key(item)]
            if item["source"] == current["source"]:
                current["items"].setdefault((item.get("serving") or "").strip(), item)
    items = sorted((item for group in best.values() for item in group["items"].values()),
                   key=lambda item: (item.get("brand", ""), item["name"], item.get("serving") or ""))
    with open(OUTPUT, "w", encoding="utf-8") as handle:
        json.dump(items, handle, ensure_ascii=False, separators=(",", ":"))
    brands = {item.get("brand", "") for item in items}
    print(f"共 {len(items)} 筆、{len(brands)} 個品牌 → {os.path.normpath(OUTPUT)}")


if __name__ == "__main__":
    main()
