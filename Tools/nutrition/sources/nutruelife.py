"""營養師杯蓋（增重學院）：食物營養素一覽（表格是圖片，用 macOS 文字辨識讀，並用熱量公式檢查）"""

import hashlib
import html
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)
from common import CACHE_DIR, fetch, log, ocr, parse_ocr_with_header, record, save  # noqa: E402
from dailydietitian import brand_in  # noqa: E402

SOURCE = "nutruelife"
API = "https://nutruelifegood.com/wp-json/wp/v2/food-nutrients"


def main():
    entries = []
    for page in range(1, 20):
        try:
            batch = json.loads(fetch(f"{API}?per_page=100&page={page}"))
        except Exception:
            break
        if not batch:
            break
        entries += batch
    log(SOURCE, f"共 {len(entries)} 篇")

    folder = os.path.join(CACHE_DIR, "files", "nutruelife")
    os.makedirs(folder, exist_ok=True)
    items = []
    for number, entry in enumerate(entries, 1):
        title = html.unescape(entry["title"]["rendered"])
        content = entry["content"]["rendered"]
        images = [src for src in re.findall(r'<img[^>]+src="([^"]+)"', content)
                  if "uploads" in src and not src.lower().endswith((".gif", ".svg"))]
        paths = []
        for src in images:
            url = src.replace("http://", "https://")
            path = os.path.join(folder, hashlib.sha1(url.encode()).hexdigest() + os.path.splitext(url)[1][:5])
            if not os.path.exists(path) or os.path.getsize(path) == 0:
                try:
                    data = fetch(url)
                except Exception as error:
                    log(SOURCE, f"圖片失敗：{error}")
                    continue
                with open(path, "wb") as file:
                    file.write(data)
            paths.append(path)
        if not paths:
            continue
        try:
            rows = parse_ocr_with_header(ocr(paths))
        except Exception as error:
            log(SOURCE, f"{title[:20]} 辨識失敗：{error}")
            continue
        brand = brand_in(title) or ""
        topic = re.sub(r"[【】]|熱量|營養素|一覽|比一比|一次看|[?？!！]|\(.*?\)", "", title).strip()[:20]
        for category, name, row in rows:
            item = record(brand, name, row["kcal"], protein=row.get("protein"), fat=row.get("fat"),
                          carbs=row.get("carbs"), sugar=row.get("sugar"), sodium=row.get("sodium"),
                          serving="1 份", category=category or topic, source=SOURCE)
            if item:
                items.append(item)
        if number % 20 == 0:
            log(SOURCE, f"{number}/{len(entries)}，目前 {len(items)} 項")

    seen, unique = set(), []
    for item in items:
        key = (item.get("brand"), item["name"])
        if key not in seen:
            seen.add(key)
            unique.append(item)
    save(SOURCE, unique, "營養師杯蓋（增重學院）食物營養素一覽圖表，文字辨識後以熱量公式檢查")


if __name__ == "__main__":
    main()
