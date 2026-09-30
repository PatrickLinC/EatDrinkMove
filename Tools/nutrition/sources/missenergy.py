"""能量小姐 Miss Energy（健康水煮餐盒）：官網菜單的「正常／半飯」熱量"""

import html
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common import fetch, log, record, save  # noqa: E402

SOURCE = "missenergy"


def main():
    items, seen = [], set()
    for tab in range(1, 10):
        try:
            page = fetch(f"https://www.missenergy.com.tw/product.php?lang=tw&tb={tab}").decode("utf-8", "ignore")
        except Exception:
            continue
        page = re.sub(r"<script.*?</script>|<style.*?</style>", "", page, flags=re.S)
        text = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " | ", page)))
        category = re.search(r"首頁\s*(?:\|\s*)+([^|]{2,10}?)\s*\|", text)
        for name, normal, half in re.findall(r"\|\s*([^|]{2,20}?)\s*-?\s*(?:\|\s*)+正常\s*(\d+)\s*卡\s*/\s*半飯\s*(\d+)\s*卡", text):
            name = name.strip(" -")
            for label, kcal in (("正常", normal), ("半飯", half)):
                if (name, label) in seen:
                    continue
                seen.add((name, label))
                items.append(record("能量小姐", f"{name}餐盒（{label}）", kcal, serving=f"1 盒（{label}）",
                                    category=category.group(1).strip() if category else "餐盒", source=SOURCE))
        log(SOURCE, f"分類 {tab}：累計 {len(items)} 項")
    save(SOURCE, items, "能量小姐官網菜單標示的餐盒熱量（正常／半飯）")


if __name__ == "__main__":
    main()
