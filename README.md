# Steam Workshop Uploader (fork)

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE.md)

Форк [EliteMasterEric/SteamWorkshopUploader](https://github.com/EliteMasterEric/SteamWorkshopUploader) с доработками под **Godot 4.6**, полную библиотеку Steam и улучшенный интерфейс для оператора.

Репозиторий: **https://github.com/hvkeyn/SteamWorkshopUploader**

## Отличия от upstream

| | Upstream (оригинал) | Этот форк |
|---|---|---|
| Godot | 4.4 | **4.6.2** |
| Список игр | Несколько захардкоженных AppID | **Вся библиотека** аккаунта Steam (~сотни игр) |
| Выбор игры | Выпадающий список | **Поиск + прокручиваемый список** |
| Имена игр | Только из сцены | CSV-база (~165k) + Store API для остальных |
| Выбор папки для загрузки | Только системный диалог | Диалог с **вставкой полного пути** |
| UGC | Создание / редактирование | + **удаление** элементов Workshop |
| Файлы в загрузке | Включить / исключить | + **убрать из списка** (Delete) |
| UI | Фиксированная вёрстка | **Адаптивная** при изменении размера окна |

## Требования

- **Windows** (основная платформа; Steam client должен быть запущен и вы залогинены)
- **Godot 4.6.2** — для запуска из исходников
- Сборки **GodotSteam** и **GodotGIF** в `third_party/` (уже в репозитории, собраны под 4.4; при проблемах может понадобиться пересборка под 4.6)

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
   - создайте или выберите UGC-элемент, загрузите файлы.

При первом запуске скачивается база имён AppID (CSV, кэш в `user://`) — подождите 10–30 секунд.

## Основные возможности

- Загрузка и обновление Workshop-элементов для **любой игры из вашей библиотеки Steam**.
- Редактирование названия, описания (BBCode), видимости, тегов, превью (в т.ч. GIF).
- Загрузка содержимого из папки с исключениями и `.steamignore`.
- **Вставка пути к папке** в диалоге выбора каталога (`E:\Mods\MyMod`, `file:///…`).
- **Удаление** выбранного Workshop-элемента (кнопка *Delete UGC Item*).
- Удаление лишних файлов из списка загрузки (кнопка *Remove from list* / клавиша Delete).

## Скриншоты (оригинальный UI)

![Screenshot](docs/screenshot.png)
![Screenshot](docs/screenshot2.png)
![Screenshot](docs/screenshot3.png)

## Структура проекта (новое / важное)

| Путь | Назначение |
|------|------------|
| `Scripts/steam_library_scanner.gd` | Скан `localconfig.vdf` и манифестов Steam |
| `Scripts/steam_master_app_list.gd` | База имён AppID (CSV + кэш) |
| `Scripts/ui/Main/steam_app_picker.gd` | Список игр с фильтром |
| `Scripts/ui/Edit/folder_picker_dialog.gd` | Диалог папки с полем пути |
| `Scripts/ui/Main/delete_ugc_button.gd` | Удаление UGC |
| `start.ps1` | Запуск Godot или экспортированного `.exe` |

Autoload `AppLogger` (раньше `Logger`) — из‑за конфликта имён в Godot 4.6.

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
