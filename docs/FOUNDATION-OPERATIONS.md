# Codex Foundation — установка и эксплуатация

## Граница

Пакет работает офлайн, только для текущего пользователя Windows 10/11 и не
устанавливает Codex client. Он не меняет `config.toml`, `hooks.json`,
credentials, cache, MCP или plugins.

## Проверка ZIP до распаковки

Для выпуска `foundation-canary-20260723-0001`:

```powershell
$ReleaseId = 'foundation-canary-20260723-0001'
$Zip = ".\Codex-Foundation-$ReleaseId.zip"
$Expected = (Get-Content "$Zip.sha256" -Raw).Trim().Split(' ')[0]
$Actual = (Get-FileHash $Zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($Actual -cne $Expected) { throw 'Package ZIP hash mismatch' }
```

После совпадения SHA распакуйте архив в отдельную папку. Не запускайте скрипт
изнутри ZIP.

## Пять команд

Откройте PowerShell в распакованной папке:

```powershell
.\install.ps1 plan
.\install.ps1 install
.\install.ps1 doctor
.\install.ps1 inventory
.\install.ps1 rollback
```

Без аргумента выполняется только `plan`, который ничего не записывает.

`install` сначала повторяет plan и просит ввести точную строку
`INSTALL {release-id}`. При conflict установка не начинается.

Безопасный диагностический отчёт:

```powershell
.\install.ps1 doctor -ExportReport .\doctor-safe.json
```

Отчёт содержит только версии, component IDs, counts и error codes. Не
прикладывайте к заявке `config.toml`, credentials или cache.

## Коды завершения

| Код | Значение |
|---:|---|
| 0 | Успех / healthy |
| 2 | Неверная команда или пакет |
| 10 | Conflict либо неподдерживаемая среда |
| 20 | Требуется recovery/rollback |
| 30 | Active drift |
| 40 | Rollback conflict |

Expected quarantine не является ошибкой: hooks, MCP и plugins специально не
активируются в Foundation v1.

## Эскалация

При коде 20 сначала выполните `rollback`. При коде 40 не редактируйте и не
удаляйте изменённый managed-файл: передайте `doctor-safe.json` ответственному за
пакет. Не запускайте PowerShell от администратора и не меняйте execution policy
глобально.

