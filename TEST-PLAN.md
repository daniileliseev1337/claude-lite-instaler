# TEST-PLAN: Apply-ClaudeMd.ps1 — 4 кейса

Test-plan для безопасной проверки миграционной логики Stage 7 без
ущерба для рабочей `~/.claude/` на твоём ноутбуке/рабочем ПК.

## Окружение — Windows Sandbox (рекомендую)

Sandbox чистый при каждом запуске, не оставляет следов. Идеально для теста.

**Bootstrap (один раз на запуск Sandbox):**

1. Запусти `WindowsSandbox.exe`.
2. Внутри Sandbox: проверь что нет git: `git --version`. Если нет:
   - Скачай Git for Windows: https://git-scm.com/download/win
   - Запусти installer (default options ок).
3. Drag-drop папку `claude-lite-instaler` внутрь Sandbox-окна (например, на рабочий стол).
4. Открой PowerShell как обычный user.
5. `cd ~/Desktop/claude-lite-instaler`
6. `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`

После этого можно запускать тесты.

**Альтернатива без Sandbox** — временная Home-переменная:

```powershell
# Создаёт изолированную тестовую директорию вместо $env:USERPROFILE
$testHome = Join-Path $env:TEMP "claude-test-$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Path $testHome -Force
$env:USERPROFILE = $testHome  # ВНИМАНИЕ: только для текущего PS-окна
# теперь Apply-ClaudeMd.ps1 будет писать в $testHome\.claude вместо реальной
```

После теста: закрой это окно PowerShell — переменные исчезнут, твоя реальная `~/.claude/` цела. Папку $env:TEMP\claude-test-* удалить вручную.

---

## Case 1 — Fresh install (clean ~/.claude/)

**Setup:**
```powershell
# Убедись что ~/.claude/ нет
Test-Path "$env:USERPROFILE\.claude"   # должно быть False

# Если есть — переименуй (только в Sandbox / тестовом окружении!)
# Move-Item "$env:USERPROFILE\.claude" "$env:USERPROFILE\.claude.before-test"
```

**Run:**
```powershell
.\Apply-ClaudeMd.ps1
```

**Ожидание:**
- Сообщение «`~/.claude/ не существует — клонирую claude-base...`»
- `git clone https://github.com/K7-LS/claude-base.git ~/.claude/`
- Сообщение «`✓ claude-base склонирован в ...`»

**Проверка PASS:**
```powershell
# 1. Папка создана
Test-Path "$env:USERPROFILE\.claude\CLAUDE.md"          # True

# 2. Это git-репо
Test-Path "$env:USERPROFILE\.claude\.git"               # True

# 3. Remote корректный
git -C "$env:USERPROFILE\.claude" remote -v
# должно показать: origin https://github.com/K7-LS/claude-base.git

# 4. Все ожидаемые папки на месте
Get-ChildItem "$env:USERPROFILE\.claude" -Directory | Select-Object Name
# должно быть: agents, harvested, memory, sessions, skills, _sandbox

# 5. Агенты на месте
Get-ChildItem "$env:USERPROFILE\.claude\agents\*.md" | Select-Object Name
# должно быть: auditor.md, designer.md, excel-validator.md, pdf-reviewer.md, word-checker.md

# 6. CLAUDE.md имеет CORE/USER EXTENSIONS секции
Select-String -Path "$env:USERPROFILE\.claude\CLAUDE.md" -Pattern "BEGIN CORE|BEGIN USER EXTENSIONS"
# должно показать обе строки
```

**FAIL-сигналы:**
- `git clone` не сработал — обычно прокси/сеть. Сообщение о fatal в выводе.
- Папок agents/skills нет — git pull частично; повторить.
- Wrong remote — что-то странное в скрипте.

---

## Case 2 — Update existing (правильный remote)

