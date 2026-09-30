"""新北市食材登錄平台「食品揭露專區」：業者自行登錄的商品營養標示（政府網站）

分類（parentId）→ 業者（areaId + ID）→ 商品（infoId）。
這個網站的憑證少了中繼憑證，Python 驗證不過；改用系統的 curl（macOS 信任鏈）連線，仍然完整驗證憑證。
"""

import hashlib
import html
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common import CACHE_DIR, USER_AGENT, log, record, save  # noqa: E402

SOURCE = "ntpc"
BASE = "https://foodtracer.health.ntpc.gov.tw"
_last = 0.0


def get(path: str) -> str:
    """robots.txt 允許 /w/；每秒最多一次，有暫存"""
    global _last
    url = BASE + html.unescape(path)
    cache = os.path.join(CACHE_DIR, "ntpc-" + hashlib.sha1(url.encode()).hexdigest())
    if os.path.exists(cache):
        with open(cache, encoding="utf-8") as file:
            return file.read()
    time.sleep(max(0.0, 1.0 - (time.time() - _last)))
    _last = time.time()
    result = subprocess.run(["curl", "-s", "--fail", "--max-time", "60", "-A", USER_AGENT, url], capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(f"curl {result.returncode}：{url}")
    body = result.stdout.decode("utf-8", "ignore")
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(cache, "w", encoding="utf-8") as file:
        file.write(body)
    return body


def text_of(page: str) -> str:
    page = re.sub(r"<script.*?</script>|<style.*?</style>|<!--.*?-->", "", page, flags=re.S)
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " | ", page)))


def field(text: str, label: str) -> str | None:
    match = re.search(rf"{label}\s*\([^)]*\)\s*(?:\|\s*)+([\d.]+)\s*\|", text)
    return match.group(1) if match else None


def main():
    queue, visited, companies = ["/w/foodtracer/FoodPublicInfo"], set(), {}
    while queue:
        path = queue.pop(0)
        if path in visited:
            continue
        visited.add(path)
        try:
            page = get(path)
        except Exception as error:
            log(SOURCE, str(error))
            continue
        for link in re.findall(r"""['"](/w/foodtracer/FoodPublicInfo\?parentId=\d+)['"]""", page):
            if link not in visited:
                queue.append(link)
        for card in re.findall(r'<li class="card"[^>]*location\.href=\'([^\']+)\'.*?card-title">(.*?)</div>', page, flags=re.S):
            href, name = html.unescape(card[0]), html.unescape(re.sub(r"<[^>]+>", "", card[1])).strip()
            companies.setdefault(href, name)
    log(SOURCE, f"分類 {len(visited)} 頁、業者 {len(companies)} 家")

    items = []
    for number, (company_path, company) in enumerate(companies.items(), 1):
        try:
            page = get(company_path)
        except Exception as error:
            log(SOURCE, f"{company} 失敗：{error}")
            continue
        products = sorted(set(html.unescape(link) for link in
                              re.findall(r"""['"](/w/foodtracer/FoodPublicInfo\?areaId=\d+&(?:amp;)?infoId=\d+)['"]""", page)))
        for product in products:
            try:
                text = text_of(get(product))
            except Exception as error:
                log(SOURCE, f"商品失敗：{error}")
                continue
            kcal = field(text, "熱量")
            name = re.search(r"產品\s*\|\s*介紹\s*(?:\|\s*)+([^|]{1,40}?)\s*\|", text)
            if not kcal or not name:
                continue
            volume = re.search(r"容器容量\s*[:：]\s*([^|]{1,30})", text)
            grams = field(text, "每一份量")
            serving = volume.group(1).strip() if volume else (f"1 份（{float(grams):g} g）" if grams else "1 份")
            items.append(record(
                company, name.group(1).strip(), kcal,
                protein=field(text, "蛋白質"), fat=field(text, "(?<!飽和)(?<!反式)脂肪"),
                carbs=field(text, "碳水化合物"), sugar=field(text, "糖類"), sodium=field(text, "鈉"),
                serving=serving, grams=grams, category="新北市食品揭露", source=SOURCE,
            ))
        if number % 20 == 0:
            log(SOURCE, f"業者 {number}/{len(companies)}，目前 {len(items)} 項")

    seen, unique = set(), []
    for item in items:
        if item and (item["brand"], item["name"], item.get("serving")) not in seen:
            seen.add((item["brand"], item["name"], item.get("serving")))
            unique.append(item)
    save(SOURCE, unique, "新北市食材登錄平台「食品揭露專區」業者自行登錄的營養標示（政府網站）")


if __name__ == "__main__":
    main()
