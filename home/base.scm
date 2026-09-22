;;; Общая часть домашнего окружения: всё, что нужно для программирования
;;; на любой машине, с графикой или без.
;;;
;;; Здесь: vim, Emacs (home/emacs.scm), git, tmux, Claude Code, bash, секреты,
;;; VPN-клиент Xray (home/xray.scm). Графика (i3, шрифты, startx) сюда НЕ
;;; входит — её добавляет home/dyens.scm через #:extra-packages / #:extra-services.
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
  #:use-module (packages glab)               ; GitLab CLI, см. packages/glab.scm
  #:use-module (packages kubectl)            ; клиент Kubernetes, см. packages/kubectl.scm
  #:use-module (home emacs)                  ; Emacs и его конфиг
  #:use-module (home xray)                   ; VPN-клиент
  #:use-module (home docker)                 ; плагины docker compose/buildx
  #:use-module (home wireguard)              ; секреты WireGuard (туннель — в системе)
  #:use-module (home ssh)                    ; ~/.ssh/config, ключ GitLab из sops
  #:use-module (home kube)                   ; kubeconfig'и кластеров в ~/k8s
  #:use-module (home telegram)               ; секрет бота для уведомлений
  #:use-module (home claude)                 ; свои скиллы Claude Code
  #:export (make-home))

;; Зашифрованные секреты. В стор уезжает только шифротекст, открытый
;; текст появляется в tmpfs /run/user/$UID/secrets при старте home-shepherd.
;; Редактировать: guix shell sops -- sops files/secrets/home.yaml
(define home.yaml
  (local-file "../files/secrets/home.yaml" "home.yaml"))

;; Без поля `path': здесь оно просто не нужно, читаем прямо из
;; $XDG_RUNTIME_DIR/secrets/<ключ> (см. files/bashrc, home/xray.scm).
;;
;; Раньше тут стояло, что `path' ломается при повторном homerec — падает
;; на уже существующей ссылке. ЭТО УСТАРЕЛО: в нынешнем sops-guix
;; активация сначала зовёт sops-secret-cleanup и только потом
;; sops-secret-create, а cleanup ведёт учёт ссылок в каталоге
;; .extra-links и снимает прежнюю. На `path' построен home/kube.scm.
(define (home-secret key)
  "Секрет KEY из home.yaml → $XDG_RUNTIME_DIR/secrets/KEY."
  (sops-secret
   (key (list key))
   (file home.yaml)
   (permissions #o400)))

(define %programming-packages
  (cons*
   ;; Проприетарный бинарник, переупакованный под Guix.
   ;; Версия зафиксирована хешем — см. packages/claude-code.scm.
   claude-code
   ;; GitLab CLI: в Guix его нет, берём статический бинарник релиза.
   ;; Нужен слэш-команде /review, GitHub-половину закрывает github-cli.
   glab
   ;; Клиент Kubernetes: в Guix тоже нет, тоже бинарник релиза.
   ;; Алиас k -> kubectl — ниже, в home-bash-configuration.
   kubectl
   (map specification->package
        '("git"
          "github-cli"                          ; gh — для /review
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
                    ("k"   . "kubectl")
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
                 (list (home-secret "bashrc.local")))))

      (simple-service 'dotfiles
                      home-xdg-configuration-files-service-type
                      ;; Пути относительно ~/.config, без префикса .config/
                      `(("tmux/tmux.conf" ,(local-file "../files/tmux.conf")))))
     %emacs-services
     %xray-services
     %docker-cli-services
     %claude-services
     %wireguard-secrets
     %kube-secrets
     %telegram-secrets
     %ssh-services
     extra-services))))
