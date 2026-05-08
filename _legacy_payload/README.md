# _legacy_payload/

**Архив.** Снимок payload-папки старой версии lite-installer, которая
копировала skills и agents напрямую в `~/.claude/`.

## Не используется

С переходом на git-clone-стратегию (Stage 7 в `Apply-ClaudeMd.ps1`)
актуальные skills и agents живут в репо
[`claude-base`](https://github.com/daniileliseev1337/claude-base) и
устанавливаются через `git clone` в `~/.claude/`.

## Зачем хранится

- **Историческая ссылка** — что было до перехода на git-стратегию.
- **Резерв** — если по какой-то причине нужно восстановить установку
  без интернет-доступа к claude-base.
- **Сравнение** — проверить, что в claude-base всё, что было в payload,
  + новые улучшения.

## Структура

```
_legacy_payload/payload/
├── CLAUDE.md                          # старая версия глобального manifest
├── agents/
│   ├── word-checker.md
│   ├── excel-validator.md
│   └── pdf-reviewer.md
└── skills/
    ├── karpathy-guidelines/
    ├── pdf-helper/
    ├── excel-helper/
    └── word-helper/
```

Все эти файлы (плюс новые `designer.md`, `auditor.md`, кейс ПНР) есть
в актуальной версии в `claude-base`.

## Если нужно вернуться к старой схеме

Восстановить `Stage 7: copy payload from `_legacy_payload/payload/` to
`~/.claude/` — но это требует ручной правки `Install.ps1`. Не рекомендуется,
проще починить git-стратегию если возникнут проблемы.
