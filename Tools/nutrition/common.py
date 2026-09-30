"""抓營養資料的共用工具：禮貌地連線（每個網站每秒最多一次、遵守 robots.txt）、暫存、數字清洗、輸出。

只用 Python 內建模組，不需要另外安裝套件。
"""

import hashlib
import json
import os
import re
import ssl
import time
import urllib.error
import urllib.parse
import urllib.request
import urllib.robotparser

ROOT = os.path.dirname(os.path.abspath(__file__))
CACHE_DIR = os.path.join(ROOT, "cache")
DATA_DIR = os.path.join(ROOT, "data")

# 誠實表明身分；網站因此拒絕的話就跳過，不偽裝成瀏覽器
USER_AGENT = "CalorieWarsPersonal/1.0 (personal nutrition app; +local)"

# 有些政府網站的憑證少了新版 Python 嚴格檢查要的欄位；仍然完整驗證憑證鏈，只關掉這項嚴格檢查
_SSL = ssl.create_default_context()
_SSL.verify_flags &= ~ssl.VERIFY_X509_STRICT

_last_request: dict[str, float] = {}
_robots: dict[str, urllib.robotparser.RobotFileParser | None] = {}


class Blocked(Exception):
    """網站的 robots.txt 不允許，或拒絕連線"""


def _allowed(url: str) -> bool:
    parts = urllib.parse.urlsplit(url)
    host = f"{parts.scheme}://{parts.netloc}"
    if host not in _robots:
        parser = urllib.robotparser.RobotFileParser()
        try:
            request = urllib.request.Request(host + "/robots.txt", headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=20, context=_SSL) as response:
                parser.parse(response.read().decode("utf-8", "ignore").splitlines())
            _robots[host] = parser
        except Exception:
            _robots[host] = None  # 沒有 robots.txt 視為允許
    parser = _robots[host]
    return parser is None or parser.can_fetch(USER_AGENT, url)


def _wait(host: str, delay: float) -> None:
    elapsed = time.time() - _last_request.get(host, 0)
    if elapsed < delay:
        time.sleep(delay - elapsed)
    _last_request[host] = time.time()


def fetch(url: str, data: bytes | None = None, headers: dict | None = None,
          delay: float = 1.0, use_cache: bool = True, check_robots: bool = True) -> bytes:
    """抓一個網址；同樣的請求會用暫存，不重複抓"""
    # 網址裡有中文等非 ASCII 字元時先編碼（已編碼的 % 不會重複編碼）
    url = urllib.parse.quote(url, safe=":/?&=%#+,;@!$'()*[]~")
    key = hashlib.sha1((url + "\n" + (data or b"").decode("utf-8", "ignore")).encode()).hexdigest()
    path = os.path.join(CACHE_DIR, key)
    if use_cache and os.path.exists(path):
        with open(path, "rb") as file:
            return file.read()
    if check_robots and not _allowed(url):
        raise Blocked(f"robots.txt 不允許：{url}")

    _wait(urllib.parse.urlsplit(url).netloc, delay)
    request = urllib.request.Request(url, data=data, headers={"User-Agent": USER_AGENT, **(headers or {})})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=60, context=_SSL) as response:
                body = response.read()
            break
        except urllib.error.HTTPError as error:
            if error.code in (401, 403):
                raise Blocked(f"{error.code}：{url}") from error
            if attempt == 2 or error.code < 500 and error.code != 429:
                raise
            time.sleep(5 * (attempt + 1))
        except urllib.error.URLError:
            if attempt == 2:
                raise
            time.sleep(5 * (attempt + 1))

    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(path, "wb") as file:
        file.write(body)
    return body


def fetch_json(url: str, payload: dict | None = None, **kwargs):
    data = json.dumps(payload).encode() if payload is not None else None
    headers = {"Content-Type": "application/json;charset=UTF-8", "Accept": "application/json"} if payload is not None else {}
    headers.update(kwargs.pop("headers", {}))
    return json.loads(fetch(url, data=data, headers=headers, **kwargs))


