---
name: pdf-helper
description: |
  Универсальная методология работы с PDF: чтение, извлечение таблиц/текста,
  редактирование (объединение, разделение, заполнение форм, перекраска
  аннотаций, замена страниц). Подключается на любые задачи с .pdf-файлами,
  где требуется не просто "прочитать", а сделать что-то осмысленное.

  Триггеры:
  - "PDF", ".pdf", "извлечь из pdf", "разбери pdf"
  - "объединить PDF", "разделить PDF", "merge pdf", "split pdf"
  - "заполни форму pdf", "fillable pdf", "акроформа", "AcroForm"
  - "вставь страницу в pdf", "замени страницу", "удали страницу"
  - "оглавление pdf", "закладки pdf", "bookmarks"
  - "pikepdf", "pypdf", "pdfplumber", "pdf metadata"
  - "перекрасить облачка", "polygon cloud", "аннотации pdf"
  - "сравнить два pdf", "diff pdf"
---

# pdf-helper

## Когда подключаться

Любая задача с PDF, выходящая за рамки простого чтения нескольких строк. Если пользователь просит «открой PDF» и в нём 1-2 страницы простого текста — Read tool достаточно. Всё остальное — сюда.

## Иерархия инструментов (от простого к сложному)

| Задача | Инструмент | Заметка |
|--------|------------|---------|
| Превью текста, грубое извлечение | `markitdown-mcp` | Быстро в md, но таблицы пляшут |
| Извлечение таблиц с координатами | `pdf-mcp` (jztan/pdf-mcp) | Кэширует разбор, лучше для повторных запросов |
| Метаданные, страницы, закладки | Python `pikepdf` | Стабильно работает с большими PDF |
| Слияние/разделение, перекомпоновка | Python `pypdf` | Простой API, не теряет аннотации |
| Заполнение AcroForm | Python `pypdf.PdfWriter.update_page_form_field_values()` | XFA-формы — отдельная история, обычно не поддерживается |
| Аннотации (облачка, маркеры) | Python `pikepdf` (низкоуровневые объекты PDF) | Удалять `/AP` после смены цвета — иначе старый рендер останется |
| Сравнение двух версий PDF | `pdftoppm` + perceptual hash, или сравнение текста через `markitdown` | Бинарный diff бесполезен |

**Правило**: всегда сначала смотри, есть ли подходящий MCP в `claude mcp list`. Если есть — через него. Если нужна более тонкая операция — Python.

## Типовые задачи

### Извлечение таблицы

```python
# Через pdf-mcp (предпочт.) — Claude вызовет MCP tool сам.
# Через Python — pdfplumber для текста, camelot для сложных таблиц.
import pdfplumber
with pdfplumber.open("file.pdf") as pdf:
    for page in pdf.pages:
        for table in page.extract_tables():
            print(table)
```

### Объединение нескольких PDF

```python
from pypdf import PdfWriter
writer = PdfWriter()
for f in ["a.pdf", "b.pdf", "c.pdf"]:
    writer.append(f)
writer.write("combined.pdf")
writer.close()
```

### Замена/удаление страницы

```python
from pypdf import PdfReader, PdfWriter
src = PdfReader("input.pdf")
out = PdfWriter()
for i, page in enumerate(src.pages):
    if i == 4:        # пропустить 5-ю (0-based)
        continue
    out.add_page(page)
out.write("output.pdf")
```

### Заполнение AcroForm

```python
from pypdf import PdfReader, PdfWriter
reader = PdfReader("template.pdf")
writer = PdfWriter(clone_from=reader)
writer.update_page_form_field_values(
    writer.pages[0],
    {"FullName": "Иванов И.И.", "Date": "07.05.2026"}
)
writer.write("filled.pdf")
```

### Перекраска аннотаций (например, облачка)

```python
import pikepdf
pdf = pikepdf.open("input.pdf")
for page in pdf.pages:
    for annot in page.get("/Annots", []):
        if annot.get("/Subtype") == "/PolygonCloud":
            annot["/C"]  = [1, 0, 0]    # красный border
            annot["/IC"] = [1, 0, 0]    # красная заливка
            if "/AP" in annot:
                del annot["/AP"]         # ВАЖНО: удалить cached appearance
pdf.save("output.pdf")
```

## Ловушки

1. **Большие PDF (>50 МБ)** — `pymupdf` (fitz) часто падает на сложной структуре или ест 4+ ГБ RAM. Использовать связку `pikepdf` (низкоуровневая работа) + `pypdf` (комбинаторика страниц).
2. **`/AP` в аннотациях** — это закэшированный рендер. После изменения цвета или текста обязательно удалить, иначе PDF-вьюер покажет старое.
3. **OCR vs текст** — если PDF — скан, `extract_text()` вернёт пусто. Сначала прогнать через OCR (tesseract / cloud API), потом работать.
4. **Сравнение «что изменилось» между двумя PDF** — бинарный diff бесполезен. Лучший путь: отрендерить страницы в PNG (`pdftoppm`) и сравнить через perceptual hash (imagehash) или multimodal vision.
5. **Шрифты при редактировании** — если меняешь текст в PDF и нужный шрифт не embedded, текст потеряется. Проверять через `reader.metadata` или `pikepdf` perms.
6. **Сжатие при сохранении** — `pikepdf.save()` по умолчанию пересжимает. Для минимальных правок передать `linearize=True` или ничего, а вот `compress_streams=False` сохранит исходные потоки.

## Когда вызывать агента pdf-reviewer

После любой существенной правки PDF (удалили страницы, добавили аннотации, изменили формы) — спавнить subagent `pdf-reviewer` с задачей «проверь итоговый PDF на сохранность структуры». Агент сам проверит количество страниц, метаданные, целостность аннотаций, выдаст отчёт.

## MCP-роутинг (повтор для удобства)

| Задача | MCP server | Скилл fallback |
|--------|------------|----------------|
| Чтение текста | markitdown | pdfminer |
| Чтение таблиц | pdf-mcp | pdfplumber |
| Редактирование | (нет MCP) | pikepdf + pypdf |
| Аннотации | (нет MCP) | pikepdf низкоуровневый |
