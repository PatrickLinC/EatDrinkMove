"""Open Food Facts：大家一起建的包裝食品資料庫（ODbL 開放授權），用官方的整包匯出檔，不打 API

匯出檔約 1.3 GB，先用 curl 下載到 cache/（可斷點續傳），下載完整後在本機篩選。只留在台灣販售或條碼 471 開頭（台灣）的商品。
有每份重量就換算成每份，沒有就用每 100 g。
"""

import csv
import gzip
import io
import os
import re
import subprocess
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common import CACHE_DIR, USER_AGENT, energy_error, log, record, save  # noqa: E402

SOURCE = "openfoodfacts"
EXPORT = "https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz"


def number(value: str) -> float | None:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return result if result >= 0 else None


def download() -> str:
    """下載匯出檔（斷線會從中斷處接著下載），回傳本機路徑"""
    path = os.path.join(CACHE_DIR, "openfoodfacts-products.csv.gz")
    request = urllib.request.Request(EXPORT, method="HEAD", headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        size = int(response.headers["Content-Length"])
    for attempt in range(50):
        if os.path.exists(path) and os.path.getsize(path) >= size:
            return path
        log(SOURCE, f"下載中 {os.path.getsize(path) if os.path.exists(path) else 0} / {size} bytes（第 {attempt + 1} 次）")
        subprocess.run(["curl", "-sL", "-C", "-", "--retry", "5", "-A", USER_AGENT, "-o", path, EXPORT])
        time.sleep(5)
    raise RuntimeError("下載一直沒完成")


def main():
    csv.field_size_limit(1 << 30)
    path = download()
    log(SOURCE, "下載完成，開始篩選")
    items, rows = [], 0
    with gzip.open(path, "rb") as raw:
        text = io.TextIOWrapper(raw, encoding="utf-8", errors="ignore", newline="")
        reader = csv.reader(text, delimiter="\t", quoting=csv.QUOTE_NONE)
        header = next(reader)
        column = {name: index for index, name in enumerate(header)}

        def get(row, name):
            index = column.get(name)
            return row[index].strip() if index is not None and index < len(row) else ""

        for row in reader:
            rows += 1
            if rows % 500000 == 0:
                log(SOURCE, f"讀了 {rows} 列，台灣商品 {len(items)} 項")
            code = get(row, "code")
            if not (code.startswith("471") or "en:taiwan" in get(row, "countries_tags")):
                continue
            name = get(row, "product_name") or get(row, "abbreviated_product_name")
            kcal = number(get(row, "energy-kcal_100g"))
            if kcal is None:
                kilojoule = number(get(row, "energy_100g"))
                kcal = kilojoule / 4.184 if kilojoule is not None else None
            if not name or kcal is None or kcal > 900:
                continue
            per = {key: number(get(row, f"{key}_100g")) for key in ("proteins", "fat", "carbohydrates", "sugars", "sodium")}
            # 網友輸入錯的（例如把千焦填成大卡）：熱量和三大營養素對不起來就不收（酒精飲料例外，酒精也有熱量）
            macros = (per["proteins"], per["fat"], per["carbohydrates"])
            if kcal > 40 and all(value is not None for value in macros) and energy_error(kcal, *macros) > 0.35 \
                    and "alcoholic" not in get(row, "categories_tags"):
                continue
            serving = number(get(row, "serving_quantity"))
            factor, label = (serving / 100, get(row, "serving_size") or f"{serving:g} g") if serving and 5 <= serving <= 1000 else (1, "100 g")

            def scaled(value):
                return value * factor if value is not None else None

            brand = get(row, "brands").split(",")[0].strip()
            items.append(record(
                brand, re.sub(r"\s+", " ", name)[:60], kcal * factor,
                protein=scaled(per["proteins"]), fat=scaled(per["fat"]), carbs=scaled(per["carbohydrates"]),
                sugar=scaled(per["sugars"]), sodium=scaled(per["sodium"] * 1000 if per["sodium"] is not None else None),
                serving=label[:30], grams=serving if factor != 1 else 100, category="包裝食品", barcode=code, source=SOURCE,
            ))
    log(SOURCE, f"讀完 {rows} 列")

    seen, unique = set(), []
    for item in items:
        if item and item["barcode"] not in seen:
            seen.add(item["barcode"])
            unique.append(item)
    save(SOURCE, unique, "Open Food Facts 台灣商品（ODbL 開放授權，官方匯出檔）")


if __name__ == "__main__":
    main()
