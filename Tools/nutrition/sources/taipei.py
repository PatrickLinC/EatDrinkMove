"""臺北市食材登錄平台：各專區業者自行登錄的商品熱量（政府網站）

專區 → 業者 → 商品頁。專區的業者清單和業者的商品清單一次只列一批，其餘要按「瀏覽更多」（網站用 AJAX 載入），這裡照網站的做法一批批載完。
商品頁的熱量有兩種寫法：
- 表格「每一份量(克) | 熱量(卡) | 100 | 371」
- 「容量：M杯半糖(16oz) | 熱量（大卡）：202」
"""

import html
import json
import os
import re
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common import fetch, log, record, save  # noqa: E402

SOURCE = "taipei"
SITE = "https://foodtracer.health.gov.taipei/"
SECTIONS = ["上市及上櫃連鎖餐飲專區", "西式連鎖速食專區", "連鎖咖啡廳專區", "連鎖早餐店專區", "連鎖日式拉麵專區",
            "連鎖飲冰品專區", "醫院美食街專區", "賣場專區", "伴手禮專區", "日夜市專區", "飯店Buffet專區"]
# 業者前幾項商品都沒登錄熱量的話，其他商品通常也沒有，整家跳過
PROBE = 3

MORE = re.compile(r"UniPageMoreAction\('([^']+)','(contentBody_m\w+)','content_m\w+'\);\"[^>]*>瀏覽更多</a>\s*</div>\s*"
                  r"<input type='hidden' id='cqs' name='cqs'\s+value='([^']*)'/>\s*"
                  r"<input type='hidden' id='pcid' value='([^']*)'")


def text_of(page: str) -> str:
    page = re.sub(r"<script.*?</script>|<style.*?</style>|<!--.*?-->", "", page, flags=re.S)
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " | ", page)))


def absolute(href: str, base: str) -> str:
    """連結依它所在的頁面換成完整網址（首頁是 ./UniPages/…，內頁是 ../UniPages/…）"""
    return urllib.parse.urljoin(base, html.unescape(href))


def field(text: str, label: str) -> str | None:
    match = re.search(rf"{label}\s*[（(][^）)]*[）)]\s*[:：]\s*([\d.]+)", text) or re.search(rf"{label}\s*[:：]\s*([\d.]+)", text)
    return match.group(1) if match else None


def expand(url: str, page: str, pattern: str) -> str:
    """把含有 pattern 連結的清單按「瀏覽更多」全部載完，回傳原頁加上後面各批的 HTML"""
    pqs = re.search(r"id='pqs'[^>]*value='([^']*)'", page)
    if not pqs:
        return page
    parts = [page]
    for match in MORE.finditer(page):
        action, body_id, cqs, pcid = match.groups()
        start = page.find(body_id)
        if start < 0 or not re.search(pattern, page[start:match.start()]):
            continue
        cqs = html.unescape(cqs)
        for _ in range(200):
            if '"recordsIsLast":"1"' in cqs:
                break
            query = urllib.parse.urlencode({"pqs": html.unescape(pqs.group(1)), "pcid": pcid, "cqs": cqs})
            try:
                response = json.loads(fetch(urllib.parse.urljoin(url, action) + "?" + query, data=b"",
                                            headers={"Content-Type": "application/x-www-form-urlencoded; charset=utf-8"}))
            except Exception as error:
                log(SOURCE, f"瀏覽更多失敗：{error}")
                break
            body = response.get("tempbody") or ""
            if not re.search(pattern, body) or response.get("cqs") in (None, "", cqs):
                parts.append(body)
                break
            parts.append(body)
            cqs = response["cqs"]
    return "\n".join(parts)


