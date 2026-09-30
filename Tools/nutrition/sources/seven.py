"""7-ELEVEN 官網「鮮食」：飯糰、便當、麵、麵包、沙拉、甜點等的熱量（官方）

各分類頁用 /freshfoods/read_food_xml.aspx?=N 載入品項（robots.txt 只擋網址含「.xml」的檔案，這個網址不在其中）。
新品還沒公布熱量時寫「.」，這些不收。
"""

import html
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common import fetch, log, record, save  # noqa: E402

SOURCE = "seven"
FEED = "https://www.7-11.com.tw/freshfoods/read_food_xml.aspx?={}"
CATEGORIES = {0: "飯糰", 1: "輕食", 2: "便當", 3: "點心", 4: "便當", 5: "麵食", 7: "熱狗", 10: "麵包", 12: "蒸點／小吃",
              13: "滷味／關東煮", 14: "健康餐", 15: "三明治", 16: "Ohlala", 17: "蔬食", 18: "星級料理", 19: "大亨堡",
              21: "霜淇淋", 22: "便當", 23: "甜點"}


def main():
    items = []
    for number in range(0, 31):
        try:
            feed = fetch(FEED.format(number)).decode("utf-8", "ignore")
        except Exception as error:
            log(SOURCE, f"分類 {number} 失敗：{error}")
            continue
        found = 0
        for block in re.findall(r"<Item\b.*?</Item>", feed, flags=re.S):
            def tag(name):
                match = re.search(rf"<{name}>(.*?)</{name}>", block, flags=re.S)
                return html.unescape(match.group(1)).strip() if match else ""
            kcal = tag("kcal")
            if not re.fullmatch(r"\d+(?:\.\d+)?", kcal):
                continue
            item = record("7-11", tag("name"), kcal, serving="1 份", category=CATEGORIES.get(number, "鮮食"), source=SOURCE)
            if item:
                items.append(item)
                found += 1
        if found:
            log(SOURCE, f"分類 {number}（{CATEGORIES.get(number, '其他')}）：{found} 項")

    seen, unique = set(), []
    for item in items:
        if item["name"] not in seen:
            seen.add(item["name"])
            unique.append(item)
    save(SOURCE, unique, "7-ELEVEN 官網鮮食熱量（官方）")


if __name__ == "__main__":
    main()
