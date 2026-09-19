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
git clone git@github.com:dyens/guix-config.git ~/guix-config
cd ~/guix-config
```

Секреты лежат в этом же репозитории зашифрованными (`files/secrets/`).
Чтобы они расшифровались, машине нужен ключ: либо скопируйте `~/.age-key`
с уже работающей машины, либо добавьте публичный ssh-ключ этой машины
в `.sops.yaml` и выполните `sops updatekeys` — см. раздел «Секреты».
Без ключа установка проходит нормально, просто без секретов.

### 2. Взять пиннутую версию Guix

`channels.scm` фиксирует точный коммит Guix и канала `sops-guix`. Это то, что делает установку
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
guix home reconfigure ~/guix-config/home/dyens.scm         # с графикой
# или
guix home reconfigure ~/guix-config/home/programming.scm   # без графики
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
| `channels.scm` | версию Guix и канала sops-guix (пины коммитов) | `guix pull -C channels.scm` |
| `systems/base.scm` | общая часть всех машин | — (подключается модулем) |
| `systems/vm.scm` | dev-VM под QEMU | `sudo -i guix system reconfigure` |
| `systems/laptop.scm` | заготовка для физической машины (UEFI) | `sudo -i guix system reconfigure` |
| `systems/t1.scm` | облачная VM: минимальный сервер, из него собирается образ | `guix system image`, см. «Облачная VM» |
| `home/base.scm` | общая часть home: vim, git, tmux, Claude Code, bash, секреты | — (подключается модулем) |
| `home/programming.scm` | home для программирования без графики (облачные VM) | `guix home reconfigure` |
| `home/dyens.scm` | home с графикой: base + i3, шрифты, startx | `guix home reconfigure` |
| `home/emacs.scm` | Emacs: пакеты из Guix + конфиг `files/emacs` (входит в base) | — (подключается модулем) |
| `home/emacs-manifest.scm` | тот же Emacs без guix home — попробовать на любой машине | `guix shell -m` |
| `files/emacs/` | конфиг Emacs → `~/.config/emacs` | — |
| `packages/claude-code.scm` | проприетарный бинарник, переупакованный под Guix | — (подключается модулем) |
| `packages/xray.scm` | Xray-core, статический бинарник релиза | — (подключается модулем) |
| `packages/docker.scm` | Docker Engine 29, compose, buildx — статические бинарники | — (подключается модулем) |
| `systems/docker.scm` | сервис dockerd + группа docker | — (подключается в `systems/<host>.scm`) |
| `home/docker.scm` | плагины `docker compose`/`buildx` в `~/.docker/cli-plugins` (входит в base) | — |
| `systems/wg-quick.scm` | WireGuard: конфиг wg-quick из sops + сервис + `/etc/hosts` | — (подключается в `systems/<host>.scm`) |
| `files/secrets/wg-ruclaw.yaml` | конфиг wg-quick проектной сети ruclaw (с ключом), зашифрован sops | см. «WireGuard» |
| `home/xray.scm` | VPN-клиент: Xray в home-shepherd, SOCKS 127.0.0.1:10808 (входит в base) | — (подключается модулем) |
| `systems/xray-tun.scm` | tun `xray0` + маршруты на выбранные адреса через этот SOCKS | — (подключается в `systems/<host>.scm`) |
| `files/secrets/xray.yaml` | конфиг Xray-клиента (ключи, сервер), зашифрован sops | см. «VPN» |
| `files/` | сырые dotfiles, подключаемые через `local-file` | — |
| `files/secrets/*.yaml` | секреты, зашифрованные sops | `sops files/secrets/home.yaml` |
| `.sops.yaml` | получатели: кто может расшифровать | `sops updatekeys` |
| `run-vm.sh` | запуск qemu с ssh + 9p (выполняется на ХОСТЕ) | — |

Три слоя — Guix, система, home — независимы, и без первого остальные два
невоспроизводимы.

### Модули

Файлы верхнего уровня (`systems/vm.scm`, `home/dyens.scm`) — точки входа,
всё остальное подключается модулями. Путь загрузки — корень репозитория,
имена модулей повторяют структуру каталогов:

```scheme
(add-to-load-path (dirname (dirname (current-filename))))
(use-modules (systems base) (packages claude-code))
```

Иерархические имена, а не короткие `(base)`/`(claude-code)`, — чтобы
не столкнуться с модулями самого Guix.

Если `add-to-load-path` не сработает (Guile не смог определить путь
исходника), укажите корень репозитория флагом:

```sh
sudo -i guix system reconfigure -L ~/guix-config ~/guix-config/systems/vm.scm
```

### Как устроен `systems/`

`base.scm` — модуль с процедурой `make-system`, где собрано всё общее:
пользователь, локаль, раскладка, зеркало подстановок, набор сервисов.
Файлы машин передают в неё только машинно-зависимое:

```scheme
(make-system
 #:host-name "dyens"
 #:root-device (uuid "981499e3-..." 'ext4)
 #:bootloader-targets (list "/dev/vda"))
```

Новая машина — файл на полтора десятка строк. Общие изменения правятся
в `base.scm` и разъезжаются по всем машинам сразу.

### Как устроен `home/`

Так же: `home/base.scm` — модуль `(home base)` с процедурой `make-home`,
в нём всё для программирования (пакеты, bash, tmux, секреты). Точки входа
передают машинно-зависимое и добавки:

```scheme
;; home/programming.scm — облачная VM, без графики
(make-home
 #:repo "~/guix-config"                     ; -> $GUIX_CONFIG
 #:sysrec "sudo guix system reconfigure ~/guix-config/systems/$(hostname).scm"
 #:homerec "guix home reconfigure ~/guix-config/home/programming.scm")

;; home/dyens.scm — локальная VM: то же + графика
(make-home
 #:repo "/mnt/guix-config"
 ...
 #:extra-packages (… "i3-wm" "st" …)
 #:extra-services (list … startx, .xinitrc, конфиг i3 …))
```

Инструмент для программирования — в `%programming-packages` в
`home/base.scm`, приедет на все машины. Графическое — в `home/dyens.scm`.

### Обновить Claude Code

Claude Code — проприетарный бинарник, собранный под FHS: он ищет
загрузчик по `/lib64/ld-linux-x86-64.so.2`, которого в Guix нет.
`packages/claude-code.scm` скачивает его, правит `patchelf`'ом путь
к загрузчику на glibc из стора и кладёт в профиль. Ни симлинков
в системе, ни FHS-контейнера не нужно.

Обратная сторона: стор неизменяемый, поэтому обновлять себя Claude Code
не может. Поэтому в `files/bashrc` выставлен `DISABLE_UPDATES=1`,
а версия бампается вручную:

```sh
# 1. узнать версию и контрольную сумму из подписанного манифеста
V=2.1.300
curl -fsSL https://downloads.claude.ai/claude-code-releases/$V/manifest.json \
  | grep -A3 '"linux-x64"'

# 2. перевести sha256 из hex в формат Guix
guix hash --hash=sha256 --format=nix-base32 <файл>
```

Проще всего не считать вручную: поставьте в `packages/claude-code.scm`
новую `version` и любой невалидный хеш, запустите `guix home build` —
Guix скачает файл и напечатает ожидаемый хеш в тексте ошибки. Впишите
его и повторите.

Версия пиннится хешем, поэтому `guix time-machine` возвращает именно ту
версию Claude Code, что была на момент коммита, — в отличие от обычной
установки, которая обновляет себя в фоне.

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
sops        # SOPS_AGE_KEY_FILE=~/.age-key sops — см. «Секреты»
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
| `home/*.scm`, `files/` | полностью, включая чужой дистрибутив |
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
и `mixed-text-file` — это публикация, а не хранение. Секреты в конфигурацию
не встраиваются никогда.

Схема из трёх частей:

| Что | Где лежит | Как попадает на машину |
|---|---|---|
| Публичные ssh-ключи | `files/keys/*.pub` | `local-file`, открыто |
| Токены, конфиги доступа | `files/secrets/*.yaml`, зашифровано sops | расшифровка в tmpfs при старте home-shepherd |
| Приватные ssh-ключи | нигде | генерируются на месте, не переносятся |

#### Приватные ssh-ключи: не переносить

Самый простой способ управлять секретом — не иметь его. Пара генерируется
**на каждой машине отдельно**, приватная половина её не покидает,
в репозиторий едет только публичная:

```sh
ssh-keygen -t ed25519 -C "dyens@$(hostname)"
cat ~/.ssh/id_ed25519.pub > files/keys/dyens-$(hostname).pub
```

Компрометация одной машины не тянет за собой остальные, а отзыв —
это удаление одного файла и `reconfigure`.

#### Вход по ssh-ключу

`#:ssh-authorized-keys` принимает список, по одному ключу на машину:

```scheme
 #:ssh-authorized-keys `(("dyens" ,(local-file "../files/keys/dyens-vm.pub"))
                         ("dyens" ,(local-file "../files/keys/dyens-laptop.pub")))
 #:ssh-password-auth? #f
```

Порядок важен: сначала добавить ключ и **проверить**, что вход работает,
и только следующим reconfigure выключать пароль. Наоборот — потеря
доступа по ssh.

#### Токены и прочее: sops-guix

Секреты лежат в этом же репозитории, в `files/secrets/*.yaml`,
зашифрованные [sops](https://getsops.io) на age-ключи. Расшифровывает их
`home-sops-secrets-service-type` из канала
[sops-guix](https://github.com/fishinthecalculator/sops-guix)
(пин — в `channels.scm`).

Как это работает:

1. `home.yaml` подключается через `local-file` и уезжает в стор —
   **только шифротекст**, так что это не хуже публичного репозитория;
2. при старте home-shepherd (первый логин после загрузки) на каждый
   `sops-secret` запускается одноразовый сервис: `sops -d --extract`
   пишет значение в tmpfs `/run/user/$UID/secrets/<ключ>` с правами 400;
3. оттуда его и читают: `files/bashrc` — `bashrc.local`, Xray —
   `xray.json`. Поле `path` (симлинк из домашнего каталога) не
   используется — см. «Нюансы».

Открытый текст на диск не пишется. Версия секретов едет вместе
с коммитом конфига: `guix home roll-back` и `time-machine` берут ровно те
секреты, что были в этом поколении.

Ключ ищется в `~/.age-key` (задано в `home/base.scm`), затем в
`~/.ssh/id_ed25519` — если публичный ssh-ключ машины внесён в `.sops.yaml`.
Нет ключа — сервис секрета падает с сообщением в логе home-shepherd,
остальное окружение работает.

Целый файл хранится как многострочное значение под своим ключом yaml,
а не как `--input-type binary`: имя файла в `/run/user/$UID/secrets`
берётся из ключа, и у всех binary-секретов оно было бы одинаковым — `data`.

Команды выполняются из корня репозитория (`/mnt/guix-config` в VM).
В окружении Guix Home алиас `sops` уже есть (`home/base.scm`): он
подставляет `SOPS_AGE_KEY_FILE=~/.age-key`, а сам `sops` кладёт в профиль
сервис секретов. На хосте без Guix Home заведите такой же руками:

```sh
alias sops='SOPS_AGE_KEY_FILE=~/.age-key guix shell sops -- sops'

# посмотреть или отредактировать: открывает расшифрованным в $EDITOR,
# при сохранении шифрует обратно
sops files/secrets/home.yaml

# добавить машину: вписать её age- или ssh-ed25519-ключ в .sops.yaml, затем
sops updatekeys files/secrets/home.yaml

# новый ключ-файл
guix shell age -- age-keygen -o ~/.age-key
```

Новый секрет — ключ в `home.yaml` плюс строка в `home/base.scm`:

```scheme
(list (home-secret "bashrc.local")
      (home-secret "ssh-config"))   ; → $XDG_RUNTIME_DIR/secrets/ssh-config
```

Первый раз на новой VM:

```sh
# на хосте: ключ в VM (приватная половина, только по ssh)
scp -P 10022 -o UserKnownHostsFile=~/vms/.known_hosts.guixvm \
    ~/.age-key dyens@127.0.0.1:~/.age-key
./run-vm.sh ssh chmod 600 ~/.age-key

# в VM: без канала sops-guix reconfigure не найдёт модуль (sops secrets)
guix pull -C /mnt/guix-config/channels.scm && hash guix
homerec

# проверка
herd status home-sops-secrets
ls -l /run/user/$(id -u)/secrets/
```

Ключ — до `homerec`. Если сервис секрета всё же упал (ключ скопирован
позже, сменили значение, а файл старый), перезапустите его:
`herd restart home-sops-secret-<ключ>`, например
`herd restart home-sops-secret-bashrc.local`. Переменные из
`bashrc.local` видны в новом шелле.

Нюансы:

- **Секреты появляются при логине, а не при `reconfigure`.** После
  перезагрузки tmpfs пуст, пока home-shepherd не стартует. Самый первый
  шелл может успеть раньше расшифровки — поэтому `files/bashrc` проверяет
  `-r` и молча пропускает висячий симлинк.
- **Поле `path` у `sops-secret` не используем.** sops-guix создаёт
  симлинк только при первом старте: при повторном (любой `homerec`,
  перезапуск home-shepherd) он пересоздаёт секрет, а старую ссылку не
  убирает и падает с `symlink: File exists`, а если нет родительского
  каталога — с `No such file or directory`. Упавший секрет валит общий
  `home-sops-secrets`, а с ним всё, что от него зависит (Xray). Поэтому
  секреты читаются прямо из `$XDG_RUNTIME_DIR/secrets/<ключ>`. Оставшийся
  от старой схемы `~/.bashrc.local`-симлинк можно удалить.
- **Имена ключей yaml видны открытым текстом**, зашифрованы только значения.
  Называйте ключи так, чтобы это не было проблемой в публичном репозитории.

#### Чего делать нельзя

- приватные ключи, пароли, токены через `local-file`;
- секреты в `files/bashrc` — он тоже уезжает в стор. Для переменных
  окружения — секрет `bashrc.local` в `files/secrets/home.yaml`: его
  подключает последний блок `files/bashrc` (на чужом дистрибутиве —
  обычный файл `~/.bashrc.local`).

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

## Облачная VM (t1)

Guix System на облачной VM (OpenStack) ставится **своим образом**:
собираем qcow2 из `systems/t1.scm` на хосте, загружаем в панель облака,
создаём из него VM. Установщик, ISO и конвертация чужой ОС не нужны.

`systems/t1.scm` — намеренно минимальная система: сеть по DHCP, sshd
только по ключу, sudo без пароля, `git`. Её задача — загрузиться и
пустить по ssh. Всё остальное (пин Guix, home, секреты) доставляется
уже на машине из этого репозитория.

Железо облака: загрузка **BIOS** (не UEFI), диск **virtio-blk**
(`/dev/vda`), сеть virtio-net с DHCP. cloud-init'а в Guix нет, поэтому
всё, что Ubuntu берёт из метаданных облака, у нас зашито в конфиг:
ssh-ключ (`files/keys/dyens-t1-cloud.pub`, публичная половина
`~/.ssh/t1-cloud`), имя хоста и т. д.

### 1. Собрать образ (на хосте)

```sh
guix system image -t qcow2 --image-size=9G \
  --substitute-urls='https://mirror.yandex.ru/mirrors/guix https://bordeaux.guix.gnu.org' \
  systems/t1.scm
```

Около 10 минут на холодную, дальше — секунды. На выходе путь
`/gnu/store/…-image.qcow2` (~880 МБ, внутри система на 2.2 ГБ).

`--image-size` — это размер **виртуального диска** в образе, корневой
раздел растягивается на него целиком. На содержимое не влияет: лишнее —
просто пустое место в ext4. Правило одно: **образ не больше диска VM**,
иначе облако его не примет. Guix добавляет к этому размеру свои
служебные разделы, так что `--image-size=10G` даёт образ на 10.04 GiB,
который не влезает в диск на 10 GiB. 9G влезает во что угодно.

### 2. Перепаковать в совместимый qcow2

```sh
qemu-img convert -c -O qcow2 -o compat=0.10 \
  /gnu/store/…-image.qcow2 ~/vms/t1-guix-v2.qcow2
qemu-img info ~/vms/t1-guix-v2.qcow2     # compat: 0.10, compression type: zlib
```

Guix пишет qcow2 версии 1.1 **со сжатием zstd**. Облако на таком падает
с «ошибкой чтения образа» без подробностей. `compat=0.10` — самый старый
формат qcow2, его читают все; `-c` сжимает zlib'ом (~930 МБ). Если
облако не примет и его — то же без `-c` (~2.4 ГБ).

### 3. Проверить локально (по желанию)

Перед загрузкой в облако образ можно поднять в QEMU. Overlay не трогает
исходник, диск задаётся больше образа — как будет в облаке:

```sh
qemu-img create -f qcow2 -b ~/vms/t1-guix-v2.qcow2 -F qcow2 /tmp/t1-test.qcow2 20G
qemu-system-x86_64 -enable-kvm -cpu host -m 2048 -smp 2 \
  -drive file=/tmp/t1-test.qcow2,if=virtio \
  -nic user,model=virtio-net-pci,hostfwd=tcp::10023-:22 \
  -display none -serial file:/tmp/t1-serial.log -daemonize
ssh -i ~/.ssh/t1-cloud -p 10023 dyens@127.0.0.1
```

QEMU по умолчанию грузится через SeaBIOS — это и есть BIOS, как в облаке.

### 4. Загрузить в облако и создать VM

В панели: образ `t1-guix-v2.qcow2`, формат **qcow2**, загрузка BIOS.
Диск VM — сколько нужно (у t1 — 100 ГБ); `/gnu/store` растёт с каждым
`guix pull` и `reconfigure`, 10 ГБ для Guix мало. ssh-ключ в панели ни на
что не влияет — cloud-init'а нет, ключ уже в образе.

Вход:

```sh
ssh -i ~/.ssh/t1-cloud dyens@<ip>
```

После пересоздания VM на том же IP ssh ругнётся на сменившийся ключ
хоста — это ожидаемо: `ssh-keygen -R <ip>`.

**Сразу задайте пароль** — иначе консоль в панели облака не пустит (в
`t1.scm` паролей нет, sudo без пароля, ssh только по ключу), и если ssh
сломается, доступа не будет вовсе:

```sh
sudo passwd dyens
```

**Правило для `sysrec`**: перед применением держите открытой вторую
ssh-сессию (лучше в tmux), а после — проверьте **новый** вход из третьего
терминала. Закрывать старые сессии — только если новый вход работает.
Уже установленные сессии переживают почти любую поломку (см. «Грабли»:
WireGuard).

### 5. Растянуть корень на весь диск

Корень после загрузки — те же 9 ГБ, что в образе, остальное место на
диске не размечено. На Ubuntu это молча делает cloud-init (`growpart`),
здесь — руками, один раз. ext4 растягивается на смонтированном корне,
перезагрузка не нужна:

```sh
lsblk                                         # диск vda, корень vda2
sudo guix shell parted e2fsprogs -- parted /dev/vda resizepart 2 100%
#   «Partition /dev/vda2 is being used. Are you sure?» -> Yes
sudo guix shell e2fsprogs -- resize2fs /dev/vda2
df -h /
```

### 6. Репозиторий и пин Guix (на VM)

Клонировать по https: ключа от GitHub на VM нет, а на чтение он не нужен.

```sh
git clone https://github.com/dyens/guix-config.git ~/guix-config
cd ~/guix-config
guix pull -C channels.scm \
  --substitute-urls='https://mirror.yandex.ru/mirrors/guix https://bordeaux.guix.gnu.org'
hash guix
guix describe
```

`--substitute-urls` — откуда брать **собранные бинарники**. Исходники
самого Guix `guix pull` берёт из **git** по `url` канала в `channels.scm`
(`git.guix.gnu.org`), зеркала на это не влияют. Первый раз клонируется
вся история Guix — долго; дальше она кэшируется в `~/.cache/guix/checkouts`.
Если `git.guix.gnu.org` тормозит, в `channels.scm` можно поставить
`https://codeberg.org/guix/guix.git`: коммит и `introduction` проверяются
подписями, так что источник не важен.

После **первого** `guix pull` перелогиньтесь (или выполните
`. ~/.config/guix/current/etc/profile`): `/etc/profile` добавляет
`~/.config/guix/current/bin` в `PATH`, только если каталог был на момент
входа, а до первого pull его нет. Без этого `hash guix` не поможет —
`guix describe` покажет системный Guix из образа, а не пиннутый.
Правильный результат: `guix 002b1a1` и `sops-guix c53e27e`.

Долго тянется фаза **`indexing objects`** — это уже не сеть: libgit2
в один поток индексирует всю историю Guix (10–20 минут, `guile` на 100 %
одного ядра). Не прерывать — начнётся заново. Это разовая плата, следующие
`guix pull` докачивают только новые коммиты.

Одно ядро — ограничение libgit2 (Guix клонирует через него, а не через
`git`, чтобы проверять подписи коммитов), флага для потоков нет. Ускорить
первый pull на новой машине можно, скопировав кэш с машины, где он уже
есть, **с тем же `url` канала** (кэш привязан к URL):

```sh
rsync -a <машина>:.cache/guix/checkouts/ ~/.cache/guix/checkouts/
```

Предупреждение `channel 'sops-guix' is not trusted` — норма.

Если pull упал с `cannot locate remote-tracking branch 'origin/keyring'`
(перед этим в логе `SWH: found revision …`) — в кэше осталась битая копия
канала, см. «Грабли». Удалить её и повторить pull:

```sh
for d in ~/.cache/guix/checkouts/*/; do echo "$d -> $(git -C "$d" remote get-url origin)"; done
rm -rf ~/.cache/guix/checkouts/<каталог sops-guix>
```

### 7. Применить систему пиннутым Guix (на VM)

Образ собран Guix'ом хоста; `reconfigure` переводит систему на пин:

```sh
sudo guix system reconfigure ~/guix-config/systems/t1.scm
```

Именно `sudo guix`, **без `-i`**: `guix pull` делал пользователь, а не root,
и `sudo -i guix` взял бы старый системный Guix из профиля root.

В выводе должно быть `bootloader successfully installed on '(/dev/vda)'`.
Предупреждение про устаревший `%base-initrd-modules` — ожидаемое,
см. комментарий в `t1.scm`. Строка `system loaded for fast reboot with
'reboot --kexec'` — это возможность перезагрузиться, минуя BIOS и GRUB;
для проверки загрузчика нужен обычный `reboot`.

Проверка:

```sh
sudo reboot
ssh t1
guix system describe          # текущее поколение — новое
```

### 8. Home (на VM)

Для программирования без графики — `home/programming.scm` (vim, git,
tmux, Claude Code и прочее из `home/base.scm`, без i3 и шрифтов):

```sh
guix home reconfigure ~/guix-config/home/programming.scm
```

Нужен elogind в системе (в `t1.scm` он есть): он создаёт при входе
`/run/user/$UID`, без которого не стартует home-shepherd, а с ним и
секреты. Симптом, если его нет, — в самом конце reconfigure:
`guix home: error: mkdir: Permission denied: "/run/user"`. Лечится
`sudo guix system reconfigure …/t1.scm`, `sudo reboot` (чтобы PAM создал
сессию уже через elogind) и повторным `guix home reconfigure`.

Проверка после входа: `echo $XDG_RUNTIME_DIR` → `/run/user/1000`,
`herd status` (без sudo) показывает домашние сервисы:

```
Started:
 + root
