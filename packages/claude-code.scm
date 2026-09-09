;;; Claude Code — готовый проприетарный бинарник от Anthropic.
;;;
;;; Зачем это пакет, а не просто скачанный файл:
;;;
;;;   * версия зафиксирована хешем, поэтому `guix time-machine`
;;;     возвращает именно ту версию, что была;
;;;   * интерпретатор правится patchelf'ом внутри пакета, так что
;;;     системе не нужен симлинк /lib64/ld-linux-x86-64.so.2 —
;;;     Guix остаётся без FHS-примесей;
;;;   * ставится и откатывается как любой другой пакет в home.
;;;
;;; Цена: авто-обновление невозможно (стор неизменяемый), версию
;;; бампаем руками. Процедура — в README, раздел «Обновить Claude Code».

(define-module (packages claude-code)
  #:use-module (gnu packages base)              ; glibc
  #:use-module (gnu packages elf)               ; patchelf
  #:use-module (guix build-system trivial)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:export (claude-code))

(define-public claude-code
  (package
    (name "claude-code")
    (version "2.1.266")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "https://downloads.claude.ai/claude-code-releases/"
                           version "/linux-x64/claude"))
       (file-name (string-append "claude-" version))
       ;; Из подписанного manifest.json релиза, поле
       ;; platforms.linux-x64.checksum, переведённое в nix-base32.
       ;; Если хеш не сойдётся, сборка упадёт — это и есть проверка.
       (sha256
        (base32 "1b1zv3zqf7cqaw1qiy5q4h78cd5h59nxy138jg73yfc9x42jg10r"))))
    (build-system trivial-build-system)
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      #~(begin
          (use-modules (guix build utils))
          (let ((exe (string-append #$output "/bin/claude")))
            (mkdir-p (dirname exe))
            (copy-file #$source exe)
            ;; patchelf'у нужен доступ на запись, поэтому 755 сейчас
            ;; и 555 после.
            (chmod exe #o755)
            ;; Ради этой строки всё и затевалось: бинарник собран под
            ;; FHS и ищет загрузчик по /lib64/ld-linux-x86-64.so.2,
            ;; которого в Guix нет. Указываем на glibc в сторе.
            (invoke #$(file-append patchelf "/bin/patchelf")
                    "--set-interpreter"
                    #$(file-append glibc "/lib/ld-linux-x86-64.so.2")
                    exe)
            (chmod exe #o555)))))
    ;; Публикуются только эти платформы; берём x86_64.
    (supported-systems '("x86_64-linux"))
    (home-page "https://claude.com/claude-code")
    (synopsis "Агентский CLI для программирования от Anthropic")
    (description
     "Claude Code — интерактивный агент, работающий в терминале: читает
и правит файлы, запускает команды, работает с git.  Распространяется
готовым бинарником; здесь он лишь переупакован под Guix — исполняемый
файл не пересобирается, у него правится только путь к ELF-загрузчику.")
    ;; Проприетарная лицензия, см. https://www.anthropic.com/legal/commercial-terms
    (license #f)))
