# Steam Workshop Uploader (fork)

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE.md)

Форк [EliteMasterEric/SteamWorkshopUploader](https://github.com/EliteMasterEric/SteamWorkshopUploader) с доработками под **Godot 4.6**, полную библиотеку Steam, надёжную загрузку крупных модов и улучшенный интерфейс для оператора.

Репозиторий: **https://github.com/hvkeyn/SteamWorkshopUploader**

## Отличия от upstream

| | Upstream (оригинал) | Этот форк |
|---|---|---|
| Godot | 4.4 | **4.6.2** |
| Список игр | Несколько захардкоженных AppID | **Вся библиотека** аккаунта Steam (~сотни игр) |
| Выбор игры | Выпадающий список | **Поиск + прокручиваемый список** |
| Имена игр | Только из сцены | CSV-база (~165k) + Store API для остальных |
| Выбор папки для загрузки | Только системный диалог | Диалог с **вставкой полного пути** |
| UGC | Создание / редактирование | + **удаление** (без «воскрешения» из черновиков) |
| Файлы в загрузке | Включить / исключить | + **убрать из списка** (Delete) |
| Загрузка в Workshop | Базовый поток | **Прогресс, лог, staging**, превью, крупные пакеты |
| UI | Фиксированная вёрстка | **Адаптивная** при изменении размера окна |

## Требования

- **Windows** (основная платформа; Steam client должен быть запущен и вы залогинены)
- **Godot 4.6.2** — для запуска из исходников
- Сборки **GodotSteam** и **GodotGIF** в `third_party/` (уже в репозитории; при проблемах может понадобиться пересборка под 4.6)

## Быстрый старт

1. Клонируйте репозиторий и откройте папку проекта.
2. Положите Godot 4.6.2 в:
   ```
   Godot_v4.6.2/Godot_v4.6.2-stable_win64.exe
   ```
   или экспортируйте приложение в `export/windows/Steam Workshop Uploader.exe`.
3. Запустите:

   ```powershell
   .\start.ps1
   ```

4. В главном окне:
   - найдите игру через **поиск** в списке библиотеки;
   - нажмите **Initialize Steam Connection**;
   - дождитесь окончания **Refresh Workshop List**;
   - создайте (**Create UGC Item**) или выберите элемент, укажите папку мода и превью, заполните **Change notes**, нажмите **Submit Changes**.

При первом запуске скачивается база имён AppID (CSV, кэш в `user://`) — подождите 10–30 секунд.

## Основные возможности

### Библиотека и Workshop

- Загрузка и обновление Workshop-элементов для **любой игры из вашей библиотеки Steam**.
- Локальный реестр известных item ID (`user://ugc_known_items.json`) + черновики (`user://ugc_item_drafts.json`).
- **Удаление** выбранного Workshop-элемента: после удаления ID не возвращается в список из черновика/кэша.
- Редактирование названия, описания (BBCode), видимости, тегов.

### Загрузка файлов (в т.ч. крупные моды)

- Папка контента с исключениями и `.steamignore`; копирование выбранных файлов во временную папку перед отправкой.
- **Staging** в `%LOCALAPPDATA%\SteamWorkshopUploader_staging\` — обязателен для путей внутри `steamapps` и помогает при длинных путях Windows.
- **Robocopy** для быстрого зеркалирования больших наборов файлов (сотни MB).
- Нормализация путей для Steam API (обратные слэши, без префикса `\\?\`).
- Проверка длины путей, размера превью, запрета превью внутри папки контента.
- Диалог **Workshop upload** с прогрессом, подробным логом, **Copy log**, **Open in Steam**.

### Превью

- JPG/PNG и **GIF** (через GodotGIF).
- Автоматическое **перекодирование превью** под лимиты Steam (до 1 MB), отдельная staging-папка для превью.

### Интерфейс

- **Вставка пути к папке** в диалоге выбора каталога (`E:\Mods\MyMod`, `file:///…`).
- Удаление лишних файлов из списка загрузки (кнопка *Remove from list* / клавиша Delete).
- Перед Submit обязательны **папка контента** и **Change notes**; без превью — предупреждение в логе.

## Типичный сценарий (пример: TurretGirls)

1. Выберите игру (AppID **3029750**), инициализируйте Steam.
2. **Create UGC Item** → примите соглашение Workshop в оверлее Steam, если попросит.
3. В редакторе:
   - **Browse Files** → папка мода (например `COPY_TO_GAME_FOLDER`);
   - **Preview** → изображение обложки;
   - вкладка **Description** → текст и BBCode;
   - внизу — **Change notes** (обязательно).
4. **Submit Changes** — дождитесь **Upload complete** (для ~350 MB это может занять минуту и больше).
5. **Open in Steam** — проверьте размер файла и превью на странице item.

Если игра ограничивает ISteamUGC (очень большие пакеты), используйте клиент Steam или уменьшите набор файлов.

## Скриншоты (оригинальный UI)

![Screenshot](docs/screenshot.png)
![Screenshot](docs/screenshot2.png)
![Screenshot](docs/screenshot3.png)

## Структура проекта (новое / важное)

| Путь | Назначение |
|------|------------|
| `Scripts/steam_library_scanner.gd` | Скан `localconfig.vdf` и манифестов Steam |
| `Scripts/steam_master_app_list.gd` | База имён AppID (CSV + кэш) |
| `Scripts/ugc_item_registry.gd` | Локальный реестр Workshop item ID + список удалённых |
| `Scripts/ugc_draft_store.gd` | Черновики редактора |
| `Scripts/workshop_upload_paths.gd` | Staging, валидация путей, подготовка контента |
| `Scripts/workshop_preview.gd` | Подготовка превью для Steam |
| `Scripts/temp_folder.gd` | Временные папки, robocopy |
| `Scripts/ui/Edit/workshop_upload_progress_dialog.gd` | Диалог прогресса загрузки |
| `Scripts/ui/Main/steam_app_picker.gd` | Список игр с фильтром |
| `Scripts/ui/Edit/folder_picker_dialog.gd` | Диалог папки с полем пути |
| `Scripts/ui/Main/delete_ugc_button.gd` | Удаление UGC |
| `start.ps1` | Запуск Godot или экспортированного `.exe` |

Autoload `AppLogger` (раньше `Logger`) — из‑за конфликта имён в Godot 4.6.

Runtime-файл `steam_appid.txt` в корне проекта создаётся при инициализации Steam для выбранной игры (в `.gitignore`).

## Сборка и экспорт

Откройте проект в Godot 4.6.2 → **Project → Export** → пресет Windows.

Либо используйте уже экспортированный бинарник в `export/windows/`, если он есть.

## Участие и upstream

Исправления, которые подходят всем, можно предлагать в [upstream](https://github.com/EliteMasterEric/SteamWorkshopUploader).

Этот форк ведётся для личного/рабочего использования; API и поведение Steam по-прежнему зависят от [GodotSteam](https://github.com/GodotSteam/GodotSteam).

## Лицензия

MIT — см. [LICENSE.md](LICENSE.md). Основано на проекте EliteMasterEric.

## Благодарности

- [EliteMasterEric](https://github.com/EliteMasterEric) — оригинальный Steam Workshop Uploader
- [GodotSteam](https://github.com/GodotSteam/GodotSteam)
- [dgibbs64/SteamCMD-AppID-List](https://github.com/dgibbs64/SteamCMD-AppID-List) — база имён приложений