One-shot:
 * home-sops-secret-bashrc.local
 * home-sops-secrets
```

`One-shot` здесь не значит «расшифровалось»: без age-ключа на машине
сервис отработает вхолостую, `/run/user/1000/secrets/bashrc.local` не
появится. Ключ —
см. «Секреты».

Если reconfigure добавил в home новые переменные окружения (так было
с Emacs: `EMACSLOADPATH`), они появятся только после нового входа —
выйти из tmux (`tmux kill-server`) и из ssh, зайти заново.

Дальше пересобирать алиасами: `homerec` — home, `sysrec` — систему
(`systems/$(hostname).scm`, то есть `t1.scm`).

Claude Code в облаке зависит от CPU, который выдал flavor: без AVX2 он
не падает, а виснет (см. «Грабли»). Проверить сразу:

```sh
grep -c avx2 /proc/cpuinfo     # должно быть > 0
claude --version
```

Цвета в терминале. Emacs включает 24-битный цвет по `COLORTERM=truecolor`,
а ssh эту переменную по умолчанию не передаёт: в tmux (он выставляет её
сам) тема нормальная, по голому ssh — огрублённая до 256 цветов. Сервер
её принимает (`accepted-environment` в `t1.scm`), клиенту в `~/.ssh/config`:

```
Host t1
    SendEnv COLORTERM
