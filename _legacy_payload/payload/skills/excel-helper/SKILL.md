---
name: excel-helper
description: |
  Универсальная методология работы с Excel: чтение, запись, анализ формул,
  выявление расхождений между листами/файлами, валидация, сравнение версий.
  Подключается на любые задачи с .xlsx где требуется не просто "открой
  файл", а осмысленный анализ или правка.

  Триггеры:
  - "Excel", ".xlsx", ".xls", ".csv"
  - "формулы Excel", "анализ Excel", "валидация Excel"
  - "сравнить таблицы", "найди расхождения", "diff xlsx"
  - "сводная", "pivot", "summary"
  - "openpyxl", "pandas", "формула не считает"
  - "дубликаты", "уникальные значения"
  - "циркулярная ссылка", "#REF!", "#DIV/0", "#NAME?"
  - "условное форматирование", "conditional formatting"
---

# excel-helper

## Когда подключаться

Любая задача с `.xlsx` где нужно понять структуру, найти ошибки, сравнить, посчитать. Если просто «открой файл и покажи первую строку» — Read tool через MCP excel хватит, без скилла.

## Иерархия инструментов

| Задача | Инструмент | Заметка |
|--------|------------|---------|
| CRUD ячеек, листов, форматов | `excel-mcp-server` | Стандартный путь, через Claude напрямую |
| Анализ всего файла, агрегации | Python `openpyxl` | Когда нужны цикл/условия/перебор сотен строк |
| Сравнение двух файлов | Python `pandas` | DataFrame.compare() или merge + diff |
| Большие файлы (>100к строк) | Python `pandas` с `chunksize` или `polars` | openpyxl читает медленно |
| Чтение формул как текст vs значений | `openpyxl` с `data_only=False` (формулы) или `data_only=True` (значения) | По умолчанию формулы |
| Запись формул | excel-mcp поддерживает; openpyxl: `cell.value = "=SUM(A1:A10)"` | Excel пересчитает при открытии |

## Типовые задачи

### Найти расхождения между двумя файлами

```python
import pandas as pd
df1 = pd.read_excel("v1.xlsx", sheet_name="Sheet1")
df2 = pd.read_excel("v2.xlsx", sheet_name="Sheet1")

# Если ключ — колонка "ID":
merged = df1.merge(df2, on="ID", how="outer", indicator=True, suffixes=("_v1", "_v2"))
print(merged[merged["_merge"] != "both"])  # что добавилось/удалилось

# Расхождения в общих строках:
common = merged[merged["_merge"] == "both"]
for col in [c for c in df1.columns if c != "ID"]:
    diff = common[common[f"{col}_v1"] != common[f"{col}_v2"]]
    if not diff.empty:
        print(f"\n=== {col} ===")
        print(diff[["ID", f"{col}_v1", f"{col}_v2"]])
```

### Валидация формул — найти #REF! / #DIV/0! / #NAME?

```python
from openpyxl import load_workbook
wb = load_workbook("file.xlsx", data_only=True)  # data_only=True вернёт CACHED значения
errors = []
for sheet in wb.sheetnames:
    ws = wb[sheet]
    for row in ws.iter_rows():
        for cell in row:
            if cell.value and isinstance(cell.value, str) and cell.value.startswith("#"):
                errors.append((sheet, cell.coordinate, cell.value))
for e in errors:
    print(f"{e[0]}!{e[1]}: {e[2]}")
```

**Важно**: чтобы Excel пересчитал и закэшировал значения, файл должен быть открыт и сохранён в Excel хотя бы один раз. Если файл создан Python — `data_only=True` вернёт `None` для формул.

### Найти дубликаты по ключу

```python
import pandas as pd
df = pd.read_excel("file.xlsx")
dups = df[df.duplicated(subset=["ID"], keep=False)]
print(dups.sort_values("ID"))
```

### Найти циркулярные ссылки

`openpyxl` напрямую их не флагует. Косвенный признак: в `data_only=True` mode значение ячейки `0` или `None`, а в `data_only=False` mode — формула, ссылающаяся (прямо или транзитивно) на саму себя. Простой эвристический поиск:

```python
import re
from openpyxl import load_workbook
wb = load_workbook("file.xlsx", data_only=False)
for ws in wb.worksheets:
    for row in ws.iter_rows():
        for cell in row:
            if isinstance(cell.value, str) and cell.value.startswith("="):
                # Самопрямая ссылка:
                if cell.coordinate in cell.value:
                    print(f"Self-ref: {ws.title}!{cell.coordinate} = {cell.value}")
```

### Условное форматирование (выделить ошибки)

`excel-mcp` это умеет. Через Python:

```python
from openpyxl import load_workbook
from openpyxl.styles import PatternFill
wb = load_workbook("file.xlsx")
ws = wb["Sheet1"]
red = PatternFill(start_color="FFCCCC", end_color="FFCCCC", fill_type="solid")
for row in ws.iter_rows(min_row=2):
    for cell in row:
        if cell.value is None:
            cell.fill = red
wb.save("highlighted.xlsx")
```

## Ловушки

1. **Locale (русская)** — формулы хранятся английскими функциями (`SUM`, `IF`), а отображаются `СУММ`, `ЕСЛИ`. При записи через Python — пиши на английском, Excel сам переведёт.
2. **Десятичный разделитель** — в русской локали запятая, в файлах CSV. Pandas: `pd.read_csv(..., decimal=",")`.
3. **Кодировка CSV от 1С** — обычно `cp1251` (Windows-1251). Если получишь "Я€" вместо русских — `encoding="cp1251"`.
4. **Дата в Excel — это число** (с 1900-01-01 = 1). При сравнении дат в pandas из xlsx — конвертировать через `pd.to_datetime()`.
5. **Пустые ячейки vs `None` vs `0`** — openpyxl возвращает `None` для пустых, `pandas` — `NaN`. Не путать с `0`.
6. **Объединённые ячейки (merged)** — значение хранится только в верхней-левой ячейке диапазона; остальные `None`. Для итерации `for row in ws.iter_rows()` придётся unmerge или пробрасывать значение из якоря.
7. **Большие файлы** — `openpyxl` читает медленно (~1 сек на 10к строк). Для >100к строк — `pandas.read_excel` с движком `openpyxl` или `polars`.
8. **Запись через openpyxl стирает условное форматирование и сводные**, если их не загрузить с `keep_vba=True` и не пересохранить аккуратно. Лучше править через excel-mcp.

## Когда вызывать агента excel-validator

После любой правки Excel или перед сдачей файла заказчику — спавнить subagent `excel-validator`. Он проверит формулы (нет ли #REF! / #DIV/0!), типы данных по колонкам, дубликаты, расхождения с эталоном (если эталон передан), и выдаст отчёт со списком замечаний.
