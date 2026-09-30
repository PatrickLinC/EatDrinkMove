"""全家「食在購安心」：鮮食、咖啡等商品的每份營養標示"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common import fetch_json, log, record, save  # noqa: E402

SOURCE = "familymart"
BASE = "https://foodsafety.family.com.tw/Web_FFD_2022/"
HEADERS = {"Origin": "https://foodsafety.family.com.tw", "Referer": BASE}


def parse_note(note: str):
    """「每份熱量193大卡;每份規格109公克;(本包裝含1份);」→ 熱量、每份重量、份數"""
    kcal = re.search(r"熱量\s*([\d.]+)", note or "")
    grams = re.search(r"規格\s*([\d.]+)\s*(公克|毫升|g|ml|mL)", note or "")
    servings = re.search(r"含\s*([\d.]+)\s*份", note or "")
    return (float(kcal.group(1)) if kcal else None,
            float(grams.group(1)) if grams else None,
            grams.group(2) if grams else "公克",
            float(servings.group(1)) if servings else None)


def main():
    listing = fetch_json(BASE + "ws/QueryFsProductListByFilter", {"MEMBER": "N"}, headers=HEADERS)
    products = []
    for category in listing.get("LIST", []):
        for item in category.get("ITEM", []):
            products.append((category.get("CATEGORY_NAME", ""), item))
    log(SOURCE, f"清單共 {len(products)} 項，開始抓每一項的營養素")

    records = []
    for index, (category, item) in enumerate(products, 1):
        cmno = item.get("CMNO")
        try:
            detail = fetch_json(BASE + "ws/QueryFsProductByItem", {"CMNO": cmno, "MEMBER": "N"}, headers=HEADERS)
            info = (detail.get("LIST") or [{}])[0]
        except Exception as error:  # 單一商品失敗就用清單上的熱量
            log(SOURCE, f"{cmno} 失敗：{error}")
            info = item

        kcal, grams, unit, servings = parse_note(info.get("NOTE") or item.get("NOTE"))
        nutrients = (info.get("NUTRIENTS") or [{}])[0]
        serving = f"1 份（{grams:g} {'ml' if unit in ('毫升', 'ml', 'mL') else 'g'}）" if grams else "1 份"
        if servings and servings > 1:
            serving += f"，本包裝 {servings:g} 份"
        records.append(record(
            "全家", info.get("PRODNAME") or item.get("PRODNAME"), kcal,
            protein=nutrients.get("PROTEIN"), fat=nutrients.get("TOTALFAT"),
            carbs=nutrients.get("CARBOHYDRATE"), sugar=nutrients.get("SUGAR"), sodium=nutrients.get("SODIUM"),
            serving=serving, grams=grams, category=category, source=SOURCE,
        ))
        if index % 100 == 0:
            log(SOURCE, f"{index}/{len(products)}")

    # 同名商品（不同工廠）只留第一筆
    seen, unique = set(), []
    for item in records:
        if item and item["name"] not in seen:
            seen.add(item["name"])
            unique.append(item)
    save(SOURCE, unique, "全家便利商店「食在購安心」網站公開的每份營養標示")


if __name__ == "__main__":
    main()