**Setup (после Case 1):**
```powershell
# ~/.claude/ уже существует и привязана к claude-base после Case 1.
# Имитируем "что-то изменилось в claude-base" — на remote был коммит.
# (Не нужно делать ничего — на github.com уже есть актуальный main.)

# Опционально: добавь USER EXTENSIONS чтобы проверить preservation
$claudemd = "$env:USERPROFILE\.claude\CLAUDE.md"
$content = Get-Content $claudemd -Raw
$content = $content -replace '<!-- END USER EXTENSIONS -->',
    "## My Test Rule`n`nThis line should survive git pull.`n`n<!-- END USER EXTENSIONS -->"
Set-Content -Path $claudemd -Value $content -NoNewline
```

**Run:**
```powershell
.\Apply-ClaudeMd.ps1
```

**Ожидание:**
- Сообщение «`Remote совпадает с claude-base. Pull...`»
- `git pull --rebase --autostash` — Already up to date / + rebase apply.
- Сообщение «`✓ ~/.claude/ обновлён из claude-base`»

**Проверка PASS:**
```powershell
# 1. USER EXTENSIONS сохранились
Select-String -Path "$env:USERPROFILE\.claude\CLAUDE.md" -Pattern "My Test Rule"
# должна найтись

# 2. CORE секция не повреждена
Select-String -Path "$env:USERPROFILE\.claude\CLAUDE.md" -Pattern "BEGIN CORE|END CORE"
# обе на месте

# 3. Working tree clean
git -C "$env:USERPROFILE\.claude" status
# должно быть "nothing to commit, working tree clean" ИЛИ "modified: CLAUDE.md" если правка USER EXT не закоммичена локально (это норма)
```

**FAIL-сигналы:**
- USER EXTENSIONS пропала после pull → critical bug в стратегии git pull.
- Conflict в git rebase → нужно посмотреть `git status`, `git rebase --continue` после ручного резолва.

---

## Case 3 — Wrong remote (error path)

**Setup:**
```powershell
# Убери текущий remote, поставь чужой
git -C "$env:USERPROFILE\.claude" remote set-url origin https://github.com/some-other-user/some-other-repo.git
```

**Run:**
```powershell
.\Apply-ClaudeMd.ps1
```

**Ожидание:**
- Красное сообщение «`✗ ~/.claude/.git remote = ..., ожидалось ...`».
- Инструкция «Решите вручную: Rename-Item ... bak».
- `exit 1` — код возврата 1.

**Проверка PASS:**
```powershell
# 1. Скрипт вышел с ошибкой
$LASTEXITCODE   # должно быть 1

# 2. ~/.claude/ НЕ изменена (не было pull, не было clone)
git -C "$env:USERPROFILE\.claude" remote -v
# должно показать some-other-repo (наш скрипт не правил это)
```

**Cleanup перед Case 4:**
```powershell
git -C "$env:USERPROFILE\.claude" remote set-url origin https://github.com/K7-LS/claude-base.git
```

**FAIL-сигналы:**
- Скрипт всё-таки сделал pull/clone (не должен) → опасный bug.
- Нет красного сообщения → проблема с output форматированием.

---

## Case 4 — Migration (existing ~/.claude/ без .git)

**Самый сложный кейс. Имитируем «была ручная установка раньше».**

**Setup:**
```powershell
# Удалить .git/, оставить файлы
Remove-Item "$env:USERPROFILE\.claude\.git" -Recurse -Force

# Создать "personal files" — имитация credentials, history, plugins
@"
fake-token-for-test
"@ | Set-Content -Path "$env:USERPROFILE\.claude\.credentials.json"

@"
{"version":1,"messages":["fake history"]}
"@ | Set-Content -Path "$env:USERPROFILE\.claude\history.jsonl"

New-Item -ItemType Directory -Path "$env:USERPROFILE\.claude\projects\test-project\memory" -Force
"fake project memory" | Set-Content "$env:USERPROFILE\.claude\projects\test-project\memory\MEMORY.md"

# Что-то "лишнее" что должно уйти в backup
"some old config" | Set-Content "$env:USERPROFILE\.claude\some-old-file.txt"
```

**Run (с подтверждением):**
```powershell
.\Apply-ClaudeMd.ps1
# Ответить y когда спросит "Продолжить?"
```

