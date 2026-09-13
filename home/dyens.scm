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

(add-to-load-path (dirname (dirname (current-filename))))

(use-modules (gnu home)
             (gnu home services)
             (gnu home services shells)
             (gnu home services desktop)   ; home-startx-command-service-type
             (gnu packages)
             (gnu services xorg)           ; xorg-configuration
             (gnu system keyboard)         ; keyboard-layout
             (guix gexp)
             (sops secrets)                ; sops-secret      — канал sops-guix
             (sops home services sops)     ; home-sops-secrets-service-type
             (packages claude-code))       ; см. packages/claude-code.scm

;; Зашифрованные секреты. В стор уезжает только шифротекст, открытый
;; текст появляется в tmpfs /run/user/$UID/secrets при старте home-shepherd.
;; Редактировать: guix shell sops -- sops files/secrets/home.yaml
(define home.yaml
  (local-file "../files/secrets/home.yaml" "home.yaml"))

(define (home-secret key target)
  "Секрет KEY из home.yaml, симлинком в ~/TARGET."
  (sops-secret
   (key (list key))
   (file home.yaml)
   (permissions #o400)
   (path (string-append (getenv "HOME") "/" target))))

(home-environment

 (packages
  (cons
   ;; Проприетарный бинарник, переупакованный под Guix.
   ;; Версия зафиксирована хешем — см. packages/claude-code.scm.
   claude-code
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
         "vim"
         "tmux"))))

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
                        ("homerec" . "guix home reconfigure /mnt/guix-config/home/dyens.scm")
                        ;; sops ищет age-ключ в ~/.config/sops/age/keys.txt,
                        ;; у нас он в ~/.age-key. Сам sops в профиль кладёт
                        ;; home-sops-secrets-service-type.
                        ("sops"    . "SOPS_AGE_KEY_FILE=~/.age-key sops")))
             (bashrc (list (local-file "../files/bashrc" "bashrc")))))

   ;; Секреты из files/secrets/home.yaml. Сам sops сервис кладёт в профиль.
   ;; Ключ — ~/.age-key; если его нет, sops пробует ~/.ssh/id_ed25519.
   (service home-sops-secrets-service-type
            (home-sops-service-configuration
             (age-key-file #~(string-append (getenv "HOME") "/.age-key"))
             (secrets
              (list (home-secret "bashrc.local" ".bashrc.local")))))

   ;; ~/.xinitrc — что запускать после startx.
   (simple-service 'xinitrc
                   home-files-service-type
                   `((".xinitrc" ,(local-file "../files/xinitrc"))))

   (simple-service 'dotfiles
                   home-xdg-configuration-files-service-type
                   ;; Пути относительно ~/.config, без префикса .config/
                   `(("i3/config"      ,(local-file "../files/i3/config"))
                     ("tmux/tmux.conf" ,(local-file "../files/tmux.conf"))))
   )))
