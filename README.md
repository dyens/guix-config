# guix-config

Декларативная конфигурация GNU Guix: система, домашнее окружение и пин
версии самого Guix. Всё воспроизводится из этих файлов — на новой машине
или в новой VM не остаётся ручных шагов, кроме подстановки UUID дисков.

Живёт на хосте (`~/vms/guix-config`), в VM пробрасывается по 9p в
`/mnt/guix-config`. Правите в привычном редакторе на Fedora — применяете
внутри VM, без коммитов и scp на каждую итерацию.

Ключевые решения:

- **Display manager'а нет.** Графика поднимается из home через `startx`.
- **i3 и всё пользовательское — в `home/`**, система о графике не знает.
- **Подстановки идут через зеркало Яндекса**, `ci.guix.gnu.org` исключён.

---

## Установка с нуля

### 1. Получить репозиторий

```sh
guix install git                     # если git ещё нет
git clone <repo-url> ~/guix-config
cd ~/guix-config
```

### 2. Взять пиннутую версию Guix

`channels.scm` фиксирует точный коммит Guix. Это то, что делает установку
воспроизводимой: тот же конфиг на другом коммите даст другие версии
пакетов.

```sh
guix pull -C channels.scm \
  --substitute-urls='https://mirror.yandex.ru/mirrors/guix https://bordeaux.guix.gnu.org'
hash guix
```

Флаг `--substitute-urls` тут нужен руками: зеркало прописано в конфиге
системы, но конфиг ещё не применён. Это неустранимая проблема курицы
и яйца, дальше флаг не понадобится.

Альтернатива без `guix pull` — выполнять команды через `time-machine`,
он берёт версию прямо из пина и не трогает локальный Guix:

```sh
guix time-machine -C channels.scm -- system reconfigure systems/<host>.scm
```

### 3. Описать машину

Скопируйте заготовку и заполните UUID:

```sh
cp systems/laptop.scm systems/myhost.scm
lsblk -f                             # или blkid
```

Подставить нужно `#:root-device`, `#:swap-device`, UUID ESP и
`#:bootloader-targets`. В заготовке стоят нули — пока их не заменить,
`reconfigure` упадёт на проверке файловых систем. Это намеренно: лучше
громкая ошибка, чем незагружающаяся система.

### 4. Применить

```sh
sudo -i guix system reconfigure ~/guix-config/systems/myhost.scm
guix home reconfigure ~/guix-config/home/dyens.scm
```

### 5. Задать пароли

Паролей в репозитории нет и быть не должно — они живут в `/etc/shadow`,
это состояние машины. На свежей системе аккаунты создаются без паролей,
так что войти вы не сможете, пока не зададите их:

```sh
sudo passwd root
sudo passwd dyens
```

Сразу после `guix system init` на новой машине root ещё без пароля,
поэтому первый вход делается с консоли под ним.

```sh
sudo reboot
```

### 6. Войти

Display manager'а нет. Логинитесь на tty1, затем:

```sh
startx
```

---

## Структура

| Путь | Что описывает | Команда применения |
|---|---|---|
| `channels.scm` | версию самого Guix (пин коммита) | `guix pull -C channels.scm` |
| `systems/base.scm` | общая часть всех машин | — (подключается модулем) |
| `systems/vm.scm` | dev-VM под QEMU | `sudo -i guix system reconfigure` |
| `systems/laptop.scm` | заготовка для физической машины (UEFI) | `sudo -i guix system reconfigure` |
| `home/dyens.scm` | dotfiles, пакеты, i3, startx | `guix home reconfigure` |
| `files/` | сырые dotfiles, подключаемые через `local-file` | — |
| `run-vm.sh` | запуск qemu с ssh + 9p (выполняется на ХОСТЕ) | — |

Три слоя — Guix, система, home — независимы, и без первого остальные два
невоспроизводимы.

### Как устроен `systems/`

`base.scm` — модуль с процедурой `make-system`, где собрано всё общее:
пользователь, локаль, раскладка, зеркало подстановок, набор сервисов.
Файлы машин передают в неё только машинно-зависимое:

```scheme
(add-to-load-path (dirname (current-filename)))
(use-modules (gnu) (base))

(make-system
 #:host-name "dyens"
 #:root-device (uuid "981499e3-..." 'ext4)
 #:bootloader-targets (list "/dev/vda"))
```

Новая машина — файл на полтора десятка строк. Общие изменения правятся
в `base.scm` и разъезжаются по всем машинам сразу.