**Ожидание:**
- Сообщение «`~/.claude/ существует, но это не git-репо. Нужна миграция.`»
- Список preserved items.
- Запрос подтверждения.
- Создаётся backup `~/.claude.backup-<timestamp>/`.
- preserve каждого .credentials.json, history.jsonl, projects.
- `git clone` в новую `~/.claude/`.
- restored: каждый сохранённый файл.
- Сообщение «`✓ Миграция завершена.`»

**Проверка PASS:**
```powershell
# 1. Backup создан и содержит ВСЕ старые файлы
$backup = Get-ChildItem "$env:USERPROFILE\.claude.backup-*" | Select-Object -First 1
Test-Path $backup.FullName                                  # True
Test-Path "$($backup.FullName)\.credentials.json"           # True
Test-Path "$($backup.FullName)\some-old-file.txt"           # True

# 2. Новая ~/.claude/ — это git-репо с claude-base
Test-Path "$env:USERPROFILE\.claude\.git"                   # True
git -C "$env:USERPROFILE\.claude" remote -v
# origin = claude-base

# 3. Personal files восстановлены
Test-Path "$env:USERPROFILE\.claude\.credentials.json"      # True
(Get-Content "$env:USERPROFILE\.claude\.credentials.json") -eq "fake-token-for-test"
# True (содержимое сохранилось)

Test-Path "$env:USERPROFILE\.claude\history.jsonl"          # True
Test-Path "$env:USERPROFILE\.claude\projects\test-project\memory\MEMORY.md"  # True

# 4. Лишний файл some-old-file.txt НЕ перенесён (он не в whitelist preserve) — он только в backup
Test-Path "$env:USERPROFILE\.claude\some-old-file.txt"      # False
Test-Path "$($backup.FullName)\some-old-file.txt"           # True

# 5. Новые файлы из claude-base на месте
Test-Path "$env:USERPROFILE\.claude\agents\auditor.md"      # True
Test-Path "$env:USERPROFILE\.claude\CLAUDE.md"              # True
```

**FAIL-сигналы (CRITICAL):**
- `.credentials.json` не восстановлен → **потеря авторизации**, в реальном использовании пользователь потеряет login.
- Нет backup → нет fallback при ошибке.
- Скрипт упал посередине, оставив `~/.claude/` в полузаполненном состоянии.

**Тест non-interactive (с флагом -Yes):**

Повторить setup и:
```powershell
.\Apply-ClaudeMd.ps1 -Yes
```

Должно работать без запроса подтверждения. Тот же результат.

---

## Сводная таблица результатов

После прогона всех 4 кейсов заполни (или сообщи в чат):

| Case | Setup | Run | PASS/FAIL | Замечания |
|------|-------|-----|-----------|-----------|
| 1. Fresh install | clean ~/.claude/ | `.\Apply-ClaudeMd.ps1` | | |
| 2. Update | + USER EXT | `.\Apply-ClaudeMd.ps1` | | |
| 3. Wrong remote | remote set-url other | `.\Apply-ClaudeMd.ps1` | | |
| 4. Migration | rm .git/, fake credentials | `.\Apply-ClaudeMd.ps1` | | |

## Что делать если FAIL

1. **Сохрани полный лог** PowerShell-окна в файл (`Stop-Transcript`, или просто скопируй).
2. **Не закрывай Sandbox** — состояние нужно для разбора.
3. **Сообщи мне:**
   - Какой Case упал.
   - Точное сообщение ошибки.
   - На каком шаге.
   - Текущее состояние `~/.claude/` (`Get-ChildItem`, `git status`, и т.п.).
4. Я подправлю Apply-ClaudeMd.ps1, ты пушнешь обновление в claude-lite-instaler через `git pull && git push`.

## Что после успешного прохождения 4 кейсов

- Можно запускать **полный** `.\Install.ps1` на чистом ПК (или в Sandbox с интернетом и временем для скачивания VS Code/claude/uv ~500 МБ).
- После этого — переходим к Этапу 3 (auto-pull/push hooks).