```

Проверка на VM вне tmux: `echo $COLORTERM` → `truecolor`, в Emacs
`M-: (display-color-cells)` → `16777216`. Без truecolor Emacs сам берёт
тему `modus-vivendi` вместо `ef-maris-dark`.

### 9. Секреты (на VM)

Положить age-ключ (как — раздел «Секреты»: скопировать `~/.age-key` или
завести ключ машины и `sops updatekeys`) и перезапустить сервис — при
загрузке он уже отработал без ключа и сам не повторит:

```sh
herd restart home-sops-secrets
ls -l /run/user/$(id -u)/secrets/     # bashrc.local, xray.json
```

Готово: система (`t1.scm`), пиннутый Guix, home для программирования,
секреты. Дальнейшие правки — в репозитории, затем `git pull` на VM и
`sysrec` / `homerec`.

## Emacs

Emacs целиком из Guix: `emacs-next` (31), все пакеты и грамматики
tree-sitter — в `home/emacs.scm`, конфиг — в `files/emacs/`. package.el,
MELPA и straight не используются, `:ensure` в `use-package` нет.
Входит в `home/base.scm`, то есть есть и на облачной VM, и на локальной.

```
files/emacs/
  early-init.el     пути: конфиг read-only, состояние — в ~/.local/state/emacs
  init.el           подключает модули по порядку
  lisp/dy-*.el      по модулю на тему: evil, completion, python, go, rust, org, …
  snippets/         yasnippet
