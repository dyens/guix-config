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

   ;; Секреты: раскладываются по $HOME при каждом `guix home reconfigure`.
   ;;
   ;; Файлы читаются по обычному пути на диске, а НЕ через local-file —
   ;; поэтому их содержимое в /gnu/store не попадает. В сторе оказывается
   ;; только сам скрипт. Это принципиально: стор читается любым
   ;; пользователем машины.
   ;;
   ;; Источник — первый существующий из:
   ;;   /mnt/guix-secrets/home  (проброшено с хоста по 9p, dev-VM)
   ;;   ~/secrets/home          (клон приватного репозитория)
   ;; Нет ни одного — шаг молча пропускается.
   ;;
   ;; Копируется всё дерево целиком: файлы 600, каталоги 700.
   ;; Списка файлов вести не надо — положили в home/, сделали homerec.
   ;;
   ;; Используются только примитивы ядра Guile (opendir/readdir), без
   ;; use-modules: внутри gexp он может оказаться не на верхнем уровне.
   (simple-service
    'install-secrets
    home-activation-service-type
    #~(let* ((home (getenv "HOME"))
             (candidates (list "/mnt/guix-secrets/home"
                               (string-append home "/secrets/home")))
             (src (let pick ((c candidates))
                    (cond ((null? c) #f)
                          ((file-exists? (car c)) (car c))
                          (else (pick (cdr c))))))
             (walk
              (lambda (walk from to)
                (let ((port (opendir from)))
                  (let next ()
                    (let ((name (readdir port)))
                      (if (eof-object? name)
                          (closedir port)
                          (begin
                            (unless (member name (list "." ".."))
                              (let ((f (string-append from "/" name))
                                    (t (string-append to "/" name)))
                                (if (eq? (quote directory) (stat:type (stat f)))
                                    (begin
                                      (unless (file-exists? t) (mkdir t))
                                      (chmod t #o700)
                                      (walk walk f t))
                                    (begin
                                      (when (file-exists? t) (delete-file t))
                                      (copy-file f t)
                                      (chmod t #o600)))))
                            (next)))))))))
        (if src
            (begin
              (walk walk src home)
              (display "секреты разложены из ")
              (display src)
              (newline))
            (begin
              (display "секреты не найдены, пропускаю")
              (newline)))))

   ;; ~/.xinitrc — что запускать после startx.
   (simple-service 'xinitrc
                   home-files-service-type
                   `((".xinitrc" ,(local-file "../files/xinitrc"))))

   (simple-service 'dotfiles
                   home-xdg-configuration-files-service-type
                   `(("i3/config" ,(local-file "../files/i3/config"))))
   )))