Если `add-to-load-path` не сработает (Guile не смог определить путь
исходника), укажите каталог модуля флагом:

```sh
sudo -i guix system reconfigure -L ~/guix-config/systems ~/guix-config/systems/vm.scm
```

---

## Ежедневный цикл: VM на этом хосте

```sh
./run-vm.sh            # с графикой
./run-vm.sh headless   # в фоне, без окна
./run-vm.sh ssh        # зайти внутрь
./run-vm.sh stop       # погасить фоновую
```

Переопределяется через env: `GUIX_VM_MEM`, `GUIX_VM_CPUS`,
`GUIX_VM_SSH_PORT`, `GUIX_VM_DISK`, `GUIX_VM_USER`.

Скрипт передаёт `-virtfs local,path=<repo>,mount_tag=guixcfg,security_model=none`,
а `systems/vm.scm` монтирует этот тег в `/mnt/guix-config` при загрузке.
`security_model=none` означает, что uid в госте совпадают с хостовыми,
поэтому из VM в каталог можно и писать.

Внутри VM (алиасы прописаны в `home/dyens.scm`):

```sh
sysrec      # sudo -i guix system reconfigure /mnt/guix-config/systems/vm.scm
homerec     # guix home reconfigure /mnt/guix-config/home/dyens.scm
```

### Обновить пин

После удачного `guix pull`, пока состояние рабочее:

```sh
guix describe -f channels > /mnt/guix-config/channels.scm
git -C ~/vms/guix-config commit -am "pin guix $(date +%F)"
```

Файл сразу появится в репозитории на хосте — 9p работает в обе стороны.
Этот коммит — ваша точка отката.

---

## Перенос на другую машину

Переносится не «система», а текстовые файлы плюс пин.

| Файл | Портируемость |
|---|---|
| `channels.scm` | полностью — это и есть гарантия одинаковости |
| `home/dyens.scm`, `files/` | полностью, включая чужой дистрибутив |
| `systems/base.scm` | полностью |
| `systems/<host>.scm` | свой на каждую машину: UUID, загрузчик, hostname |
| `run-vm.sh` | только для VM-хостов |

### Что не переносится: состояние

Репозиторий описывает, **какой должна быть машина**, а не её накопленное
состояние. Guix System декларативна, но не stateless. Вне конфига живёт:

| Состояние | Где | Что делать на новой машине |
|---|---|---|
| Пароли пользователей | `/etc/shadow` | `passwd` руками (шаг 5 установки) |
| Хост-ключи ssh | `/etc/ssh/ssh_host_*` | ничего, генерируются при первой загрузке |
| Приватные ssh-ключи | `~/.ssh/id_*` | перенести отдельно, **не** через `local-file` |
| Домашние каталоги | `/home` | бэкап/rsync отдельно |
| Данные сервисов | `/var/lib/*` | бэкап отдельно |
| `machine-id` | `/etc/machine-id` | ничего, и не надо |
| Поколения системы | `/var/guix/profiles` | история локальна, не переносится |

Про пароли подробнее: `guix system reconfigure` и `guix system roll-back`
существующие пароли **не сбрасывают** — активация создаёт недостающие
аккаунты, но не трогает уже проставленные записи в `/etc/shadow`.
Поэтому на работающей машине пароль переживает любые пересборки,
а на новой его просто нет.

Задать пароль декларативно технически можно:

```scheme
(password (crypt "ВременныйПароль" "$6$случайнаясоль"))
```

но хеш при этом попадает в `/gnu/store`, который **читается всеми
пользователями машины**. Для одноразового пароля «войти и сразу сменить»
это приемлемо, для постоянного — нет. См. раздел про секреты ниже.

### Секреты

Правило одно: **всё в `/gnu/store` читается любым пользователем системы**
(`ls -ld /gnu/store`, права `444`/`555`). Значит `local-file`, `plain-file`
и `mixed-text-file` — это публикация, а не хранение.

Что можно класть в репозиторий открыто:

- публичные ключи (`*.pub`) для `authorized-keys` — это не секреты;
- секреты, **зашифрованные** через `age` / `sops` / `git-crypt`.

#### Вход по ssh-ключу

Публичные ключи лежат в `files/keys/` и подключаются параметром
`make-system`:

```scheme
 #:ssh-authorized-keys `(("dyens" ,(local-file "../files/keys/dyens.pub")))
 #:ssh-password-auth? #f
