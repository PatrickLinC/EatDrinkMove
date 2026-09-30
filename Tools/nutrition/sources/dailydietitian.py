"""日日營養 DailyDietitian（營養師整理）：各品牌菜單與常見食品的熱量表

用 WordPress 的公開文章 API 讀文章，只取有「熱量」欄位的表格。
品牌由表格前最近的標題判斷，其次看文章標題；沒有品牌的算一般食品。
"""

import html
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common import fetch, html_tables, log, parse_nutrition_table, record, save  # noqa: E402

SOURCE = "dailydietitian"
API = "https://dailydietitian.com.tw/wp-json/wp/v2/posts"

# （關鍵字, 統一後的品牌名）——長的、具體的放前面
BRANDS = [
    ("CITY CAFE", "7-11 CITY CAFE"), ("City cafe", "7-11 CITY CAFE"), ("City Cafe", "7-11 CITY CAFE"),
    ("7-11 咖啡", "7-11 CITY CAFE"), ("CITY TEA", "7-11 CITY TEA"), ("CITY PEARL", "7-11 CITY TEA"),
    ("現萃茶", "7-11 CITY TEA"), ("Let’s Cafe", "全家 Let's Café"), ("Let’s cafe", "全家 Let's Café"),
    ("Let's Cafe", "全家 Let's Café"), ("全家咖啡", "全家 Let's Café"), ("Let’s Tea", "全家 Let's Tea"),
    ("Famiice", "全家 Famiice"), ("Hi Café", "萊爾富 Hi Café"), ("萊爾富咖啡", "萊爾富 Hi Café"),
    ("麥當勞", "麥當勞"), ("肯德基", "肯德基"), ("KFC", "肯德基"), ("摩斯", "摩斯"), ("漢堡王", "漢堡王"),
    ("必勝客", "必勝客"), ("達美樂", "達美樂"), ("德克士", "德克士"), ("頂呱呱", "頂呱呱"),
    ("拉亞", "拉亞漢堡"), ("麥味登", "麥味登"), ("Subway", "Subway"), ("八方雲集", "八方雲集"),
    ("四海遊龍", "四海遊龍"), ("三商巧福", "三商巧福"), ("三商炸雞", "三商炸雞"), ("丸龜", "丸龜製麵"),
    ("Sukiya", "Sukiya"), ("すき家", "Sukiya"), ("吉野家", "吉野家"), ("松屋", "松屋"),
    ("21世紀", "21世紀風味館"), ("IKEA", "IKEA"), ("我家牛排", "我家牛排"), ("拿坡里", "拿坡里"),
    ("石二鍋", "石二鍋"), ("老蔡水煎包", "老蔡水煎包"), ("Häagen-Dazs", "Häagen-Dazs"), ("哈根達斯", "Häagen-Dazs"),
    ("50 嵐", "50嵐"), ("50嵐", "50嵐"), ("五十嵐", "50嵐"), ("清心", "清心福全"), ("麻古", "麻古茶坊"),
    ("迷客夏", "迷客夏"), ("Milksha", "迷客夏"), ("CoCo", "CoCo都可"), ("都可", "CoCo都可"),
    ("可不可", "可不可熟成紅茶"), ("大苑子", "大苑子"), ("一沐日", "一沐日"), ("得正", "得正"),
    ("大茗", "大茗"), ("五桐號", "五桐號"), ("萬波", "萬波"), ("天仁", "天仁茗茶"), ("茶湯會", "茶湯會"),
    ("春水堂", "春水堂"), ("COMEBUY", "COMEBUY"), ("COME BUY", "COMEBUY"), ("UG", "UG"), ("八曜", "八曜和茶"),
    ("路易莎", "路易莎"), ("星巴克", "星巴克"), ("好市多", "好市多"), ("Costco", "好市多"),
]


def brand_in(text: str) -> str | None:
    for keyword, brand in BRANDS:
        if keyword in text:
            return brand
    return None


def topic(title: str) -> str:
    """沒有品牌的文章，用標題判斷是哪一類食品"""
    for word in ("泡麵", "月餅", "水果", "堅果", "酒", "火鍋料", "零食", "年菜", "宵夜", "烤肉", "早餐", "超商"):
        if word in title:
            return word
    return "常見食品"


def sections(content: str):
    """依標題切段，回傳 (這段的標題, 這段的 HTML)"""
    parts = re.split(r"(<h[1-4][^>]*>.*?</h[1-4]>)", content, flags=re.S)
    heading = ""
    for part in parts:
        if re.match(r"<h[1-4]", part):
            heading = html.unescape(re.sub(r"<[^>]+>", "", part))
        else:
            yield heading, part


def main():
    posts = []
    for page in range(1, 20):
        try:
            batch = json.loads(fetch(f"{API}?per_page=100&page={page}&_fields=id,title"))
        except Exception:
            break
        if not batch:
            break
        posts += batch
    log(SOURCE, f"共 {len(posts)} 篇文章")

    items = []
    for post in posts:
        title = html.unescape(post["title"]["rendered"])
        detail = json.loads(fetch(f"{API}/{post['id']}?_fields=content"))
        content = detail["content"]["rendered"]
        if "<table" not in content:
            continue
        title_brand = brand_in(title)
        count = 0
        for heading, part in sections(content):
            brand = brand_in(heading) or title_brand
            for table in html_tables(part):
                for row in parse_nutrition_table(table):
                    size = row.pop("size", "")
                    name = row.pop("name")
                    display = f"{name}（{size}）" if size and size not in name else name
                    serving = row.pop("serving", "") or ""
                    grams = re.search(r"([\d.]+)\s*(?:g|公克|克|ml|毫升|c\.c\.|cc)", serving, flags=re.I)
                    item = record(brand or "", display, row.get("kcal"), protein=row.get("protein"),
                                  fat=row.get("fat"), carbs=row.get("carbs"), sugar=row.get("sugar"),
                                  sodium=row.get("sodium"),
                                  serving=serving or (f"1 杯 {size}" if size else "1 份"),
                                  grams=grams.group(1) if grams else None,
                                  category=("推估" if "推估" in title else "") or (heading[:20] if brand else topic(title)),
                                  source=SOURCE)
                    if item:
                        items.append(item)
                        count += 1
        if count:
            log(SOURCE, f"{title[:30]}：{count} 項")

    seen, unique = set(), []
    for item in items:
        key = (item.get("brand"), item["name"])
        if key not in seen:
            seen.add(key)
            unique.append(item)
    save(SOURCE, unique, "日日營養 DailyDietitian 營養師整理的各品牌與常見食品熱量表")


if __name__ == "__main__":
    main()
