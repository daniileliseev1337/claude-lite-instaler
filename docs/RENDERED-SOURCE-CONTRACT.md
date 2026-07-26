# Rendered source contract

Foundation устанавливает только target-bound рендер LLM-base. Полный build-репозиторий
нельзя клонировать в нативный home клиента: каталоги `agents/` и `skills/` снова
попадут в discovery и вернут большой стартовый контекст.

Поддерживаются ровно три target: `claude`, `codex`, `opencode`. Kimi не является
отдельным target; при необходимости это лишь модель провайдера внутри OpenCode.

## Сборочный поток

1. Зафиксировать immutable commit или content SHA исходного LLM-base. Даже
   git-identity обязана содержать вычисленный `content_sha256` всего approved
   source tree: одна декларация commit/tree без сверки байтов не принимается.
2. Выполнить его офлайн-рендер для одного target в чистую папку.
3. Сопоставить файлы по
   `contracts/foundation/rendered-target-map.json`.
4. Получить независимые acceptance evidence для каждого payload SHA-256.
5. Только после этого собрать target-bound Foundation package.

Один package содержит один `target`. На одном ПК пакеты Claude, Codex и OpenCode
могут быть установлены рядом: состояние хранится раздельно.

Builder пересчитывает source-tree digest и требует точного совпадения active
set с target map, включая source path, component ID, type и destination.
Runtime повторяет проверку active set по встроенному контракту, поэтому
изменение одного map-файла или release-manifest не расширяет установку.
Quarantine-компоненты могут присутствовать отдельно, но не становятся active.

## Sync и секреты

Манифест schema v2 обязан содержать `direction=hub-to-consumer`,
`default_role=consumer` и четыре `false`: consumer push, feedback upload,
session upload и credentials included. Пакет не управляет auth-store и не
устанавливает модель, провайдера или клиент.

Consumer — роль по умолчанию. `-Role hub` допустим только как явный выбор
разработчика; он не добавляет credentials в пакет. Любой reverse-channel
должен приводить к `INVALID_PACKAGE`.

## Release gate

Синтетический fixture доказывает только движок на fake-home. Пока нет
утверждённого immutable rendered source и frozen evidence inventory для всех
активных компонентов, вердикт остаётся
`BLOCKED_APPROVED_FOUNDATION_SOURCE` / `FULL_RELEASE_NOT_PASS`.
