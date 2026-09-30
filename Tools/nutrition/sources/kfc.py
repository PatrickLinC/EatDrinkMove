"""肯德基台灣：線上點餐菜單裡每個品項的「營養資訊」文字"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common import fetch_json, log, record, save  # noqa: E402

SOURCE = "kfc"
API = "https://olo-api.kfcclub.com.tw/menu/v1/"
HEADERS = {"Origin": "https://www.kfcclub.com.tw", "Referer": "https://www.kfcclub.com.tw/"}


def field(text: str, label: str) -> str | None:
    match = re.search(rf"{label}\s*[:：]\s*([\d.]+)", text)
    return match.group(1) if match else None


def query(endpoint: str, payload: dict) -> dict:
    # API 主機沒有 robots.txt（404），視為允許
    return fetch_json(API + endpoint, payload, headers=HEADERS, check_robots=False)


def main():
    items, menus = {}, set()
    for mealperiod in ("0", "1"):
        base = {"mealperiod": mealperiod, "ordertype": "0", "ismember": "0", "channel": "2"}
        for menu in query("GetQueryMenu", {**base, "parentid": "0"}).get("Data", {}).get("Menu", []):
            menus.add((mealperiod, str(menu["MenuID"]), menu.get("Title", "")))

    for mealperiod, menu_id, title in sorted(menus):
        data = query("GetQueryFood", {"mealperiod": mealperiod, "ordertype": "0", "ismember": "0",
                                      "menuid": menu_id, "channel": "2"})
        for group in data.get("Data", {}).get("Foods", []):
            for food in group.get("Details", []):
                text = (food.get("Nutrition") or "").replace("\\n", "\n")
                kcal = field(text, "熱量")
                if not kcal or food.get("Name") in items:
                    continue
                grams = field(text, "重量")
                items[food["Name"]] = record(
                    "肯德基", food["Name"], kcal,
                    protein=field(text, "蛋白質"), fat=field(text, "(?<!飽和)(?<!反式)脂肪"),
                    carbs=field(text, "碳水化合物"), sugar=field(text, "糖"), sodium=field(text, "鈉"),
                    serving=f"1 份（{float(grams):g} g）" if grams else "1 份", grams=grams,
                    category=group.get("Title") or title, source=SOURCE,
                )
        log(SOURCE, f"{title}：累計 {len(items)} 項")
    save(SOURCE, list(items.values()), "肯德基台灣線上點餐各品項的營養資訊")


if __name__ == "__main__":
    main()
