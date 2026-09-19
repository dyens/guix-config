;;; Общая часть домашнего окружения: всё, что нужно для программирования
;;; на любой машине, с графикой или без.
;;;
;;; Здесь: vim, Emacs (home/emacs.scm), git, tmux, Claude Code, bash, секреты. Графика (i3,
;;; шрифты, startx) сюда НЕ входит — её добавляет home/dyens.scm через
;;; #:extra-packages / #:extra-services.
;;;
;;; Точки входа:
;;;     home/programming.scm — только это (облачные VM, сервер без X)
;;;     home/dyens.scm       — это + графика (локальная VM)
;;;
;;; Модуль подключается так же, как systems/base.scm:
;;;     (add-to-load-path (dirname (dirname (current-filename))))
;;;     (use-modules (home base))

(define-module (home base)
  #:use-module (gnu home)
  #:use-module (gnu home services)
  #:use-module (gnu home services shells)
  #:use-module (gnu packages)
  #:use-module (guix gexp)
  #:use-module (sops secrets)                ; sops-secret      — канал sops-guix
  #:use-module (sops home services sops)     ; home-sops-secrets-service-type
  #:use-module (packages claude-code)        ; см. packages/claude-code.scm
  #:use-module (home emacs)                  ; Emacs и его конфиг
  #:export (make-home))

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

(define %programming-packages
  (cons
   ;; Проприетарный бинарник, переупакованный под Guix.
   ;; Версия зафиксирована хешем — см. packages/claude-code.scm.
   claude-code
   (map specification->package
        '("git"
          "ripgrep"
          "fd"
          "htop"
          "curl"
          "unzip"
          "vim"
          "tmux"))))

(define* (make-home #:key
                    ;; Где на ЭТОЙ машине лежит репозиторий: в локальной VM
                    ;; он проброшен по 9p, на облачной — склонирован.
                    ;; Попадает в $GUIX_CONFIG.
                    (repo "~/guix-config")
                    ;; Полные команды для алиасов sysrec/homerec. Машинно-
                    ;; зависимы: путь к конфигу системы и sudo с -i или без
                    ;; (-i — только если guix pull делал root, см. README).
                    sysrec
                    homerec
                    (extra-packages '())
                    (extra-services '()))
  "Собрать <home-environment> для программирования плюс EXTRA-*."
  (home-environment
   (packages (append %programming-packages %emacs-packages extra-packages))

   (services
    (append
     (list
      (simple-service 'guix-config-env
                      home-environment-variables-service-type
                      `(("GUIX_CONFIG" . ,repo)))

      (service home-bash-service-type
               (home-bash-configuration
                (aliases
                 (append
                  '(("ll"  . "ls -alF")
                    ("la"  . "ls -A")
                    ("gs"  . "git status")
                    ("gd"  . "git diff")
                    ;; sops ищет age-ключ в ~/.config/sops/age/keys.txt,
                    ;; у нас он в ~/.age-key. Сам sops в профиль кладёт
                    ;; home-sops-secrets-service-type.
                    ("sops" . "SOPS_AGE_KEY_FILE=~/.age-key sops"))
                  (if sysrec  `(("sysrec"  . ,sysrec))  '())
                  (if homerec `(("homerec" . ,homerec)) '())))
                (bashrc (list (local-file "../files/bashrc" "bashrc")))))

      ;; Секреты из files/secrets/home.yaml. Сам sops сервис кладёт в профиль.
      ;; Ключ — ~/.age-key; если его нет, sops пробует ~/.ssh/id_ed25519.
      ;; Без ключа home ставится, просто секретов не будет.
      (service home-sops-secrets-service-type
               (home-sops-service-configuration
                (age-key-file #~(string-append (getenv "HOME") "/.age-key"))
                (secrets
                 (list (home-secret "bashrc.local" ".bashrc.local")))))

      (simple-service 'dotfiles
                      home-xdg-configuration-files-service-type
                      ;; Пути относительно ~/.config, без префикса .config/
                      `(("tmux/tmux.conf" ,(local-file "../files/tmux.conf")))))
     %emacs-services
     extra-services))))
