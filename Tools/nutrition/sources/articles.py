"""營養師在新聞、健康媒體公開的熱量排行文章（小吃、零食、泡麵、超商），從文字擷取「品名＋份量＋大卡」

只收文章內文用文字寫的數字（圖片不讀），品名要像食物名稱，數字要合理；同一品名多篇文章取中位數。
文章清單在 ARTICLES，網站 robots.txt 不允許的會自動跳過。
"""

import html
import os
import re
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common import fetch, log, record, save  # noqa: E402

SOURCE = "articles"

# （網址, 分類）
ARTICLES = [
    ("https://www.storm.mg/lifestyle/3624528", "小吃"),
    ("https://health.udn.com/health/story/11189/8052625", "小吃"),
    ("https://fashion.ettoday.net/news/2431169", "小吃"),
    ("https://www.storm.mg/lifestyle/5225564", "小吃"),
    ("https://health.tvbs.com.tw/nutrition/327749", "小吃"),
    ("https://health.businessweekly.com.tw/article/ARTL003012869", "小吃"),
    ("https://health.ettoday.net/news/1960565", "小吃"),
    ("https://www.healingdaily.com.tw/articles/%E5%8F%B0%E7%81%A3%E7%BE%8E%E9%A3%9F%E7%86%B1%E9%87%8F-%E9%A3%9F%E7%89%A9%E7%87%9F%E9%A4%8A/", "小吃"),
    ("https://health.tvbs.com.tw/nutrition/348823", "零食"),
    ("https://health.gvm.com.tw/article/79788", "泡麵"),
    ("https://www.mirrormedia.mg/story/20210531edi030", "零食"),
    ("https://www.setn.com/News.aspx?NewsID=942043", "泡麵"),
    ("https://health.udn.com/health/story/11189/7840379", "早餐"),
    ("https://health.ettoday.net/news/1575512", "早餐"),
    ("https://www.ttvc.com.tw/-%E4%B8%AD%E5%BC%8F%E6%97%A9%E9%A4%90-%E7%86%B1%E9%87%8F%E6%8E%92%E8%A1%8C%E6%9B%9D%E5%85%89-%E5%90%84%E9%A1%9E%E7%AC%AC%E4%B8%80%E5%90%8D%E8%82%A5%E5%88%B0%E7%88%86-%E4%BD%A0%E6%AD%A3%E5%9C%A8%E5%90%83%E5%97%8E-a-10874.html", "早餐"),
    ("https://tw.news.yahoo.com/%E4%B8%8D%E6%98%AF%E7%87%92%E9%A4%85%E6%B2%B9%E6%A2%9D-%E4%B8%AD%E5%BC%8F%E6%97%A9%E9%A4%90%E7%86%B1%E9%87%8F-%E5%A4%A7%E5%85%AC%E9%96%8B-%E5%86%A0%E8%BB%8D%E7%A0%B4600%E5%A4%A7%E5%8D%A1%E8%B6%85%E7%BD%AA%E6%83%A1-150805683.html", "早餐"),
    ("https://www.einfit.tw/blogs/dietitian/156109", "早餐"),
]

# 品名：2～16 個字，中文為主（可夾英數）；份量：括號裡或「一碗」「每份」之類
NAME = r"([一-鿿A-Za-z][一-鿿A-Za-z0-9＆&・‧\-]{1,15})"
AMOUNT = r"(?:\s*[（(]([^）)]{1,16})[）)])?"
PATTERNS = [
    re.compile(NAME + AMOUNT + r"\s*[：:，,、]?\s*(?:約|熱量(?:約|為)?)?\s*(\d{2,4}(?:\.\d)?)\s*(?:大卡|kcal|卡)(?![路])"),
]
NOT_FOOD = re.compile(r"熱量|大卡|營養師|建議|每天|一天|攝取|消耗|運動|走路|跑步|慢跑|游泳|小時|分鐘|第[一二三四五六七八九十\d]+名|排行|冠軍|總共|合計|"
                      r"相當於|超過|約有|只有|高達|以上|以下|左右|減肥|體重|男性|女性|成人|其中|這|那|因為|所以|如果|但是|而且")


# 句子片段不是品名：「一份5」「像是花枝米粉湯一碗也才3」「水餃一顆平均在」
BAD_NAME = re.compile(r"^(?:的|搭配|加上|配|一|像|含|小份|大份|約|只|竟|僅|每|平均|比)|平均|也|才|竟|僅|要|比|在$|為$|是|有|\d$")


def extract(page: str) -> list[tuple[str, str, float]]:
    page = re.sub(r"<script.*?</script>|<style.*?</style>|<!--.*?-->", " ", page, flags=re.S)
    text = html.unescape(re.sub(r"<[^>]+>", "\n", page))
    found = []
    for line in re.split(r"[\n。；;！!？?]", text):
        line = re.sub(r"\s+", " ", line).strip()
        if not (4 <= len(line) <= 160):
            continue
        for pattern in PATTERNS:
            for name, amount, kcal in pattern.findall(line):
                name = re.sub(r"^(?:[一二三四五六七八九十\d]+[、.．)）]|No\.?\d+|TOP\d+)", "", name).strip("－-・‧ ")
                if len(name) < 2 or NOT_FOOD.search(name) or not re.search(r"[一-鿿]", name) or BAD_NAME.search(name):
                    continue
                value = float(kcal)
                if 20 <= value <= 2000:
                    found.append((name, amount.strip(), value))
    return found


def main():
    collected: dict[str, dict] = {}
    for url, category in ARTICLES:
        try:
            page = fetch(url).decode("utf-8", "ignore")
        except Exception as error:
            log(SOURCE, f"跳過 {url}：{error}")
            continue
        rows = extract(page)
        log(SOURCE, f"{len(rows):3d} 項  {url}")
        for name, amount, kcal in rows:
            entry = collected.setdefault(name, {"kcal": [], "amount": amount, "category": category})
            entry["kcal"].append(kcal)
            entry["amount"] = entry["amount"] or amount

    items = [record("", name, statistics.median(entry["kcal"]), serving=entry["amount"] or "1 份",
                    category=entry["category"], source=SOURCE)
             for name, entry in collected.items()]
    save(SOURCE, [item for item in items if item], "營養師在新聞、健康媒體公開的熱量文章（文字部分）")


if __name__ == "__main__":
    main()