def num(value) -> float | None:
    """「12.3公克」「1,234」「<0.1」「T」「-」→ 數字；讀不出來回傳 None"""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    text = str(value).strip().replace(",", "").replace("，", "")
    if text in ("", "-", "--", "—", "N/A", "NA", "N.A.", "T", "Tr", "tr"):
        return 0.0 if text in ("T", "Tr", "tr") else None
    if text.startswith("<") or text.startswith("＜"):
        return 0.0
    match = re.search(r"-?\d+(?:\.\d+)?", text)
    return float(match.group()) if match else None


def record(brand: str, name: str, kcal, *, protein=None, fat=None, carbs=None, sugar=None, sodium=None,
           serving: str = "", grams=None, category: str = "", barcode: str | None = None, source: str = "") -> dict | None:
    """整理成 App 用的一筆資料；沒有熱量或名稱的不收"""
    kcal = num(kcal)
    name = re.sub(r"\s+", " ", (name or "")).strip()
    if not name or kcal is None or kcal < 0 or kcal > 5000:
        return None

    def clean(value):
        value = num(value)
        return round(value, 1) if value is not None and value >= 0 else None

    item = {
        "brand": brand,
        "name": name,
        "kcal": round(kcal),
        "protein": clean(protein),
        "fat": clean(fat),
        "carbs": clean(carbs),
        "sugar": clean(sugar),
        "sodium": clean(sodium),
        "serving": serving.strip(),
        "grams": clean(grams),
        "category": category.strip(),
        "barcode": barcode or None,
        "source": source,
    }
    return {key: value for key, value in item.items() if value not in (None, "")}


def save(source: str, records: list[dict], note: str = "") -> None:
    os.makedirs(DATA_DIR, exist_ok=True)
    records = [item for item in records if item]
    path = os.path.join(DATA_DIR, f"{source}.json")
    with open(path, "w", encoding="utf-8") as file:
        json.dump({"source": source, "note": note, "updated": time.strftime("%Y-%m-%d"),
                   "count": len(records), "items": records}, file, ensure_ascii=False, indent=1)
    print(f"[{source}] 存了 {len(records)} 筆 → {path}")


def log(source: str, message: str) -> None:
    print(f"[{source}] {message}", flush=True)


# ---------- 圖片、PDF 表格（用 macOS 內建文字辨識） ----------

import itertools  # noqa: E402
import subprocess  # noqa: E402

OCR_BIN = os.path.join(ROOT, "ocr_table")
_OCR_FIX = str.maketrans({"O": "0", "o": "0", "D": "0", "Z": "2", "z": "2", "I": "1", "l": "1", "|": "1",
                          "S": "5", "s": "5", "B": "8", "g": "9", "q": "9", "，": "", ",": ""})


def ocr(paths: list[str]) -> list[dict]:
    """回傳 [{"file", "page", "rows": [[格子文字, ...], ...]}]"""
    if not os.path.exists(OCR_BIN):
        subprocess.run(["swiftc", "-O", "-o", OCR_BIN, os.path.join(ROOT, "ocr_table.swift")], check=True)
    result = subprocess.run([OCR_BIN, *paths], check=True, capture_output=True)
    return json.loads(result.stdout)


def ocr_number(cell: str) -> float | None:
    """辨識錯字修正後轉數字：「88Z」→ 882、「1,037」→ 1037；夾雜其他字的格子當作讀不到"""
    text = cell.strip().translate(_OCR_FIX)
    text = re.sub(r"[公克大卡毫gGmMkKcalCAL()（）\s]", "", text)
    if re.fullmatch(r"-?\d+(?:\.\d+)?", text):
        return float(text)
    if text in ("-", "—", "–", "0.0", "0"):
        return 0.0
    return None


def energy_error(kcal, protein, fat, carbs) -> float:
    """熱量和「蛋白質×4 + 碳水×4 + 脂肪×9」差多少（比例）"""
    if not kcal:
        return 1.0
    return abs((protein or 0) * 4 + (carbs or 0) * 4 + (fat or 0) * 9 - kcal) / kcal


