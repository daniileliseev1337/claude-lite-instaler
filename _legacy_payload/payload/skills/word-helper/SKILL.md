---
name: word-helper
description: |
  Универсальная методология работы с Word-документами: чтение, find-replace,
  правка структуры, генерация документов, экспорт в Markdown/PDF. Подключается
  на любые задачи с .docx где требуется не просто "прочитать", а
  отредактировать или сгенерировать.

  Триггеры:
  - "Word", ".docx", ".doc", ".rtf"
  - "правки в документе", "правки в Word"
  - "генерация документа", "создать docx", "шаблон Word"
  - "find and replace docx", "замени текст в Word"
  - "оглавление Word", "стили Word", "TOC"
  - "python-docx", "mammoth", "docx2pdf"
  - "слияние Word", "комбинировать документы"
---

# word-helper

## Когда подключаться

Любая задача с `.docx`/`.doc`, выходящая за «открой и покажи». Если просто прочитать абзац — markitdown MCP справится без скилла.

## Иерархия инструментов

| Задача | Инструмент | Заметка |
|--------|------------|---------|
| Превью в Markdown | `markitdown-mcp` | Лучший общий читатель |
| CRUD абзацев, find-replace, стили | `word` MCP (office-word-mcp-server) | Прямая правка docx |
| Сложная правка структуры | Python `python-docx` | Низкоуровнево, но гибко |
| Сохранить форматирование при чтении | Python `mammoth` (docx → html) | mammoth честнее для inline-стилей |
| Генерация по шаблону | Python `python-docx-template` (docxtpl) | Jinja2 syntax внутри docx |
| Экспорт в PDF | LibreOffice headless / Word COM (если установлен) / `docx2pdf` | Без Office нет 100% точного PDF |

## Типовые задачи

### Find-and-replace по всему документу

```python
from docx import Document
doc = Document("input.docx")

replacements = {
    "{{ИМЯ}}": "Иванов И.И.",
    "{{ДАТА}}": "07.05.2026",
}

# Ловушка: текст может быть разорван на несколько runs внутри одного paragraph
# (Word делит при stylе-changes). Пройтись по runs наивно — пропустит совпадения.
# Простой надёжный способ:
for para in doc.paragraphs:
    full = para.text
    for old, new in replacements.items():
        if old in full:
            full = full.replace(old, new)
    if full != para.text:
        # Очистить runs и записать новый текст единым run'ом (теряется in-paragraph
        # форматирование — приемлемый trade-off для шаблонов).
        for run in para.runs[1:]:
            run.text = ""
        para.runs[0].text = full

# То же для таблиц
for table in doc.tables:
    for row in table.rows:
        for cell in row.cells:
            for para in cell.paragraphs:
                pass  # повторить логику выше

doc.save("output.docx")
```

Для шаблонной генерации с Jinja2-like синтаксисом проще `docxtpl`:

```python
from docxtpl import DocxTemplate
tpl = DocxTemplate("template.docx")
tpl.render({"name": "Иванов И.И.", "date": "07.05.2026"})
tpl.save("filled.docx")
```

### Извлечение структуры (заголовки, оглавление)

```python
from docx import Document
doc = Document("input.docx")
for para in doc.paragraphs:
    if para.style.name.startswith("Heading"):
        level = para.style.name.replace("Heading ", "")
        print(f"{'  ' * (int(level) - 1)}{para.text}")
```

### Слияние нескольких docx в один

```python
from docxcompose.composer import Composer
from docx import Document
master = Document("main.docx")
composer = Composer(master)
for f in ["chapter2.docx", "chapter3.docx"]:
    composer.append(Document(f))
composer.save("combined.docx")
```

(требует пакет `docxcompose`)

### Конвертация в Markdown

Через MCP markitdown — Claude вызовет сам. Через Python:

```python
import mammoth
with open("input.docx", "rb") as f:
    result = mammoth.convert_to_markdown(f)
    print(result.value)
```

### Конвертация в PDF (без Office на машине)

```bash
# LibreOffice headless (нужно установить LibreOffice)
soffice --headless --convert-to pdf input.docx
```

Без LibreOffice / Word — на чистой машине нет надёжного пути из Python. Скажи пользователю установить LibreOffice (User-installer без админа) или открыть файл в Word и сохранить как PDF вручную.

## Ловушки

1. **Разорванный `<w:t>`** — Word делит текст внутри параграфа на несколько `runs` при изменении стилей внутри предложения. Find-replace по `run.text` пропустит совпадения. Решение: операция на уровне `paragraph.text`, потом перезапись runs (см. пример выше). Минус — теряется in-paragraph форматирование.
2. **Шрифты** — если в шаблоне используется PT Astra Sans / GOST шрифт, при генерации на чужой машине без шрифта Word подменит на похожий и сместит верстку. На пользовательском ПК ставить нужные шрифты заранее.
3. **Таблицы со сложной разметкой** — `python-docx` теряет некоторые свойства cell width / borders при правке. Для табличных шаблонов лучше использовать docxtpl или править через Word MCP.
4. **Стили (Heading 1, Heading 2)** — должны существовать в документе ДО присвоения параграфу. Иначе AttributeError. Создавать через `doc.styles.add_style()` если их нет.
5. **Сохранение в .doc (старый формат)** — `python-docx` НЕ умеет, только .docx. Для .doc — конвертировать через LibreOffice headless.
6. **Раздельные секции (sections)** — для верстки альбомных листов или разных колонтитулов. python-docx работает с ними через `doc.sections`.
7. **Списки и нумерация** — глубокий enchant: `numbering.xml` в docx определяет нумерацию, на одном файле может быть несколько определений. Простая правка через python-docx может не взлететь.

## Когда вызывать агента word-checker

После генерации документа (особенно по шаблону) — спавнить subagent `word-checker`. Он проверит структуру (заголовки, оглавление), таблицы (на повреждения после правки), наличие placeholder'ов которые не заменились (`{{...}}`), форматирование. Выдаст отчёт со списком замечаний.
