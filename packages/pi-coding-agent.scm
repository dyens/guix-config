;;; Pi coding agent — готовый standalone-бинарник из GitHub Releases.
;;;
;;; Почему не npm-пакет:
;;;
;;;   * npm-пакет тянет дерево node_modules и требует Node.js >= 22.19;
;;;   * standalone-релиз уже собран авторами в один ELF-бинарник;
;;;   * версия фиксируется хешем архива, как у остальных бинарных пакетов.
;;;
;;; Бинарник собран под FHS и ищет /lib64/ld-linux-x86-64.so.2. В наших
;;; системах этот путь даёт systems/fhs.scm; сам ELF не патчим, потому что
;;; Bun-compiled executable после patchelf падает при старте.

(define-module (packages pi-coding-agent)
  #:use-module (guix build-system gnu)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:export (pi-coding-agent))

(define-public pi-coding-agent
  (package
    (name "pi-coding-agent")
    (version "0.87.1")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "https://github.com/earendil-works/pi/releases/download/v"
                           version "/pi-linux-x64.tar.gz"))
       (sha256
        (base32 "0k3n15cpa2pasiwc5c1hww8cqnr5c569j7cqdc09l12h5pb8vmw0"))))
    (build-system gnu-build-system)
    (arguments
     (list
      #:modules '((guix build gnu-build-system)
                  (guix build utils))
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          (delete 'build)
          (delete 'check)
          ;; Bun-compiled executable from the release is already a finished
          ;; artifact; stripping or patchelf'ing it makes it crash at startup.
          (delete 'strip)
          ;; It intentionally keeps the upstream /lib64 interpreter; our
          ;; systems/base.scm provides that FHS loader path.
          (delete 'validate-runpath)
          (replace 'install
            (lambda* (#:key outputs #:allow-other-keys)
              (let* ((out (assoc-ref outputs "out"))
                     (bin (string-append out "/bin"))
                     (share (string-append out "/share/pi-coding-agent"))
                     (exe (string-append share "/pi")))
                (mkdir-p share)
                (copy-recursively "." share)
                (chmod exe #o755)
                (mkdir-p bin)
                (symlink exe (string-append bin "/pi"))))))))
    (supported-systems '("x86_64-linux"))
    (home-page "https://pi.dev")
    (synopsis "Агентский CLI для программирования Pi")
    (description
     "Pi coding agent — интерактивный агент для терминала: читает и правит
файлы, запускает команды, ведёт сессии и поддерживает расширения.  Здесь
упакован официальный standalone-бинарник linux-x64; исполняемый файл не
пересобирается и не патчится.")
    (license license:expat)))