```

Порядок важен: сначала добавить ключ и **проверить**, что вход работает,
и только следующим reconfigure выключать пароль. Наоборот — потеря
доступа по ssh. Подробности в `files/keys/README.md`.

Чего делать нельзя:

- приватные ключи, пароли, токены через `local-file`;
- секреты в `files/bashrc` — он тоже уезжает в стор. Для переменных
  окружения с секретами держите неуправляемый `~/.bashrc.local`
  и подключайте его из `files/bashrc`.

Приватные ключи проще всего не отдавать Guix Home вовсе: `~/.ssh/id_ed25519`
с правами 600 живёт сам по себе, Guix Home спокойно уживается
с неуправляемыми файлами в `~`. Если хочется хранить их в репозитории —
шифруйте, а расшифровывайте обычным скриптом мимо Guix:

```sh
age -d -i ~/.age-key files/secrets/id_ed25519.age > ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519
```

Один секрет (сам `~/.age-key`) всё равно придётся передать руками —
это граница схемы, а не её недостаток.

### На чужом дистрибутиве (Fedora, Ubuntu)

Работает **только** home-часть, и работает хорошо: тот же набор пакетов,
тот же bashrc, те же алиасы поверх чужой системы.

```sh
guix pull -C channels.scm
guix home reconfigure home/dyens.scm
```

`systems/` там неприменим — системой управляет дистрибутив. Сервис
`home-startx-command-service-type` на такой машине стоит отключить:
`startx` там свой.

### Готовый образ VM

Собирает qcow2 прямо из конфига, минуя установщик:

```sh
guix system image -t qcow2 --image-size=20G systems/vm.scm
```

На выходе путь в `/gnu/store`. Копируете на хост — и каждая новая VM это
`cp` образа плюс запуск. Для образов корень принято описывать меткой
(`(device (file-system-label "guix-root"))`), а не UUID: UUID текущей VM
в новом образе не совпадёт.

### `guix deploy`

Накат конфига на работающие машины по SSH, без захода на каждую.
Пригодится, когда их станет больше одной.

---

## Графика: startx, без display manager

GDM — тяжёлый GNOME-компонент, который тянет полстека ради экрана входа
в i3, и он ломался на отсутствующей GSettings-схеме `org.gnome.system.locale`.
Вместо него `home-startx-command-service-type` кладёт `startx`
в **домашний** профиль.

| Слой | Что знает про графику |
|---|---|
| `systems/base.scm` | ничего: ни WM, ни DM. Только раскладка для консоли и GRUB |
| `home/dyens.scm` | i3, шрифты, терминал, раскладка внутри X, сам `startx` |

Порядок: логин на tty1 → `startx` → i3.

`set-xorg-configuration` в системе использовать НЕЛЬЗЯ вместе со startx:
конфигурация Xorg задаётся в `home-startx-command-service-type`, иначе
получаются две конкурирующие настройки.

### Конфиг i3

Сервис `home-xdg-configuration-files-service-type` в `home/dyens.scm`
намеренно закомментирован. Под управлением Guix Home файл
`~/.config/i3/config` становится read-only симлинком в стор, и мастер
первого запуска i3 не сможет его создать. Порядок:

1. Первый `startx` — i3 предложит сгенерировать конфиг, согласитесь.
2. `cp ~/.config/i3/config files/i3/config`
3. Раскомментируйте сервис, `guix home reconfigure`.

---

## Грабли

- **`guix-daemon` не перезапускается сам** после reconfigure. Смена
  `substitute-urls` доедет только после `sudo herd restart guix-daemon`
  или перезагрузки.
- **`ps` не показывает guix-daemon** — он поднимается по обращению
  к сокету (socket activation). Это норма, смотрите `sudo herd status guix-daemon`.
- **`sudo guix` ≠ `sudo -i guix`.** Без `-i` берётся guix из PATH
  пользователя, а не обновлённый root'овский, и reconfigure падает
  с «is not a descendant of».
- **Shepherd банит сервис** после нескольких падений подряд
  (`It is disabled`). Перед `herd start` нужен `herd enable`.
- **Сервис GDM в shepherd называется `xorg-server`**, не `gdm`.
  Актуально, если вернёте display manager.
- **Файловая система без `mount-may-fail? #t`** роняет цель
  `file-systems`, а с ней весь пользовательский стек. Для необязательных
  монтирований флаг обязателен.
- **Раскладка по слоям**: X — после перелогина, консоль — после reboot,
  GRUB — со следующего поколения.
- **Dotfiles read-only** после `guix home reconfigure` — правьте `files/`.
