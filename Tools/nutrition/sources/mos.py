"""摩斯漢堡：每個商品頁面的「單份營養標示」"""

import html
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common import Blocked, fetch, log, record, save  # noqa: E402

SOURCE = "mos"
BASE = "https://www.mos.com.tw/menu/"
CATEGORIES = {"set": "漢堡", "breakfast": "早餐", "sideDishes": "點心", "soup": "湯品",
              "dessert": "甜點", "beverage": "飲料"}


def value(text: str, label: str) -> str | None:
    match = re.search(rf"\|\s*{label}\s*\|\s*\|\s*([\d.]+)\s*(?:Kcal|kcal|g|mg)", text)
    return match.group(1) if match else None


def main():
    items = []
    for page_name, category in CATEGORIES.items():
        try:
            listing = fetch(f"{BASE}{page_name}.aspx").decode("utf-8", "ignore")
        except Blocked as error:
            log(SOURCE, str(error))
            continue
        details = sorted(set(re.findall(r'href="(?:/menu/)?(\w*[Dd]etail\.aspx\?id=M\d+)"', listing)))
        log(SOURCE, f"{category}：{len(details)} 項")
        for detail in details:
            page = fetch(BASE + detail).decode("utf-8", "ignore")
            page = re.sub(r"<script.*?</script>|<style.*?</style>|<!--.*?-->", "", page, flags=re.S)
            text = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " | ", page)))
            title = re.search(r"單份(.+?)營養標示", text)
            if not title:
                continue
            items.append(record(
                "摩斯", title.group(1).strip(), value(text, "熱量"),
                protein=value(text, "蛋白質"), fat=value(text, "脂肪"), carbs=value(text, "碳水化合物"),
                sugar=value(text, "糖"), sodium=value(text, "鈉"),
                serving="1 份", category=category, source=SOURCE,
            ))
    seen, unique = set(), []
    for item in items:
        if item and item["name"] not in seen:
            seen.add(item["name"])
            unique.append(item)
    save(SOURCE, unique, "摩斯漢堡官網各商品頁「單份營養標示」")


if __name__ == "__main__":
    main()
