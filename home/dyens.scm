;; Домашнее окружение пользователя dyens (Guix Home).
;;
;; Применять БЕЗ root:
;;     guix home reconfigure /mnt/guix-config/home/dyens.scm
;;
;; Откат:  guix home roll-back
;; Список: guix home list-generations
;;
;; Здесь живёт ВСЁ пользовательское: i3, шрифты, терминал, раскладка
;; внутри X и сам startx. Система (systems/vm.scm) о графике не знает
;; ничего — там нет ни display manager'а, ни оконного менеджера.
;;
;; ВАЖНО: Guix Home делает ~/.bashrc, ~/.xinitrc и прочие dotfiles
;; симлинками в /gnu/store, то есть read-only. Править надо файлы
;; в files/, а потом reconfigure. Это и есть та дисциплина, которая
;; даёт воспроизводимость.

(use-modules (gnu home)
             (gnu home services)
             (gnu home services shells)
             (gnu home services desktop)   ; home-startx-command-service-type
             (gnu packages)
             (gnu services xorg)           ; xorg-configuration
             (gnu system keyboard)         ; keyboard-layout
             (guix gexp))

(home-environment

 (packages
  (map specification->package
       '(;; Графическое окружение
         "i3-wm"
         "i3status"
         "dmenu"
         "st"
         ;; Шрифты: fontconfig подхватывает их из домашнего профиля,
         ;; в систему ставить не нужно.
         "font-dejavu"
         "font-google-noto"
         ;; Утилиты
         "git"
         "ripgrep"
         "fd"
         "htop"
         "curl"
         "unzip"
         "vim")))

 (services
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

   (service home-bash-service-type
            (home-bash-configuration
             (aliases '(("ll"  . "ls -alF")
                        ("la"  . "ls -A")
                        ("gs"  . "git status")
                        ("gd"  . "git diff")
                        ;; reconfigure системы и home из проброшенного репозитория
                        ("sysrec"  . "sudo -i guix system reconfigure /mnt/guix-config/systems/vm.scm")
                        ("homerec" . "guix home reconfigure /mnt/guix-config/home/dyens.scm")))
             (bashrc (list (local-file "../files/bashrc" "bashrc")))))

   ;; ~/.xinitrc — что запускать после startx.
   (simple-service 'xinitrc
                   home-files-service-type
                   `((".xinitrc" ,(local-file "../files/xinitrc"))))

   (simple-service 'dotfiles
                   home-xdg-configuration-files-service-type
                   `(("i3/config" ,(local-file "../files/i3/config"))))
   )))
