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
         ;; Расшифровка секретов из guix-secrets (age-совместимый).
         ;; Нужен и скрипту активации ниже, и вручную — bin/secret-*.
         "rage"
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

   ;; Секреты: расшифровываются и раскладываются по $HOME при каждом
   ;; `guix home reconfigure`.
   ;;
   ;; Источник — первый существующий из:
   ;;   /mnt/guix-secrets/home  (проброшено с хоста по 9p, локальная VM)
   ;;   ~/secrets/home          (клон публичного репозитория guix-secrets)
   ;;
   ;; Ключ расшифровки — первый существующий из:
   ;;   ~/.age-key              (общий ключ, копируется на машину руками)
   ;;   ~/.ssh/id_ed25519       (если машина в .age-recipients)
   ;;
   ;; Парольной фразы у ключа нет — расшифровка идёт молча, без интерактива.
   ;; Нет источника или нет ключа — шаг пропускается, машина
   ;; разворачивается нормально.
   ;;
   ;; Обрабатываются ТОЛЬКО файлы *.age: суффикс отбрасывается, результат
   ;; кладётся по тому же относительному пути. Файлы без суффикса
   ;; игнорируются — так плейнтекст из публичного репозитория не попадёт
   ;; в $HOME даже случайно. Файлы 600, каталоги 700.
   ;;
   ;; Содержимое секретов в /gnu/store НЕ попадает: файлы читаются
   ;; по обычному пути во время активации, а не через local-file.
   ;; В сторе оказывается только сам скрипт.
   ;;
   ;; Используются только примитивы ядра Guile (opendir/readdir), без
   ;; use-modules: внутри gexp он может оказаться не на верхнем уровне.
   (simple-service
    'install-secrets
    home-activation-service-type
    #~(let* ((home (getenv "HOME"))
             (rage #$(file-append (specification->package "rage") "/bin/rage"))
             (first-existing
              (lambda (paths)
                (let pick ((p paths))
                  (cond ((null? p) #f)
                        ((file-exists? (car p)) (car p))
                        (else (pick (cdr p)))))))
             (src (first-existing
                   (list "/mnt/guix-secrets/home"
                         (string-append home "/secrets/home"))))
             (key (first-existing
                   (list (string-append home "/.age-key")
                         (string-append home "/.ssh/id_ed25519"))))
             (age-file?
              (lambda (name)
                (let ((n (string-length name)))
                  (and (> n 4)
                       (string=? ".age" (substring name (- n 4) n))))))
             (walk
              (lambda (walk from to)
                (let ((port (opendir from)))
                  (let next ()
                    (let ((name (readdir port)))
                      (if (eof-object? name)
                          (closedir port)
                          (begin
                            (unless (member name (list "." ".."))
                              (let ((f (string-append from "/" name)))
                                (if (eq? (quote directory) (stat:type (stat f)))
                                    (let ((t (string-append to "/" name)))
                                      (unless (file-exists? t) (mkdir t))
                                      (chmod t #o700)
                                      (walk walk f t))
                                    (when (age-file? name)
                                      (let* ((n (string-length name))
                                             (t (string-append
                                                 to "/" (substring name 0 (- n 4)))))
                                        (when (file-exists? t) (delete-file t))
                                        (if (zero? (system* rage "-d" "-i" key
                                                            "-o" t f))
                                            (chmod t #o600)
                                            (begin
                                              (display "не расшифровался: ")
                                              (display f)
                                              (newline))))))))
                            (next)))))))))
        (cond ((not src)
               (display "секреты: источник не найден, пропускаю")
               (newline))
              ((not key)
               (display "секреты: нет ключа (~/.age-key), пропускаю")
               (newline))
              (else
               (walk walk src home)
               (display "секреты разложены из ")
               (display src)
               (newline)))))

   ;; ~/.xinitrc — что запускать после startx.
   (simple-service 'xinitrc
                   home-files-service-type
                   `((".xinitrc" ,(local-file "../files/xinitrc"))))

   (simple-service 'dotfiles
                   home-xdg-configuration-files-service-type
                   `(("i3/config" ,(local-file "../files/i3/config"))))
   )))
