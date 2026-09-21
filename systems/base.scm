;;; Общая часть конфигурации всех машин.
;;;
;;; Здесь живёт то, что одинаково везде: пользователь, локаль, раскладка,
;;; зеркало подстановок, набор сервисов. Машинно-зависимое (UUID дисков,
;;; загрузчик, hostname) передаётся параметрами из systems/<host>.scm.
;;;
;;; Модуль подключается так (см. systems/vm.scm):
;;;     (add-to-load-path (dirname (dirname (current-filename))))
;;;     (use-modules (gnu) (systems base))

(define-module (systems base)
  #:use-module (gnu)
  #:use-module (gnu services desktop)   ; %desktop-services
  #:use-module (gnu services xorg)      ; gdm-service-type
  #:use-module (gnu services ssh)       ; openssh-service-type
  #:use-module (systems fhs)            ; /lib64/ld-linux — загрузчик для чужих бинарников
  #:export (make-system
            %substitute-urls
            %keyboard-layout))

;; ci.guix.gnu.org намеренно НЕ в списке: он недоступен из этой сети
;; и на каждом промахе кэша давал бы таймаут. Зеркало Яндекса кэширует
;; bordeaux и отдаёт upstream-подписи, поэтому авторизовывать
;; дополнительные ключи не нужно.
(define %substitute-urls
  '("https://mirror.yandex.ru/mirrors/guix"
    "https://bordeaux.guix.gnu.org"))

;; Раскладка уровня системы = консольные tty + GRUB.
;; Раскладка внутри X задаётся отдельно, в home/dyens.scm.
(define %keyboard-layout
  (keyboard-layout "us,ru" #:options '("ctrl:swapcaps" "grp:rctrl_toggle")))

(define* (make-system #:key
                      (host-name "guix")
                      root-device                 ; например (uuid "..." 'ext4)
                      (root-type "ext4")
                      (swap-device #f)            ; например (uuid "...")
                      (bootloader-type grub-bootloader)
                      (bootloader-targets (list "/dev/vda"))
                      ;; Алист (имя-пользователя file-like) с ПУБЛИЧНЫМИ
                      ;; ключами. Публичные ключи не секрет — их можно
                      ;; держать в репозитории открыто:
                      ;;   `(("dyens" ,(local-file "../files/keys/dyens.pub")))
                      (ssh-authorized-keys '())
                      ;; Выключать пароль ТОЛЬКО после того, как вход
                      ;; по ключу проверен: иначе запрётесь.
                      (ssh-password-auth? #t)
                      (extra-packages '())
                      (extra-services '())
                      (extra-file-systems '()))
  "Собрать <operating-system> из общей базы и машинно-зависимых параметров."
  (operating-system
    (locale "en_US.utf8")
    (timezone "Europe/Moscow")
    (keyboard-layout %keyboard-layout)
    (host-name host-name)

    (users (cons* (user-account
                   (name "dyens")
                   (comment "Dyens")
                   (group "users")
                   (home-directory "/home/dyens")
                   (supplementary-groups '("wheel" "netdev" "audio" "video")))
                  %base-user-accounts))

    ;; Только то, что нужно ДО входа пользователя.
    ;; i3, шрифты, терминал и startx живут в home/dyens.scm.
    (packages (append extra-packages %base-packages))

    (services
     (append (list (service openssh-service-type
                            (openssh-configuration
                             (password-authentication? ssh-password-auth?)
                             (authorized-keys ssh-authorized-keys)))

                   ;; /lib64/ld-linux-x86-64.so.2 — см. systems/fhs.scm.
                   %fhs-loader-service)
             extra-services
             ;; delete gdm-service-type: display manager не используем,
             ;; графика поднимается из home через startx. По той же
             ;; причине здесь нет set-xorg-configuration — конфигурация
             ;; Xorg задаётся в home-startx-command-service-type.
             (modify-services %desktop-services
               (delete gdm-service-type)
               (guix-service-type config =>
                                  (guix-configuration
                                   (inherit config)
                                   (substitute-urls %substitute-urls))))))

    (bootloader (bootloader-configuration
                 (bootloader bootloader-type)
                 (targets bootloader-targets)
                 (keyboard-layout %keyboard-layout)))

    (swap-devices (if swap-device
                      (list (swap-space (target swap-device)))
                      '()))

    (file-systems (cons* (file-system
                           (mount-point "/")
                           (device root-device)
                           (type root-type))
                         (append extra-file-systems %base-file-systems)))))
