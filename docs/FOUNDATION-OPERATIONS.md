# LLM Base Foundation — установка и эксплуатация

## Граница

Пакет работает офлайн, только для текущего пользователя Windows 10/11.
Он не устанавливает и не авторизует Claude, Codex или OpenCode, не выбирает
провайдера/модель и не читает auth-store.

Каждый ZIP привязан ровно к одному target: `claude`, `codex` или `opencode`.
Несколько target можно установить рядом. Consumer — роль по умолчанию.

## Проверка ZIP до распаковки

```powershell
$Zip = '.\LLM-Base-Foundation-<release>-<target>.zip'
$Expected = (Get-Content "$Zip.sha256" -Raw).Trim().Split(' ')[0]
$Actual = (Get-FileHash $Zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($Actual -cne $Expected) { throw 'Package ZIP hash mismatch' }
```

После совпадения SHA распакуйте архив в отдельную папку. Не запускайте скрипт
изнутри ZIP.

## Пять команд

```powershell
.\install.ps1 plan
.\install.ps1 install
.\install.ps1 doctor
.\install.ps1 inventory
.\install.ps1 rollback
```

Target берётся из проверенного по SHA-256 frozen release-manifest. Для видимой проверки можно
добавить `-Target claude|codex|opencode`; несовпадение с пакетом блокирует plan.

Consumer не требует флага:

```powershell
.\install.ps1 plan -Target opencode
.\install.ps1 install -Target opencode
```

Только на ПК разработчика роль hub задаётся явно:

```powershell
.\install.ps1 install -Target opencode -Role hub
```

`install` требует точную строку:

```text
INSTALL <release-id> <target> <consumer|hub>
```

Любое другое значение отменяет операцию до открытия транзакции.

Безопасный диагностический отчёт:

```powershell
.\install.ps1 doctor -Target opencode -ExportReport .\doctor-safe.json
```

Отчёт содержит target, роль, версии, component IDs, counts и error codes.
Не прикладывайте credentials, auth-файлы, environment или cache.

## Односторонняя политика

Release-manifest schema v2 принимается только при:

- `direction = hub-to-consumer`;
- `default_role = consumer`;
- `consumer_push = false`;
- `consumer_feedback_upload = false`;
- `consumer_session_upload = false`;
- `credentials_included = false`.

Foundation не добавляет write-token даже для hub. Публикация изменений хаба —
отдельный исходный workflow, не функция employee package.

## Коды завершения

| Код | Значение |
|---:|---|
| 0 | Успех / healthy |
| 2 | Неверная команда, target или пакет |
| 10 | Conflict либо неподдерживаемая среда/client version |
| 20 | Требуется recovery/rollback |
| 30 | Active drift |
| 40 | Rollback conflict |

Expected quarantine не является ошибкой: недоказанный компонент не активируется.

Install и rollback используют write-ahead journal. После прерывания повторите
`rollback` для того же target: движок сверит фактический hash каждого файла,
продолжит только незавершённые операции и удалит собственные staging-файлы.
Не удаляйте `transaction-journal.json` вручную.

## Эскалация

При коде 20 выполните rollback для того же target. При коде 40 не редактируйте
managed-файл повторно: передайте `doctor-safe.json` ответственному за пакет.
Не запускайте PowerShell от администратора и не меняйте execution policy
глобально.
