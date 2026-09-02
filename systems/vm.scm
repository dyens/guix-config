;; Конфигурация системы для dev-VM под QEMU.
;;
;; Применять:
;;     sudo -i guix system reconfigure /mnt/guix-config/systems/vm.scm
;;
;; Собрать готовый образ (не трогая текущую систему):
;;     guix system image -t qcow2 --image-size=20G systems/vm.scm

(use-modules (gnu))
(use-service-modules base cups desktop networking ssh xorg)

(operating-system
  (locale "en_US.utf8")
  (timezone "Europe/Moscow")
  (keyboard-layout (keyboard-layout "us,ru"
                                    #:options '("ctrl:swapcaps"
                                                "grp:rctrl_toggle")))
  (host-name "dyens")

  ;; Список пользователей ('root' подразумевается).
  (users (cons* (user-account
                 (name "dyens")
                 (comment "Dyens")
                 (group "users")
                 (home-directory "/home/dyens")
                 (supplementary-groups '("wheel" "netdev" "audio" "video")))
                %base-user-accounts))

  ;; Пакеты уровня системы. Пользовательские пакеты живут не здесь,
  ;; а в home/dyens.scm — держите эту границу, иначе home-конфиг
  ;; перестанет быть самодостаточным.
  (packages (append (list (specification->package "i3-wm")
                          (specification->package "i3status")
                          (specification->package "dmenu")
                          (specification->package "st"))
                    %base-packages))

  (services
   (append (list
            ;; Пароль по умолчанию разрешён; ключи можно завести
            ;; декларативно — см. закомментированный блок ниже.
            (service openssh-service-type)
            ;; (service openssh-service-type
            ;;          (openssh-configuration
            ;;           (password-authentication? #f)
            ;;           (authorized-keys
            ;;            `(("dyens" ,(local-file "../files/id_ed25519.pub"))))))

            (set-xorg-configuration
             (xorg-configuration (keyboard-layout keyboard-layout))))

           ;; Дефолтный список сервисов, к которому мы добавляемся.
           ;; guix-daemon переопределяем, чтобы ходить через зеркало Яндекса.
           ;; ci.guix.gnu.org намеренно НЕ в списке: он недоступен из этой
           ;; сети и на каждом промахе кэша давал бы таймаут.
           ;; Зеркало кэширует bordeaux и отдаёт upstream-подписи,
           ;; так что авторизовывать дополнительные ключи не нужно.
           (modify-services %desktop-services
             (guix-service-type config =>
               (guix-configuration
                (inherit config)
                (substitute-urls
                 '("https://mirror.yandex.ru/mirrors/guix"
                   "https://bordeaux.guix.gnu.org")))))))

  (bootloader (bootloader-configuration
               (bootloader grub-bootloader)
               (targets (list "/dev/vda"))
               (keyboard-layout keyboard-layout)))

  (swap-devices (list (swap-space
                       (target (uuid "8cc62121-4969-469d-9f94-5fd10a0d36ad")))))

  (file-systems
   (cons* (file-system
            (mount-point "/")
            (device (uuid "981499e3-df04-42f4-adfe-1145b86a5a13" 'ext4))
            (type "ext4"))

          ;; Каталог с этим репозиторием, проброшенный с хоста по 9p.
          ;; Требует запуска qemu с:
          ;;   -virtfs local,path=<repo>,mount_tag=guixcfg,security_model=none
          ;;
          ;; mount-may-fail? ОБЯЗАТЕЛЕН. Без него неудачное монтирование
          ;; роняет цель file-systems, от которой зависит user-processes,
          ;; а от неё — весь графический стек (dbus, elogind, gdm).
          ;; Результат: sshd поднимается, а GDM/i3 — нет.
          ;; UUID-ов у 9p нет, поэтому check? отключён.
          (file-system
            (mount-point "/mnt/guix-config")
            (device "guixcfg")
            (type "9p")
            (options "trans=virtio,version=9p2000.L,msize=104857600")
            (mount-may-fail? #t)
            (check? #f)
            (create-mount-point? #t))

          %base-file-systems)))
