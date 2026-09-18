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
| `packages/claude-code.scm` | проприетарный бинарник, переупакованный под Guix | — (подключается модулем) |
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
3. поле `path` создаёт симлинк на него, например
   `~/.bashrc.local -> /run/user/1000/secrets/bashrc.local`.

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
(list (home-secret "bashrc.local" ".bashrc.local")
      (home-secret "ssh-config"   ".ssh/config"))
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
ls -l ~/.bashrc.local /run/user/$(id -u)/secrets/
```

Ключ — до `homerec`. Если сервис секрета всё же упал (ключ скопирован
позже, сменили значение, а файл старый), перезапустите его:
`herd restart home-sops-secret-<ключ>`, например
`herd restart home-sops-secret-bashrc.local`. Переменные из
`~/.bashrc.local` видны в новом шелле.

Нюансы:

- **Секреты появляются при логине, а не при `reconfigure`.** После
  перезагрузки tmpfs пуст, пока home-shepherd не стартует. Самый первый
  шелл может успеть раньше расшифровки — поэтому `files/bashrc` проверяет
  `-r` и молча пропускает висячий симлинк.
- **Если по пути `path` уже лежит обычный файл** (например `~/.bashrc.local`
  от старой схемы с `guix-secrets`), симлинк не создастся. Удалите файл
  руками один раз.
- **Имена ключей yaml видны открытым текстом**, зашифрованы только значения.
  Называйте ключи так, чтобы это не было проблемой в публичном репозитории.

#### Чего делать нельзя

- приватные ключи, пароли, токены через `local-file`;
- секреты в `files/bashrc` — он тоже уезжает в стор. Для переменных
  окружения держите `~/.bashrc.local`: он не управляется Guix Home,
  подключается последней строкой из `files/bashrc`, а на машину приезжает
  из `files/secrets/home.yaml` через sops.

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

Дальше пересобирать алиасами: `homerec` — home, `sysrec` — систему
(`systems/$(hostname).scm`, то есть `t1.scm`).

<!-- TODO: дописывается по ходу установки t1 -->

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
