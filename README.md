# guix-config

Конфигурация Guix-системы и домашнего окружения. Живёт на хосте
(`~/vms/guix-config`), пробрасывается в VM по 9p в `/mnt/guix-config`.
Правите в привычном редакторе на Fedora — применяете внутри VM,
без коммитов и scp на каждую итерацию.

## Структура

| Путь | Что описывает | Команда применения |
|---|---|---|
| `channels.scm` | версию самого Guix (пин коммита) | `guix pull -C channels.scm` |
| `systems/vm.scm` | систему: ядро, сервисы, юзеров | `sudo -i guix system reconfigure` |
| `home/dyens.scm` | dotfiles и пакеты пользователя | `guix home reconfigure` |
| `files/` | сырые dotfiles, подключаемые через `local-file` | — |
| `run-vm.sh` | запуск qemu с ssh + 9p (выполняется на ХОСТЕ) | — |

Три слоя независимы, и без первого остальные два невоспроизводимы:
тот же `vm.scm` на другом коммите Guix даст другие версии пакетов.

## Запуск VM (на хосте)

```sh
./run-vm.sh            # с графикой
./run-vm.sh headless   # в фоне, без окна
./run-vm.sh ssh        # зайти внутрь
./run-vm.sh stop       # погасить фоновую
```

Переопределяется через env: `GUIX_VM_MEM`, `GUIX_VM_CPUS`,
`GUIX_VM_SSH_PORT`, `GUIX_VM_DISK`, `GUIX_VM_USER`.

## Первый шаг после проброса (внутри VM)

Каталог монтируется автоматически, но только после того, как
`systems/vm.scm` с записью про 9p будет применён. Первый раз —
руками:

```sh
sudo mkdir -p /mnt/guix-config
sudo mount -t 9p -o trans=virtio,version=9p2000.L,msize=104857600 \
     guixcfg /mnt/guix-config
```

Дальше применяем конфиг уже из репозитория, и монтирование станет
автоматическим:

```sh
sudo -i guix system reconfigure /mnt/guix-config/systems/vm.scm
guix home reconfigure /mnt/guix-config/home/dyens.scm
```

## Зафиксировать версию Guix

Сразу после удачного `guix pull`, пока состояние рабочее:

```sh
guix describe -f channels > /mnt/guix-config/channels.scm
git -C /mnt/guix-config commit -am "pin guix $(date +%F)"
```

`channels.scm` в репозитории сейчас — **заглушка** без пина.
Замените, иначе воспроизводимости нет.

## Развернуть на новой VM

### Вариант А — из установщика

Минимальная установка с ISO, потом:

```sh
# зеркало ещё не настроено, поэтому первый pull — с флагом руками.
# Это неустранимая проблема курицы и яйца.
guix pull -C /mnt/guix-config/channels.scm \
  --substitute-urls='https://mirror.yandex.ru/mirrors/guix https://bordeaux.guix.gnu.org'

sudo -i guix system reconfigure /mnt/guix-config/systems/vm.scm
guix home reconfigure /mnt/guix-config/home/dyens.scm
```

Дальше флаг не нужен: `substitute-urls` зашит в `systems/vm.scm`.

Не забыть подставить в `systems/vm.scm` реальные UUID корня и swap
(`blkid`) — они привязаны к конкретному диску.

### Вариант Б — готовый образ (быстро)

Собирает qcow2 прямо из конфига, минуя установщик:

```sh
guix system image -t qcow2 --image-size=20G /mnt/guix-config/systems/vm.scm
```

На выходе путь в `/gnu/store`. Копируете на хост — и каждая новая VM
это `cp` образа плюс запуск. Секунды вместо получаса установки.

### Вариант В — `guix deploy`

Накат конфига на уже работающие VM по SSH, без захода на каждую.
Пригодится, когда машин станет больше одной.

## Грабли

- **`guix-daemon` не перезапускается сам** после reconfigure. Смена
  `substitute-urls` доедет только после `sudo herd restart guix-daemon`
  или перезагрузки.
- **`ps` не показывает guix-daemon** — он поднимается по обращению
  к сокету (socket activation). Это норма, смотрите `sudo herd status guix-daemon`.
- **`sudo guix` ≠ `sudo -i guix`.** Без `-i` берётся guix из PATH
  пользователя, а не обновлённый root'овский, и reconfigure падает
  с «is not a descendant of».
- **Раскладка по слоям**: X — после перелогина, консоль — после
  reboot, GRUB — со следующего поколения.
- **Dotfiles read-only** после `guix home reconfigure` — правьте `files/`.
