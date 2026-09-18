;; Домашнее окружение пользователя dyens (Guix Home): программирование
;; (home/base.scm) + графика. Для машин без X — home/programming.scm.
;;
;; Применять БЕЗ root:
;;     guix home reconfigure /mnt/guix-config/home/dyens.scm
;;
;; Откат:  guix home roll-back
;; Список: guix home list-generations
;;
;; Здесь живёт графика: i3, шрифты, терминал, раскладка внутри X и сам
;; startx. Система (systems/vm.scm) о графике не знает ничего — там нет
;; ни display manager'а, ни оконного менеджера.
;;
;; ВАЖНО: Guix Home делает ~/.bashrc, ~/.xinitrc и прочие dotfiles
;; симлинками в /gnu/store, то есть read-only. Править надо файлы
;; в files/, а потом reconfigure. Это и есть та дисциплина, которая
;; даёт воспроизводимость.

(add-to-load-path (dirname (dirname (current-filename))))

(use-modules (gnu home services)
             (gnu home services desktop)   ; home-startx-command-service-type
             (gnu packages)
             (gnu services xorg)           ; xorg-configuration
             (gnu system keyboard)         ; keyboard-layout
             (guix gexp)
             (home base))

(make-home
 ;; Репозиторий проброшен с хоста по 9p (см. systems/vm.scm).
 #:repo "/mnt/guix-config"
 #:sysrec "sudo -i guix system reconfigure /mnt/guix-config/systems/vm.scm"
 #:homerec "guix home reconfigure /mnt/guix-config/home/dyens.scm"

 #:extra-packages
 (map specification->package
      '("i3-wm"
        "i3status"
        "dmenu"
        "st"
        ;; Шрифты: fontconfig подхватывает их из домашнего профиля,
        ;; в систему ставить не нужно.
        "font-dejavu"
        "font-google-noto"))

 #:extra-services
 (list
  ;; Кладёт startx в домашний профиль. Display manager не нужен:
  ;; логинитесь на tty и набираете startx.
  ;; Раскладка внутри X задаётся ЗДЕСЬ, а не через
  ;; set-xorg-configuration в системе.
  (service home-startx-command-service-type
           (xorg-configuration
            (keyboard-layout
             (keyboard-layout "us,ru"
                              #:options '("ctrl:swapcaps"
                                          "grp:rctrl_toggle")))))

  ;; ~/.xinitrc — что запускать после startx.
  (simple-service 'xinitrc
                  home-files-service-type
                  `((".xinitrc" ,(local-file "../files/xinitrc"))))

  (simple-service 'i3-config
                  home-xdg-configuration-files-service-type
                  `(("i3/config" ,(local-file "../files/i3/config"))))))