```

Куда что пишется:

| Что | Где |
|---|---|
| конфиг (`init.el`, `lisp/`, `snippets/`) | `~/.config/emacs` — симлинки в стор, **read-only** |
| eln-cache, бэкапы, история, `custom.el`, transient, project-list | `~/.local/state/emacs` (`user-emacs-directory`) |

Отсюда правило: конфиг и сниппеты правятся в репозитории, затем
`homerec`. Customize (`M-x customize`) пишет в `~/.local/state/emacs/custom.el`
— это состояние машины, в репозиторий не попадает.

### Guile и Guix (`dy-scheme.el`)

REPL geiser — это `guix repl`, а не голый `guile`: в нём сразу модули
Guix из `guix pull` (с каналами, например sops-guix) и уже
скомпилированные `.go`. Модули этого репозитория видны через
`$GUIX_CONFIG` (`(systems base)`, `(home base)`, `(packages …)`).

В `scheme-mode`:

| Клавиши | Что |
|---|---|
| `SPC m r` | REPL (`guix repl`) |
| `SPC m d` / `SPC m b` / `SPC m l` | eval определения / буфера / выражения перед курсором |
| `M-.` / `M-,` | к определению (в том числе в исходники Guix) и обратно |
| `SPC m e` | раскрыть макрос на месте (macrostep) |
| `SPC m g b` / `g l` / `g s` | собрать / lint / скачать исходник пакета под курсором |
| `C-c .` | остальные команды `guix-devel-mode` |
| `M-x guix` | пакеты, профили, поколения (emacs-guix) |

Отступы и подсветка форм Guix (`package`, `origin`, `modify-phases`, …)
— `guix-devel-mode` (emacs-guix), включается сам. Скобки — lispyville
(и в Emacs Lisp): `d`/`c`/`y` не ломают баланс, `>`/`<` в normal —
затянуть/вытолкнуть выражение, `M-j`/`M-k` — переставить. Сниппеты
самого Guix (`guix-package`, `guix-origin`, сообщения коммитов) берутся
из git-кэша каналов `~/.cache/guix/checkouts/*/etc/snippets/yas`.

### Добавить пакет

1. Строка в `%emacs-packages` (`home/emacs.scm`); имя —
   `guix search emacs-<имя>`.
2. `use-package` без `:ensure` в подходящем `files/emacs/lisp/dy-*.el`.
3. `homerec`.

Если пакета нет в Guix — либо маленькая замена в конфиге (так сделаны
pytest, gotest, ruff-format, clipetty — см. комментарии в модулях), либо
упаковать его в `packages/`, как `claude-code`.

### Попробовать без guix home

На машине со своим `~/.emacs.d` (например, на хосте):

```sh
guix shell -m home/emacs-manifest.scm -- emacs --init-directory=files/emacs
```

Состояние всё равно уйдёт в `~/.local/state/emacs`, старый `~/.emacs.d`
не тронут. Проверить конфиг без окна:

```sh
guix shell -m home/emacs-manifest.scm -- emacs --batch --init-directory=files/emacs \
  -l files/emacs/early-init.el -l files/emacs/init.el
```

### Что осталось от старого `~/.emacs.d` и что нет

Перенесены: evil со всеми сочетаниями на `SPC`, vertico/orderless/
consult/embark/corfu, magit (с заготовкой коммита из имени ветки),
eglot, Python (docstring, pytest, ruff, pyvenv), Go, Rust, org
(agenda, capture, помодоро), denote, vterm, kkp и OSC 52 для `-nw`.

Не перенесены: telega, mu4e, elfeed, erc, forge, org-roam, dape,
AI-пакеты (agent-shell, gptel, ellama, eca), рабочие модули
(`dy-http`, `dy-kaas`, `dy-t1`, …). Вернуть — см. «Добавить пакет».

### Грабли

- **Грамматики Guix не видны до `(require 'treesit)`.** Путь из
  `TREE_SITTER_GRAMMAR_PATH` попадает в `treesit-extra-load-path` только
  при загрузке `treesit.el`, а `treesit-language-available-p` (функция
  на C) без него отвечает nil. Поэтому `dy-treesit.el` начинается с
  `require`.
- **После первого `homerec` с Emacs — перелогиниться, и из tmux тоже.**
  Пакеты и грамматики Emacs находит по `EMACSLOADPATH` и
  `TREE_SITTER_GRAMMAR_PATH` из home-профиля, а они выставляются при
  входе. В старой сессии Emacs запустится без пакетов: `Cannot load evil`,
  `Invalid completion style orderless`. Новое окно tmux не поможет — оно
  берёт окружение у сервера tmux: `tmux kill-server`, выйти из ssh, зайти
  заново. Проверка: `echo $EMACSLOADPATH` непустой.
- **По ssh без tmux тема «грязная».** ssh не передаёт `COLORTERM`, Emacs
  не знает про truecolor и рисует в 256 цветах. `SendEnv COLORTERM` на
  клиенте + `AcceptEnv` на сервере (в `t1.scm` уже есть). Задавать
  `COLORTERM` на сервере жёстко не стоит: в консоли без truecolor
  (tty локальной VM) это даст мусор.
- **t1 потерял ssh после включения WireGuard и Docker.** После `sysrec`
  (sops-secrets + wg-ruclaw + dockerd) и выхода из сессии новый `ssh`
  подключался по TCP, но сервер не присылал даже приветствия; консоль
  панели после неудачного входа тоже встала. Похоже на зависший shepherd
  (PID 1): в Guix он принимает соединения ssh и запускает sshd и login.
  В локальной VM с той же конфигурацией (но без настоящего туннеля) всё
  работало, `AllowedIPs` — только три `172.31.x.0/20`. Причина не найдена,
  VM пересоздана. Меры: пароль для консоли сразу после первого входа,
  запасная сессия при каждом `sysrec`, WireGuard — флагом и сначала
  вручную, у `wg-quick` в сервисе таймаут.
- **`C-w C-h/j/k/l` в evil нет** — только буквенные `C-w h/j/k/l`.
  Контрольные варианты, как в Vim, добавлены в `dy-evil.el`.
- **ESC в `emacs -nw` без kkp.** Протокол kitty (kkp) включается, только
  если терминал на него ответил: alacritty — да, tmux — нет. Без kkp ESC
  для Emacs — префикс Meta, и без перехвата evil `Esc C-w` читается как
  `C-M-w`: из insert не выйти (заметно в REPL geiser — он открывается
  в insert). Поэтому `evil-intercept-esc` оставлен по умолчанию; где kkp
  включился, его `define-key "\e[…"` сам снимает обёртку evil.
- **`guix shell -m` кэширует окружение по файлу манифеста**, а не по
  тому, что он подключает. После правки `home/emacs.scm` манифест
  `home/emacs-manifest.scm` не изменился — и shell отдаст старое
  окружение без новых пакетов (`Cannot open load file …`). Нужен
  `guix shell --rebuild-cache -m home/emacs-manifest.scm …`.
- **Модули каналов в REPL — только те, что в `guix pull` этой машины.**
  На хосте нет канала sops-guix, поэтому eval `home/base.scm` там
  упадёт на `(sops secrets)`; на t1 канал есть.
- **`~/.emacs.d` побеждает `~/.config/emacs`.** Если на машине есть
  `~/.emacs.d` (или `~/.emacs`), Emacs возьмёт его. На хосте — либо
  `--init-directory`, либо переименовать старый каталог.
- **Пакеты Guix приходят только байт-компилированными** (`.elc`, без
  `.eln`; нативно собран лишь встроенный Lisp самого Emacs). При первом
  интерактивном запуске Emacs нативно компилирует их в фоне в
  `~/.local/state/emacs/eln-cache` — первый запуск медленнее, это норма.

## Docker

Docker из Guix застрял на 20.10 (2023) с compose v1 на Python и без
buildx — свежим compose-файлам (`!reset`/`!override`, profiles) и
Dockerfile с BuildKit (`RUN --mount=type=cache`) этого мало. Поэтому, как
с Xray, — официальные статические бинарники (`packages/docker.scm`):
Engine 29 (dockerd, containerd, runc, CLI), compose v5, buildx.

| Часть | Где |
|---|---|
| `dockerd` (сам запускает свой containerd), группа `docker`, `docker` CLI в системном профиле | `systems/docker.scm` → `docker-static-services` в `systems/<host>.scm` (сейчас t1) |
| плагины `docker compose`, `docker buildx` | `home/docker.scm` → `~/.docker/cli-plugins/`, входит в `make-home` |

`daemon.json` собирается в сервисе: `cgroupfs` (systemd нет), insecure-
реестры параметром, сети compose — из `10.210.0.0/16`, а не из дефолтных
172.17–172.31: те пересекаются с сетями за VPN (ruclaw — `172.31.0.0/20`, …).
Статические бинарники не обёрнуты, как guix-овский docker, поэтому `PATH`
для dockerd (iptables, ip, modprobe, …) и `LINUX_MODULE_DIRECTORY` заданы
в сервисе явно.

Применить и проверить:

```sh
git pull && sysrec && homerec
# группа docker появится только в новой сессии: tmux kill-server, выйти, войти
docker version                 # Client и Server 29.x
docker compose version
docker buildx version
docker run --rm hello-world
```

Лог демона: `/var/log/docker.log`.

## WireGuard (проектная сеть ruclaw)

Проектная сеть ruclaw (`172.31.0.0/20`, `.16.0/20`, `.32.0/20`: реестр
образов, nexus, vault, keycloak, livekit) — WireGuard. На хосте это
соединение NetworkManager, на t1 — `systems/wg-quick.scm`: весь конфиг
wg-quick (с приватным ключом) лежит в sops, системный sops-guix
расшифровывает его при загрузке в `/run/secrets/ruclaw.conf`, сервис
`wg-ruclaw` делает `wg-quick up`. Штатный `wireguard-service-type` не
подошёл: пиры описываются в конфиге системы, адрес сервера и ключи ушли бы
в стор и git.

**Ключ и адрес — те же, что у хоста** (`10.8.0.4`). Сервер WireGuard
считает их одним клиентом и шлёт ответы туда, откуда пришёл последний
пакет: одновременно туннель работает только на одной машине. На хосте
`nmcli connection down ruclaw` **мало** — интерфейс `ruclaw` остаётся
с ключом и отвечает серверу, и тот часть трафика t1 отдаёт хосту.
Симптом на t1: handshake есть, ping ходит, но DNS внутри VPN то отвечает,
то нет, а TCP на 443 реестра висит. Удалять интерфейс целиком:

```sh
sudo ip link delete ruclaw        # на хосте, перед работой на t1
ip -br link show ruclaw           # Device "ruclaw" does not exist
```

Имена `*.k2int-ruclaw.loc` разрешает DNS внутри VPN (`172.31.32.1`):
строка `DNS =` в конфиге, wg-quick на время туннеля ставит его в
`/etc/resolv.conf` через resolvconf. Так имена видны и контейнерам Docker —
их DNS берёт серверы из `resolv.conf` хоста, а `/etc/hosts` хоста не видит
(поэтому статических записей `#:hosts` мало).

### Секрет с конфигом (один раз, на хосте)

Берётся оригинальный конфиг wg-quick целиком (`/etc/wireguard/ruclaw.conf`
на хосте) — с `Address`, `DNS`, `MTU`, `Endpoint` по имени. `wg showconf`
не годится: он отдаёт только то, что знает ядро (без `Address`, `DNS`, `MTU`).

```sh
cd ~/vms/guix-config
sudo grep AllowedIPs /etc/wireguard/ruclaw.conf   # НЕ 0.0.0.0/0 — иначе в туннель уйдёт и ssh
{ echo 'ruclaw.conf: |'
  sudo cat /etc/wireguard/ruclaw.conf | sed 's/^/  /'
} | guix shell sops -- sops encrypt --input-type yaml --output-type yaml \
      --filename-override files/secrets/wg-ruclaw.yaml /dev/stdin > files/secrets/wg-ruclaw.yaml
git add files/secrets/wg-ruclaw.yaml
```

### На машине

Системному sops нужен age-ключ root (один раз):

```sh
sudo install -D -m 600 ~/.age-key /root/.config/sops/age/keys.txt
```

**Включать осторожно** (однажды после включения t1 потерял ssh, причина не
найдена — см. «Грабли»). WireGuard выключен флагом `%ruclaw-wg?` в
`t1.scm`. Порядок:

1. Запасная ssh-сессия открыта, пароль для консоли задан (см. «Облачная VM»).
2. Сначала руками, мимо shepherd:
   ```sh
   sops -d --extract '["ruclaw.conf"]' files/secrets/wg-ruclaw.yaml | sudo tee /root/ruclaw.conf >/dev/null
   sudo chmod 600 /root/ruclaw.conf
   sudo wg-quick up /root/ruclaw.conf     # из guix shell wireguard-tools, если wg-quick нет
   ```
   и **из другого терминала** — новый `ssh t1`. Работает — `sudo wg-quick
   down /root/ruclaw.conf`, `sudo rm /root/ruclaw.conf`. Не работает —
   `wg-quick down` в запасной сессии, и ищем причину в конфиге.
3. Только потом `%ruclaw-wg? #t`, коммит, `git pull && sysrec` — и снова
   проверка нового входа из другого терминала.

Проверка:

```sh
sudo herd status sops-secrets wg-ruclaw
sudo wg show ruclaw latest-handshakes     # недавнее время = сервер отвечает
ping -c2 172.31.32.4
grep nameserver /etc/resolv.conf          # первым — 172.31.32.1
curl -skI https://docker-registry.k2int-ruclaw.loc/v2/ | head -1   # HTTP/2 401
docker run --rm busybox nslookup docker-registry.k2int-ruclaw.loc  # и из контейнера
```

Опустить/поднять: `sudo herd stop wg-ruclaw` / `sudo herd start wg-ruclaw`.

## VPN (Xray)

Как на хосте (`xray` + `net.sh` с tun2socks), только декларативно и без
tun2socks — в Xray есть свой tun-вход:

```
программа → маршрут на xray0 → Xray-tun (система, root)
          → SOCKS 127.0.0.1:10808 → Xray-клиент (home, пользователь)
          → VLESS/REALITY → сервер
```

| Часть | Где | Секреты |
|---|---|---|
| Xray-клиент, SOCKS `127.0.0.1:10808` | `home/xray.scm`, входит в `make-home` — есть и в `programming`, и в `dyens` | конфиг — `files/secrets/xray.yaml` |
| tun `xray0` + `ip route` на список адресов | `systems/xray-tun.scm`, подключается в `systems/<host>.scm` (сейчас — `t1.scm`) | нет |

Через VPN идут только адреса из списка в `t1.scm` (сейчас подсеть
Anthropic — для Claude Code — и адрес из `net.sh`). Остальное, включая
трафик к самому VPN-серверу, — напрямую; поэтому петли нет. Не добавляйте
в список адрес VPN-сервера и не заворачивайте `0.0.0.0/0` — потеряете
сеть, а на облачной VM и ssh. Программы с поддержкой прокси могут
ходить в SOCKS напрямую: `socks5://127.0.0.1:10808`.

### Секрет с конфигом (один раз, на хосте)

Конфиг клиента — обычный JSON Xray. В репозиторий он попадает только
зашифрованным: ключ `xray.json` в `files/secrets/xray.yaml`. Открытый
текст на диск не пишется; заодно `loglevel` понижается с `debug`, иначе
лог сервиса растёт без конца:

```sh
cd ~/vms/guix-config
{ echo 'xray.json: |'
  sed 's/"loglevel": "debug"/"loglevel": "warning"/; s/^/  /' ~/vpn/dyvpn/timeweb.json
} | guix shell sops -- sops encrypt --input-type yaml --output-type yaml \
      --filename-override files/secrets/xray.yaml /dev/stdin > files/secrets/xray.yaml
git add files/secrets/xray.yaml
```

Получатель берётся из `.sops.yaml` по пути файла (`--filename-override`),
приватный ключ для шифрования не нужен. Поменять конфиг потом:
`sops files/secrets/xray.yaml`.

### Применить (на машине)

```sh
git pull
sysrec      # систему: сервис xray-tun (root)
homerec     # home: сервис xray (пользователь)
```

Проверка:

```sh
herd status xray                     # клиент, без sudo
sudo herd status xray-tun            # tun
ip route get 160.79.104.10           # … dev xray0
curl -sI https://api.anthropic.com | head -1
```

Логи: `~/.local/state/xray.log` (клиент), `/var/log/xray-tun.log` (tun).

Если что-то не так, сначала разделить: сам VPN или tun?

```sh
# VPN мимо tun — прямо в SOCKS клиента; любой HTTP-код (404) = VPN работает
curl -s -m 15 --socks5-hostname 127.0.0.1:10808 -o /dev/null -w '%{http_code}\n' https://api.anthropic.com
# tun
ip -br addr show xray0               # должен быть 198.18.0.1/32
ip route get 160.79.104.10           # … dev xray0 src 198.18.0.1
```

- **`Invalid argument` на `connect()` / `ip route get` через xray0** — у
  интерфейса нет IPv4-адреса, и ядро не выбирает исходный. Поэтому сервис
  назначает `xray0` адрес `198.18.0.1/32` (на хосте с tun2socks и ядром
  Fedora обходилось без него).

### Пакет Xray

`packages/xray.scm` — официальный статический бинарник релиза (как
`claude-code`, но даже без patchelf). Обновить — версия и хеш, порядок
в комментарии в файле. `guix download` может спотыкаться на редиректе
GitHub на `release-assets.githubusercontent.com`: тогда `curl -LO`,
сверить с `.dgst` релиза и `guix hash` / `guix download file://…`.

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
- **QEMU без `-cpu host`** поднимает модель `qemu64`, которая маскирует
  AVX/AVX2 даже под KVM. Собранные Bun'ом бинарники (Claude Code) на таком
  госте виснут в бесконечном цикле вместо честного `SIGILL`: `--version`
  работает, а TUI — нет. Проверка: `grep avx2 /proc/cpuinfo` в госте.
- **Без elogind не работает Guix Home.** `/run/user/$UID` создаёт он;
  `%base-services` его не содержат, `%desktop-services` — содержат.
  В минимальной системе добавлять явно: `(service elogind-service-type)`.
- **Фолбэк на Software Heritage ломает кэш канала.** Если клон канала
  не удался (у t1 так было с GitHub один раз, причина неизвестна), Guix
  достаёт коммит из архива SWH и кладёт в `~/.cache/guix/checkouts/`
  репозиторий с единственной веткой `master` и без ветки `keyring`. Проверить
  подписи по нему нельзя: `cannot locate remote-tracking branch
  'origin/keyring'`, и каждый следующий pull падает так же. Лечится
  удалением этого каталога из кэша.
- **qcow2 от `guix system image` — версии 1.1 со сжатием zstd.** Облако
  (OpenStack) отвечает на него «ошибкой чтения образа». Перепаковать:
  `qemu-img convert -c -O qcow2 -o compat=0.10`.
- **`--image-size` — это корень, а не весь образ.** Guix добавляет свои
  разделы, и образ `--image-size=10G` не влезает в диск на 10 GiB.
- **Корень из образа не растёт сам** — cloud-init'а нет. После первой
  загрузки: `parted resizepart` + `resize2fs`, см. «Облачная VM».
- **Облако выбирает шину диска само.** VM с Ubuntu видела `/dev/sda`
  (virtio-scsi), VM из нашего образа — `/dev/vda` (virtio-blk). Поэтому
  корень в `t1.scm` описан меткой, а в initrd добавлен `virtio_scsi`.
- **Пакет `rage` в Guix — это медиаплеер на EFL**, а не age-шифрование.
  Нужный пакет называется `age` (понадобится для `age-keygen`). Проверять состав пакета, а не только
  наличие имени: `guix show <имя>`.
