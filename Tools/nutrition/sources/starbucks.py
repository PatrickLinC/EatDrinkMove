"""星巴克台灣：糕點輕食（營養標示表圖片，用文字辨識）＋ 飲料（每個飲料頁面的各杯型熱量與糖）"""

import html
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common import CACHE_DIR, fetch, log, ocr, parse_ocr_table, record, save  # noqa: E402

SOURCE = "starbucks"
BASE = "https://www.starbucks.com.tw"
FOOD_COLUMNS = ["grams", "kcal", "protein", "fat", "satfat", "transfat", "carbs", "sugar", "sodium"]


def text_of(page: str) -> str:
    page = re.sub(r"<script.*?</script>|<style.*?</style>|<!--.*?-->", "", page, flags=re.S)
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " | ", page)))


def food() -> list[dict]:
    page = fetch(BASE + "/products/calories/calories.jspx").decode("utf-8", "ignore")
    images = re.findall(r'<img[^>]+src="(/products/objects/images/calories/[^"]+food[^"]*)"', page)
    paths = []
    os.makedirs(os.path.join(CACHE_DIR, "files"), exist_ok=True)
    for index, image in enumerate(images, 1):
        path = os.path.join(CACHE_DIR, "files", f"sbux-food-{index:02d}.png")
        with open(path, "wb") as file:
            file.write(fetch(BASE + image))
        paths.append(path)
    items = []
    for category, name, row in parse_ocr_table(ocr(paths), FOOD_COLUMNS):
        grams = row.get("grams")
        items.append(record("星巴克", name, row["kcal"], protein=row.get("protein"), fat=row.get("fat"),
                            carbs=row.get("carbs"), sugar=row.get("sugar"), sodium=row.get("sodium"),
                            serving=f"1 份（{grams:g} g）" if grams else "1 份", grams=grams,
                            category=category, source=SOURCE))
    log(SOURCE, f"糕點輕食 {len(items)} 項")
    return items


SIZES = ["小杯", "中杯", "大杯", "特大杯"]
SIZE_ML = {"小杯": 236, "中杯": 354, "大杯": 473, "特大杯": 591}


def drinks() -> list[dict]:
    listing = fetch(BASE + "/products/drinks.jspx").decode("utf-8", "ignore")
    categories = sorted(set(re.findall(r"view\.jspx\?catId=(\d+)", listing)), key=int)
    products = set()
    for category in categories:
        page = fetch(f"{BASE}/products/drinks/view.jspx?catId={category}").decode("utf-8", "ignore")
        products.update(re.findall(r"product\.jspx\?id=(\d+)&(?:amp;)?catId=(\d+)", page))
    log(SOURCE, f"飲料頁面 {len(products)} 個")

    items = []
    for product_id, category in sorted(products, key=lambda item: int(item[0])):
        page = fetch(f"{BASE}/products/drinks/product.jspx?id={product_id}&catId={category}").decode("utf-8", "ignore")
        title = re.search(r"<title>\s*([^|<]+)", page)
        if not title:
            continue
        kind, _, name = title.group(1).strip().rpartition("-")
        name = name.strip()
        if kind.startswith("冰") and "冰" not in name:
            name = "冰" + name
        text = text_of(page)
        header = text[: text.find("價格")] if "價格" in text else ""
        sizes = [size for size in SIZES if re.search(rf"\|\s*{size}\s*\|", header)]
        blocks = re.findall(r"熱量\(大卡\)\s*\|\s*\|\s*([\d.]+)\s*\|(?:[^|]*\|){0,4}?\s*糖\(公克\)\s*\|\s*\|\s*([\d.]+)", text)
        for size, (kcal, sugar) in zip(sizes, blocks):
            items.append(record("星巴克", f"{name}（{size}）", kcal, sugar=sugar,
                                serving=f"1 杯 {size}（{SIZE_ML[size]} ml）", grams=SIZE_ML[size],
                                category=kind.strip(), source=SOURCE))
    log(SOURCE, f"飲料 {len(items)} 項（各杯型）")
    return items


def main():
    save(SOURCE, food() + drinks(), "星巴克台灣官網營養標示表（糕點以圖片文字辨識，已用熱量公式檢查）與飲料頁面")


if __name__ == "__main__":
    main()