def product(text: str, company: str, section: str) -> dict | None:
    name = re.search(r"下載公告\s*(?:\|\s*)+([^|]{1,60}?)\s*\|", text)
    if not name or name.group(1).startswith("@"):
        return None
    name = name.group(1).strip()
    table = re.search(r"每一份量\s*[（(]克[）)]\s*(?:\|\s*)+熱量\s*[（(]卡[）)]\s*(?:\|\s*)+"
                      r"([^|]{1,30}?)\s*(?:\|\s*)+([^|]{1,30}?)\s*\|", text)
    if table:
        grams = re.search(r"\d+(?:\.\d+)?", table.group(1))
        kcal = re.search(r"\d+(?:\.\d+)?", table.group(2))
        if not kcal:
            return None
        return record(company, name, kcal.group(), serving=f"{float(grams.group()):g} g" if grams else "1 份",
                      grams=grams.group() if grams else None, category=section, source=SOURCE)
    kcal = field(text, "熱量")
    if not kcal:
        return None
    volume = re.search(r"容量\s*[:：]\s*([^|]{1,30})", text)
    serving = volume.group(1).strip() if volume else "1 份"
    grams = re.search(r"([\d.]+)\s*(?:g|公克|克|ml|毫升|c\.c\.|cc)", serving, flags=re.I)
    return record(company, name, kcal,
                  protein=field(text, "蛋白質"), fat=field(text, "(?<!飽和)(?<!反式)脂肪"),
                  carbs=field(text, "碳水化合物"), sugar=field(text, "(?<!代)糖"), sodium=field(text, "鈉"),
                  serving=serving, grams=grams.group(1) if grams else None, category=section, source=SOURCE)


def main():
    home = fetch(SITE).decode("utf-8", "ignore")
    sections = {}
    for href, label in re.findall(r'<a[^>]+href="([^"]*CustPageView[^"]*)"[^>]*>(.*?)</a>', home, flags=re.S):
        label = re.sub(r"<[^>]+>", "", label).strip()
        if label in SECTIONS:
            sections[label] = absolute(href, SITE)

    items = []
    for section, url in sections.items():
        listing = expand(url, fetch(url).decode("utf-8", "ignore"), r"company_id=")
        companies = {}
        for href, label in re.findall(r'<a[^>]+href="([^"]*company_id=[^"&]+[^"]*)"[^>]*>(.*?)</a>', listing, flags=re.S):
            if "itemno" in href or "sel_product_type" in href:
                continue
            name = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", label))).strip()
            companies.setdefault(absolute(href, url), name)
        log(SOURCE, f"{section}：{len(companies)} 家業者")

        before = len(items)
        for company_url, company in companies.items():
            try:
                page = fetch(company_url).decode("utf-8", "ignore")
            except Exception as error:
                log(SOURCE, f"{company} 失敗：{error}")
                continue
            # 用招牌名稱（例如「喫茶趣」），沒有才用公司登記名稱
            brand = re.search(r"\|\s*([^|]{1,30}?)\s*(?:\|\s*)+公司名稱\s*[:：]\s*([^|]+)", text_of(page))
            if brand:
                company = brand.group(1).strip() if brand.group(1).strip() not in ("下載公告", "") else brand.group(2).strip()
            page = expand(company_url, page, r"itemno=\d+")
            products = sorted(set(absolute(href, company_url) for href in re.findall(r'href="([^"]*itemno=\d+[^"]*)"', page)),
                              key=lambda link: int(re.search(r"itemno=(\d+)", link).group(1)))
            found = 0
            for number, product_url in enumerate(products):
                if number >= PROBE and not found:
                    break
                try:
                    item = product(text_of(fetch(product_url).decode("utf-8", "ignore")), company, section)
                except Exception as error:
                    log(SOURCE, f"商品失敗：{error}")
                    continue
                if item:
                    items.append(item)
                    found += 1
        log(SOURCE, f"{section} 完成，本區 {len(items) - before} 項，累計 {len(items)} 項")

    seen, unique = set(), []
    for item in items:
        if item and (item["brand"], item["name"], item.get("serving")) not in seen:
            seen.add((item["brand"], item["name"], item.get("serving")))
            unique.append(item)
    save(SOURCE, unique, "臺北市食材登錄平台業者自行登錄的商品熱量（政府網站）")


if __name__ == "__main__":
    main()
