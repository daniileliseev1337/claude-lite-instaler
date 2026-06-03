# claude-lite-instaler

Лёгкий установщик для **Claude Code** на Windows + PowerShell, без прав
администратора. Ставит ту же связку, что у автора базы, и подключает
`~/.claude/` к общей базе [`claude-base`](https://github.com/daniileliseev1337/claude-base)
через git.

## Что ставит — 8 стадий

| Стадия | Компонент | Куда |
|--------|-----------|------|
| 1. Proxy | `$env:HTTPS_PROXY/$env:HTTP_PROXY` для текущей сессии. host:port + login → `~/.claude-proxy.json` (без пароля). | env-vars сессии |
| 2. VS Code | User installer от Microsoft, silent. | `%LOCALAPPDATA%\Programs\Microsoft VS Code\` |
| 3. Claude Code CLI | Официальный installer Anthropic (`irm claude.ai/install.ps1 \| iex`). | `%USERPROFILE%\.local\bin\claude.exe` |
| 4. VS Code extension | `anthropic.claude-code` через Marketplace. | `%USERPROFILE%\.vscode\extensions\` |
| 5. uv | Astral installer. Нужен для `uvx`. | `%USERPROFILE%\.local\bin\uv.exe` |
| 6. MCP servers | 8 общеполезных через `claude mcp add --scope user`: `markitdown`, `document-loader`, `word`, `excel`, `pdf-mcp`, `sequential-thinking`, `fetch`, `time`. | `~/.claude.json` |
| 7. claude-base sync | `~/.claude/` становится git-рабочей-копией `claude-base`. После clone/pull: persistent GitHub bypass-proxy в global git config + `merge-shared-settings.ps1` (Phase 1 sync-redesign). | `~/.claude/` |
| 8. Setup extras | Python 3.12 + user-packages (matplotlib, ezdxf, paddleocr, easyocr, iopaint, …) + дополнительные MCP из `~/.claude/mcp-manifest.json`: `autocad-mcp`, `adeu`. Итого 10 серверов после restart. | `~/.local/`, `~/.claude/mcp-servers/` |

## Что устанавливает Stage 7 в `~/.claude/`

Из репо [`claude-base`](https://github.com/daniileliseev1337/claude-base):

- **`CLAUDE.md`** — глобальный manifest с CORE / USER EXTENSIONS секциями, STOP-процедурой, MCP-роутингом, скилл-роутингом, harvest-workflow.
- **`agents/`** — `designer` (доменный для проектирования), `auditor` (общий ревьюер), `word-checker` / `excel-validator` / `pdf-reviewer` (узкие read-only ревьюеры).
- **`skills/`** — `karpathy-guidelines`, `pdf-helper`, `excel-helper`, `word-helper`, `chains-pattern`, `handoff-to-new-chat`, и др.
- **`chains/`** — именованные многошаговые цепочки (`docx-from-template`, `pdf-scan-extract`, …).
- **`scripts/`** — инфраструктура: `auto-pull.ps1`, `auto-push.ps1`, `merge-shared-settings.ps1`, `feedback-collector.ps1`, `verify-claude-base.ps1`, **`Update-ClaudeBase.bat`** (one-command updater для будущих обновлений).
- **`settings.shared.json`** — shared между всеми ПК (language, hooks, autoMode, enabledPlugins). Phase 1 sync-redesign. После pull `merge-shared-settings.ps1` вливает эти ключи в personal `settings.json`.
- **`memory/`**, **`session-reports/`**, **`harvested/`** — структура для аналитической работы.

После установки: при следующем запуске Stage 7 делает `git pull` + **persistent GitHub bypass-proxy** + **`merge-shared-settings.ps1`** — база актуальна на каждом ПК с одинаковыми shared настройками.

## Auto-sync hooks (Phase 1+2 sync-redesign)

После Stage 7 в `~/.claude/settings.json` (через merge-shared) подключены два hook'а:

- **SessionStart hook** → `scripts/auto-pull.ps1` → `git pull --rebase --autostash`. База актуализируется автоматически при каждом старте сессии Claude Code.
- **SessionEnd hook** → `scripts/auto-push.ps1` → если есть локальные правки в managed paths (chains/, skills/, memory/, session-reports/, …) → коммит + push. На consumer-ПК (без `.developer-marker`) вместо push в main репо запускается `feedback-collector.ps1` → отправляет файлы из `feedback-pending/` в отдельный private репо `claude-base-feedback` через GitHub REST API.

**Feedback channel предлагается отдельным prompted-шагом** в конце установки (заметная зелёная секция, рекомендуется всем кроме dev-хаба). На «да» запускает `~/.claude/scripts/Update-ClaudeBase.bat` — спросит PAT и создаст `.feedback-config.json` интерактивно. Можно пропустить и включить позже тем же `.bat`.

## Что НЕ делает

- Не требует прав администратора.
- Не трогает `~/.claude/.credentials.json`, `history.jsonl`, `plugins/`, `projects/`, `cache/`, `backups/`, `file-history/`, `downloads/`, `settings.local.json` — это **личные** файлы пользователя, при миграции и pull сохраняются как есть.
- Не пишет в реестр, не правит User PATH сам.
- Не настраивает feedback channel молча — он предлагается **заметным prompted-шагом** в конце установки (запускает `Update-ClaudeBase.bat`, спросит PAT). Рекомендуется всем кроме dev-хаба; можно пропустить.

## CLAUDE.md: CORE и USER EXTENSIONS

После Stage 7 в `~/.claude/CLAUDE.md` есть две секции:

```
<!-- BEGIN CORE -->
... управляется через claude-base, обновляется при git pull ...
<!-- END CORE -->

<!-- BEGIN USER EXTENSIONS -->
... твои личные правила, специфика рабочего ПК ...
<!-- END USER EXTENSIONS -->
```

При git pull обновляется только CORE (потому что только он отслеживается активной разработкой). USER EXTENSIONS — это твоя зона, при `git pull --rebase --autostash` она сохраняется. Если возникает конфликт (одновременно правил CORE и сторону USER EXTENSIONS) — git rebase его покажет, решишь руками.

## Использование

**Способ 1 — через .cmd-обёртку:**

Двойной клик по `Install.cmd`. Откроется PowerShell с обходом ExecutionPolicy.

**Способ 2 — вручную из PowerShell:**

```powershell
# Распаковать в любую папку, перейти в неё
cd C:\Tools\claude-lite-instaler

# Разрешить запуск скриптов в этом окне
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# Запустить orchestrator (интерактивно)
.\Install.ps1

# Или non-interactive:
.\Install.ps1 -Yes
```

**Обновление существующей установки:**

Два пути:

1. **Рекомендуется:** двойной клик на `~/.claude/scripts/Update-ClaudeBase.bat` — one-command updater из claude-base. Делает: detect role → git pull → merge-shared-settings → verify (23 проверки) → (consumer) smoke-test feedback push → итоговый PASS/FAIL summary.

2. **Альтернатива:** запусти `.\Install.ps1` ещё раз. Все стадии **идемпотентны** — Stage 7 делает `git pull` + `merge-shared-settings`, Stage 8 догоняет manifest (новые MCP/pkgs из `mcp-manifest.json`).

## Миграция существующей `~/.claude/`

Если на ПК уже есть `~/.claude/` без `.git/` (например, после ручной настройки или с прошлой версией lite-installer'а), Stage 7 предложит миграцию:

1. Backup всей `~/.claude/` → `~/.claude.backup-<timestamp>/`.
2. Личные файлы сохраняются (`.credentials.json`, `history.jsonl`, `plugins/`, `projects/`, `file-history/`, `backups/`, `cache/`, `downloads/`, `settings.local.json`).
3. Текущая `~/.claude/` удаляется (полный backup есть).
4. `git clone claude-base` в `~/.claude/`.
5. Личные файлы возвращаются.

**Backup сохраняется** — можно проверить, что всё работает, и только потом удалить.

## Запуск отдельных стадий

```powershell
.\Set-Proxy.ps1               # только прокси
.\Install-VSCode.ps1          # только VS Code
.\Install-ClaudeCode.ps1      # только claude CLI
.\Install-VSCodeExt.ps1       # только VS Code extension
.\Install-UV.ps1              # только uv
.\Setup-MCP-Servers.ps1       # только MCP servers
.\Apply-ClaudeMd.ps1          # только sync ~/.claude/ с claude-base
```

## Прокси в каждой новой сессии

`Set-Proxy.ps1` ставит env-переменные **только в текущем терминале и его дочерних процессах**. Пароль в системе не оседает.

```powershell
# Способ 1: двойной клик по Set-Proxy.cmd
# Способ 2: вручную
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
& "$env:USERPROFILE\Desktop\claude-lite-instaler\Set-Proxy.ps1"

# Параметры:
.\Set-Proxy.ps1 -Off      # снять прокси
.\Set-Proxy.ps1 -Reset    # удалить сохранённый конфиг
.\Set-Proxy.ps1 -NoSave   # не сохранять host/login
```

## Corporate proxy

Стадии **2, 3, 5** (VS Code, Claude Code CLI, uv) скачивают через `irm` / `iwr` с `-Proxy $env:HTTPS_PROXY`. Работает для **Basic** аутентификации.

Если корп-прокси использует **NTLM** — нужна обвязка типа Cntlm.
Если **Negotiate / Kerberos** — `irm` не пройдёт. Manual fallback:

- VS Code: скачать `VSCodeUserSetup-x64-*.exe` через браузер, запустить с `/VERYSILENT /MERGETASKS=!runcode /NORESTART`.
- Claude Code CLI: скачать standalone бинарь из релизов и распаковать в `%USERPROFILE%\.local\bin\`.
- uv: скачать zip из релизов Astral и распаковать туда же.
- MCP servers: качаются через `uvx` если `HTTPS_PROXY` выставлен (npm/pip обычно идут через системный прокси).
- **Stage 7 (`git clone`/`pull`)**: если git настроен на использование прокси (`git config --global http.proxy ...`), всё работает; иначе — настроить.

## Глобальная горячая клавиша Ctrl+Alt+C (опционально)

Требует AutoHotkey v2.

1. Установить AutoHotkey v2 с [autohotkey.com](https://autohotkey.com) (вариант **Install for current user**).
2. Двойной клик по `Start-Claude.ahk` — в трее появится иконка.
3. **Ctrl+Alt+C** в любом окне → откроется PowerShell с прокси и выбором CLI/VSCode.

Авто-запуск при входе:
1. Win+R → `shell:startup`.
2. Создать ярлык на `Start-Claude.ahk`, переместить в Startup-папку.

## Структура

```
claude-lite-instaler/
├── README.md                  # этот файл
├── Install.cmd                # двойной клик — обёртка установки
├── Install.ps1                # orchestrator (9 стадий, banner + стилизованные секции)
├── Apply-ClaudeMd.ps1         # стадия 7 — git sync claude-base
├── Apply-ClaudeMd.ps1.OLD     # старая версия для reference (до перехода на git)
├── Start-Claude.bat           # двойной клик — прокси + claude
├── Start-Claude.ps1           # логика стартера
├── Start-Claude.ahk           # глобальная горячая клавиша Ctrl+Alt+C
├── Set-Proxy.cmd              # двойной клик — только прокси
├── Set-Proxy.ps1              # стадия 1
├── Install-VSCode.ps1         # стадия 2
├── Install-ClaudeCode.ps1     # стадия 3
├── Install-VSCodeExt.ps1     # стадия 4
├── Install-UV.ps1             # стадия 5
├── Setup-MCP-Servers.ps1      # стадия 6
└── _legacy_payload/           # архив payload до перехода на git clone
```

## Откат

| Компонент | Команда |
|-----------|---------|
| `~/.claude/` (вернуть до миграции) | переименовать `~/.claude.backup-<ts>/` обратно в `~/.claude/` |
| MCP-серверы | `claude mcp remove <name>` для каждого из 8 имён |
| VS Code extension | `code --uninstall-extension anthropic.claude-code` |
| VS Code | Settings → Apps → Microsoft Visual Studio Code → Uninstall |
| Claude Code CLI | удалить `%USERPROFILE%\.local\bin\claude.exe` |
| uv | удалить `%USERPROFILE%\.local\bin\uv.exe` и `uvx.exe` |
| Прокси-конфиг | `Remove-Item "$env:USERPROFILE\.claude-proxy.json"` |

## Идемпотентность

Все скрипты можно запускать повторно. Каждый сначала проверяет наличие компонента и выходит no-op если уже установлен. Stage 7 делает `git pull --rebase --autostash` — если уже git-репо, обновляется; если нет, мигрирует.

## Связанные репо

- [`claude-base`](https://github.com/daniileliseev1337/claude-base) — общая база, которая клонируется в `~/.claude/`.
- [`claude-base-feedback`](https://github.com/daniileliseev1337/claude-base-feedback) — private репо для feedback от сотрудников (push через `feedback-collector.ps1` на consumer-ПК, pull через `pull-feedback.ps1` на developer-ПК).

## История

`_legacy_payload/` — снимок старой версии установщика, когда все скиллы и агенты лежали внутри установщика и копировались в `~/.claude/`. После перехода на архитектуру «общая база через git clone» payload не нужен — актуальное содержимое в `claude-base`. Папка остаётся как архив.

## Лицензия

MIT.