# 辨識漏掉數字時，先假設漏的是哪一欄（小的 0 最常漏）
_GAP_COST = {"transfat": 0, "satfat": 1, "grams": 2, "sodium": 3, "sugar": 4, "fiber": 4, "caffeine": 4}


def _violations(row: dict) -> int:
    """不合理的組合：飽和脂肪比總脂肪多、糖比碳水多、反式脂肪超過 2 克…"""
    bad = 0
    fat, carbs = row.get("fat"), row.get("carbs")
    if row.get("satfat") is not None and fat is not None and row["satfat"] > fat + 0.1:
        bad += 1
    if row.get("transfat") is not None and row["transfat"] > 2:
        bad += 1
    if row.get("sugar") is not None and carbs is not None and row["sugar"] > carbs + 0.5:
        bad += 1
    if row.get("grams") is not None and row.get("kcal") and row["grams"] < row["kcal"] / 9.5:
        bad += 1  # 每克不可能超過 9 大卡
    return bad


def fit_columns(values: list[float | None], columns: list[str], tolerance: float = 0.3) -> dict | None:
    """把一列數字對到欄位。數字少了幾個（辨識漏掉）時，試各種空位，挑最合理的：
    熱量要和「蛋白質×4 + 碳水×4 + 脂肪×9」對得起來、不能有不合理的組合，平手時先假設漏的是最常漏的欄位。

    columns 要包含 kcal、protein、fat、carbs；其他欄位（grams、satfat…）照順序放。
    """
    need = len(columns)
    numbers = list(values)[:need]
    missing = need - len(numbers)
    if not any(field in columns for field in ("protein", "fat", "carbs")):
        # 沒有三大營養素可以驗算：數字個數要剛好對上，不猜
        return dict(zip(columns, numbers)) if missing == 0 else None
    best, best_score = None, None
    for gaps in itertools.combinations(range(need), missing):
        filled, it = [], iter(numbers)
        for index in range(need):
            filled.append(None if index in gaps else next(it))
        row = dict(zip(columns, filled))
        if row.get("kcal") is None or _violations(row):
            continue
        error = energy_error(row.get("kcal"), row.get("protein"), row.get("fat"), row.get("carbs"))
        if error > tolerance:
            continue
        gap_cost = sum(_GAP_COST.get(columns[index], 10) for index in gaps)
        score = (round(error, 2), gap_cost)
        if best_score is None or score < best_score:
            best, best_score = row, score
    return best


def parse_ocr_table(pages: list[dict], columns: list[str], min_numbers: int | None = None) -> list[tuple[str, str, dict]]:
    """把辨識出來的表格轉成 (分類, 品名, 數值)；只有一格文字的列當作分類標題"""
    min_numbers = min_numbers or max(3, len(columns) - 3)
    items, category = [], ""
    for page in pages:
        for cells in page["rows"]:
            texts = [cell.strip() for cell in cells if cell.strip()]
            if not texts:
                continue
            numbers = [ocr_number(cell) for cell in texts]
            name_cells = [text for text, number in zip(texts, numbers) if number is None]
            values = [number for number in numbers if number is not None]
            if not values and len(texts) == 1:
                category = texts[0]
                continue
            if len(values) < min_numbers or not name_cells:
                continue
            row = fit_columns(values, columns)
            if row:
                items.append((category, name_cells[0], row))
    return items


# ---------- 網頁 HTML 表格 ----------

import html as _html  # noqa: E402

_FIELD_WORDS = [
    ("kcal", ("熱量", "卡路里", "kcal", "大卡", "Kcal", "KCAL", "Calorie")),
    ("protein", ("蛋白",)),
    ("fat", ("脂肪", "油脂")),
    ("carbs", ("碳水", "醣類")),
    ("sugar", ("糖",)),
    ("sodium", ("鈉",)),
    ("serving", ("重量", "份量", "容量", "規格", "克數", "毫升")),
]
_NAME_WORDS = ("品項", "名稱", "餐點", "飲品", "產品", "口味", "項目", "品名", "商品", "食物", "菜色", "種類")
_SKIP_WORDS = ("價格", "售價", "元", "咖啡因", "GI", "膳食纖維", "纖維", "飽和", "反式", "代糖", "推薦", "備註", "建議")


