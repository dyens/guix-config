;;; Раскладка секретов из репозитория guix-secrets.
;;;
;;; Подключается из home/dyens.scm:
;;;     (add-to-load-path (dirname (dirname (current-filename))))
;;;     (use-modules (home secrets))
;;;     ... (install-secrets-service) ...
;;;
;;; Как это работает. При каждом `guix home reconfigure` запускается
;;; скрипт, который проходит дерево с секретами, расшифровывает все
;;; файлы *.age и кладёт результат в $HOME по тем же относительным
;;; путям, без суффикса. Файлы получают права 600, каталоги 700.
;;;
;;; Почему секреты не встроены в конфигурацию: всё, что попадает
;;; в неё через local-file, уезжает в /gnu/store, а стор читается
;;; любым пользователем машины. Здесь файлы читаются по обычному пути
;;; ВО ВРЕМЯ выполнения, поэтому в сторе оказывается только сам скрипт.
;;;
;;; Файлы без суффикса .age игнорируются — так плейнтекст из публичного
;;; репозитория не попадёт в $HOME даже случайно.

(define-module (home secrets)
  #:use-module (gnu home services)   ; home-activation-service-type
  #:use-module (gnu packages)        ; specification->package
  #:use-module (gnu services)        ; simple-service
  #:use-module (guix gexp)
  #:export (install-secrets-service))

;; Где искать секреты. Берётся первый существующий путь.
;; Ведущее "~/" разворачивается во время выполнения.
(define %sources
  '("/mnt/guix-secrets/home"    ; проброшено с хоста по 9p (локальная dev-VM)
    "~/secrets/home"))          ; обычный клон репозитория guix-secrets

;; Чем расшифровывать. Тоже первый существующий.
(define %identities
  '("~/.age-key"                ; общий ключ, копируется на машину руками
    "~/.ssh/id_ed25519"))       ; если машина внесена в .age-recipients

;; ВНИМАНИЕ: пакет называется "age" (gnu/packages/golang-crypto.scm).
;; Пакет "rage" в Guix — это медиаплеер на EFL, а не шифрование.
(define %age
  (file-append (specification->package "age") "/bin/age"))

(define (install-secrets-program)
  "Скрипт, раскладывающий секреты по $HOME. Отдельной программой, а не
инлайновым gexp: так внутри допустим use-modules на верхнем уровне,
и код читается как обычный Guile."
  (program-file
   "install-secrets"
   #~(begin
       (use-modules (ice-9 ftw)      ; scandir
                    (ice-9 format)
                    (srfi srfi-1))   ; find

       (define %age #$%age)
       (define %home (getenv "HOME"))

       (define (expand path)
         "Развернуть ведущее ~/ в путь к домашнему каталогу."
         (if (and (> (string-length path) 1)
                  (string=? "~/" (substring path 0 2)))
             (string-append %home (substring path 1))
             path))

       (define (first-existing paths)
         (find file-exists? (map expand paths)))

       (define (age-file? name)
         (let ((n (string-length name)))
           (and (> n 4) (string=? ".age" (substring name (- n 4) n)))))

       (define (strip-suffix name)
         (substring name 0 (- (string-length name) 4)))

       (define (directory? path)
         (eq? 'directory (stat:type (stat path))))

       (define (ensure-directory path)
         (unless (file-exists? path) (mkdir path))
         (chmod path #o700))

       (define (decrypt key from to)
         "Расшифровать FROM в TO с правами 600. #t при успехе."
         (when (file-exists? to) (delete-file to))
         (and (zero? (system* %age "-d" "-i" key "-o" to from))
              (begin (chmod to #o600) #t)))

       (define (install key from to)
         "Пройти дерево FROM, разложив расшифрованные файлы в TO."
         (for-each
          (lambda (name)
            (unless (member name '("." ".."))
              (let ((source (string-append from "/" name)))
                (cond
                 ((directory? source)
                  (let ((target (string-append to "/" name)))
                    (ensure-directory target)
                    (install key source target)))
                 ((age-file? name)
                  (let ((target (string-append to "/" (strip-suffix name))))
                    (unless (decrypt key source target)
                      (format #t "не расшифровался: ~a~%" source))))
                 (else #f)))))          ; не *.age — игнорируем
          (scandir from)))

       (let ((source (first-existing '#$%sources))
             (key    (first-existing '#$%identities)))
         (cond
          ((not source)
           (format #t "секреты: источник не найден, пропускаю~%"))
          ((not key)
           (format #t "секреты: ключ не найден (~~/.age-key), пропускаю~%"))
          (else
           (install key source %home)
           (format #t "секреты разложены из ~a~%" source)))))))

(define (install-secrets-service)
  "Сервис активации, раскладывающий секреты по $HOME.
Ошибка расшифровки не прерывает активацию: сообщение печатается,
остальные секреты обрабатываются дальше."
  (simple-service 'install-secrets
                  home-activation-service-type
                  #~(system* #$(install-secrets-program))))
