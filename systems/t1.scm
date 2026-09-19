;;; Облачная VM t1 (OpenStack Nova, KVM). Сервер без графики.
;;;
;;; Железо: загрузка BIOS (не UEFI), диск /dev/vda (virtio-blk), сеть
;;; virtio-net по DHCP. cloud-init в Guix нет, поэтому ssh-ключ зашит
;;; в конфиг, а не приезжает из метаданных облака.
;;;
;;; Паролей нет ни у кого: вход только по ключу, sudo для wheel
;;; без пароля. Консоль дублируется на ttyS0 (console log в облаке).
;;;
;;; Это минимальная система: сеть, ssh, sudo, git, elogind, VPN-туннель.
;;; systems/base.scm и каналы не нужны, чтобы образ собирался любым Guix;
;;; из репозитория подключаются только (packages xray) и (systems xray-tun)
;;; (путь добавляет add-to-load-path ниже).
;;;
;;; Как собрать образ и поднять VM — README, раздел «Облачная VM».

(add-to-load-path (dirname (dirname (current-filename))))
(use-modules (gnu)
             (gnu services desktop)      ; elogind
             (systems xray-tun)          ; VPN для выбранных адресов
             (systems docker)            ; Docker Engine (статический)
             (gnu services networking)   ; dhcpcd, ntp
             (gnu services ssh))         ; openssh-service-type

(operating-system
  (host-name "t1")
  (locale "en_US.utf8")
  (timezone "Europe/Moscow")

  ;; virtio_blk (/dev/vda) в %base-initrd-modules уже есть, virtio_scsi
  ;; (/dev/sda) — нет. Облако может подключить диск и так, и так: старая
  ;; VM с Ubuntu видела sda, новая с этим образом — vda. Без модуля initrd
  ;; не найдёт корень и уйдёт в REPL Guile.
  ;;
  ;; Пиннутый Guix предупреждает, что %base-initrd-modules устарел в пользу
  ;; (base-initrd-modules linux-libre). Не менять, пока хост на старом Guix:
  ;; там новой процедуры нет, и образ перестанет собираться.
  (initrd-modules (cons* "virtio_scsi" %base-initrd-modules))
  (kernel-arguments (list "console=tty0" "console=ttyS0,115200"))

  (bootloader (bootloader-configuration
               (bootloader grub-bootloader)
               ;; Используется только при reconfigure на самой машине;
               ;; в образ GRUB ставится независимо от этого значения.
               (targets (list "/dev/vda"))
               (terminal-outputs '(console serial))))

  ;; По метке, а не по UUID: так её создаёт `guix system image`,
  ;; и UUID заранее неизвестен.
  (file-systems (cons (file-system
                        (mount-point "/")
                        (device (file-system-label "Guix_image"))
                        (type "ext4"))
                      %base-file-systems))

  (users (cons (user-account
                (name "dyens")
                (comment "Dyens")
                (group "users")
                (home-directory "/home/dyens")
                (supplementary-groups '("wheel" "docker")))
               %base-user-accounts))

  (sudoers-file
   (plain-file "sudoers" "root ALL=(ALL) ALL\n%wheel ALL=(ALL) NOPASSWD: ALL\n"))

  (packages (cons (specification->package "git") %base-packages))

  (services
   (append (list (service dhcpcd-service-type)
                 ;; elogind создаёт /run/user/$UID при входе (через PAM).
                 ;; Без него нет XDG_RUNTIME_DIR, и guix home падает на старте
                 ;; home-shepherd: «mkdir: Permission denied: "/run/user"».
                 ;; В systems/base.scm он приходит с %desktop-services.
                 (service elogind-service-type)
                 (service ntp-service-type)
                 ;; Эти адреса — через VPN (tun xray0 → SOCKS 10808 →
                 ;; Xray-клиент из home). Как net.sh на хосте.
                 (xray-tun-service
                  '("160.79.104.0/23"      ; Anthropic (AS399358): api.anthropic.com — Claude Code
                    "146.59.209.152")))    ; из net.sh хоста (OVH)
           (docker-static-services
            ;; Как в /etc/docker/daemon.json хоста (реестры проекта ruclaw).
            #:insecure-registries '("docker-registry.k2int-ruclaw.loc"
                                    "registry.int.nova-platform.io"))
           (list
            (service openssh-service-type
                     (openssh-configuration
                      (password-authentication? #f)
                      (permit-root-login #f)
                      ;; COLORTERM=truecolor от клиента (в ~/.ssh/config:
                      ;; SendEnv COLORTERM). ssh по умолчанию его не
                      ;; передаёт, и emacs -nw рисует тему в 256 цветах.
                      (accepted-environment '("COLORTERM"))
                      (authorized-keys
                       `(("dyens" ,(local-file "../files/keys/dyens-t1-cloud.pub")))))))
           (modify-services %base-services
             (guix-service-type config =>
                                (guix-configuration
                                 (inherit config)
                                 ;; Как в systems/base.scm: ci.guix.gnu.org недоступен.
                                 (substitute-urls '("https://mirror.yandex.ru/mirrors/guix"
                                                    "https://bordeaux.guix.gnu.org"))))))))
