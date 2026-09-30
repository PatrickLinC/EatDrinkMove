"""i-fit 愛瘦身：食物熱量表文章（多半只有熱量）

從 sitemap 找所有文章，只取有「熱量」欄位的表格；品牌判斷沿用日日營養的清單。
"""

import html
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)
from common import fetch, html_tables, log, parse_nutrition_table, record, save  # noqa: E402
from dailydietitian import brand_in, sections, topic  # noqa: E402

SOURCE = "ifit"


def main():
    sitemap = fetch("https://www.i-fit.com.tw/sitemap.xml").decode("utf-8", "ignore")
    pages = [url for url in re.findall(r"<loc>([^<]+)</loc>", sitemap) if "/context/" in url or "/post/" in url]
    log(SOURCE, f"共 {len(pages)} 頁")

    items = []
    for index, url in enumerate(pages, 1):
        try:
            page = fetch(url).decode("utf-8", "ignore")
        except Exception as error:
            log(SOURCE, f"{url} 失敗：{error}")
            continue
        if "<table" not in page or "熱量" not in page:
            continue
        title_match = re.search(r"<title>(.*?)</title>", page, flags=re.S)
        title = html.unescape(title_match.group(1)).strip() if title_match else ""
        title_brand = brand_in(title)
        for heading, part in sections(page):
            brand = brand_in(heading) or title_brand
            for table in html_tables(part):
                for row in parse_nutrition_table(table):
                    size = row.pop("size", "")
                    name = row.pop("name")
                    display = f"{name}（{size}）" if size and size not in name else name
                    item = record(brand or "", display, row.get("kcal"), protein=row.get("protein"),
                                  fat=row.get("fat"), carbs=row.get("carbs"), sugar=row.get("sugar"),
                                  sodium=row.get("sodium"), serving=row.get("serving") or "1 份",
                                  category=(heading[:20] if brand else topic(title)), source=SOURCE)
                    if item:
                        items.append(item)
        if index % 100 == 0:
            log(SOURCE, f"{index}/{len(pages)}，目前 {len(items)} 項")

    seen, unique = set(), []
    for item in items:
        key = (item.get("brand"), item["name"])
        if key not in seen:
            seen.add(key)
            unique.append(item)
    save(SOURCE, unique, "i-fit 愛瘦身食物熱量表文章（多半只有熱量）")


if __name__ == "__main__":
    main()