def html_tables(page: str) -> list[list[list[str]]]:
    """網頁裡所有表格 → [表格][列][格子文字]"""
    tables = []
    for table in re.findall(r"<table.*?</table>", page, flags=re.S | re.I):
        rows = []
        for row in re.findall(r"<tr.*?</tr>", table, flags=re.S | re.I):
            cells = re.findall(r"<t[hd][^>]*>(.*?)</t[hd]>", row, flags=re.S | re.I)
            rows.append([re.sub(r"\s+", " ", _html.unescape(re.sub(r"<[^>]+>", " ", cell))).strip() for cell in cells])
        if rows:
            tables.append(rows)
    return tables


def _field_of(header: str) -> tuple[str | None, str]:
    """表頭 → (欄位, 杯型或份量的前綴)，例如「大杯 熱量 (kcal)」→ ("kcal", "大杯")"""
    text = header.replace(" ", "")
    if any(word in text for word in _SKIP_WORDS) and not any(word in text for word in ("熱量", "kcal")):
        return None, ""
    for field, words in _FIELD_WORDS:
        for word in words:
            if word in text:
                prefix = text[: text.find(word)].strip("()（）/:：-")
                return field, prefix
    return None, ""


def _is_nutrition_label(cell: str) -> bool:
    field, _ = _field_of(cell)
    return field in ("kcal", "protein", "fat", "carbs")


def parse_nutrition_table(rows: list[list[str]]) -> list[dict]:
    """把一個表格轉成 [{"name", "size", "kcal", ...}]；看不懂的表格回傳空"""
    if len(rows) < 2:
        return []
    # 第一欄是營養素名稱（品項橫著排）的表格，先轉置
    if sum(1 for row in rows if row and _is_nutrition_label(row[0])) >= 2:
        width = max(len(row) for row in rows)
        rows = [[row[index] if index < len(row) else "" for row in rows] for index in range(width)]

    header = rows[0]
    name_col, groups = None, {}
    for index, cell in enumerate(header):
        field, prefix = _field_of(cell)
        if field:
            groups.setdefault(prefix, {})[field] = index
        elif name_col is None and (any(word in cell for word in _NAME_WORDS) or index == 0):
            name_col = index
    groups = {prefix: fields for prefix, fields in groups.items() if "kcal" in fields}
    if name_col is None or not groups:
        return []
    shared = groups.get("", {})

    items = []
    for row in rows[1:]:
        if name_col >= len(row):
            continue
        name = re.sub(r"\s+", " ", row[name_col]).strip(" *※")
        if not name or _is_nutrition_label(name) or len(name) > 40:
            continue
        for prefix, fields in groups.items():
            merged = {**shared, **fields}
            values = {field: row[index] for field, index in merged.items() if index < len(row)}
            if num(values.get("kcal")) is None:
                continue
            items.append({"name": name, "size": prefix, **values})
    return items


def parse_ocr_with_header(pages: list[dict]) -> list[tuple[str, str, dict]]:
    """表頭不固定的表格圖片：先找含「熱量」的表頭列，依表頭決定數字欄位，再逐列對欄位"""
    numeric_fields = ("kcal", "protein", "fat", "carbs", "sugar", "sodium")
    items = []
    for page in pages:
        columns, category = None, ""
        for cells in page["rows"]:
            texts = [cell.strip() for cell in cells if cell.strip()]
            if not texts:
                continue
            fields = [_field_of(text)[0] for text in texts]
            if "kcal" in fields:
                columns = [field for field in fields if field in numeric_fields]
                continue
            numbers = [ocr_number(text) for text in texts]
            name_cells = [text for text, number in zip(texts, numbers) if number is None]
            values = [number for number in numbers if number is not None]
            if not values and len(texts) == 1:
                category = texts[0]
                continue
            if not columns or not name_cells or not values:
                continue
            row = fit_columns(values, columns)
            if row and row.get("kcal"):
                items.append((category, name_cells[0], row))
    return items
