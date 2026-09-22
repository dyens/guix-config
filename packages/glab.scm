;;; glab — GitLab CLI, готовый статический бинарник из релиза.
;;;
;;; В Guix его нет вовсе: ни как `glab', ни как `gitlab-cli'. Собирать из
;;; исходников — упаковать полсотни Go-зависимостей, которых в Guix тоже
;;; нет. Релизный бинарник чистый Go, проверено:
;;;
;;;     patchelf --print-interpreter bin/glab
;;;     -> cannot find section '.interp'. The input file is most likely
;;;        statically linked
;;;
;;; То есть ни загрузчик, ни библиотеки ему не нужны, и, в отличие от
;;; claude-code, patchelf не требуется. К /lib64 из systems/fhs.scm это
;;; отношения не имеет — статическому бинарнику он ни к чему.
;;;
;;; Нужен для слэш-команды /review (files/claude/commands/review.md),
;;; GitHub-половину которой закрывает github-cli из Guix.
;;;
;;; Обновить:
;;;   1. посмотреть последний тег:
;;;      curl -s "https://gitlab.com/api/v4/projects/34675721/releases?per_page=1"
;;;   2. version ниже;
;;;   3. guix download <url> — вписать nix-base32 в sha256;
;;;   4. проверить: glab --version.

(define-module (packages glab)
  #:use-module (gnu packages base)              ; tar
  #:use-module (gnu packages compression)       ; gzip
  #:use-module (guix build-system trivial)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:export (glab))

(define-public glab
  (package
    (name "glab")
    (version "1.118.0")
    (source
     (origin
       (method url-fetch)
       ;; Ассеты релиза лежат в generic-пакетах проекта, а не в /releases/.
       (uri (string-append
             "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli"
             "/packages/generic/glab/" version
             "/glab_" version "_linux_amd64.tar.gz"))
       (sha256
        (base32 "0ca9aawl64z2c0v8i4g9cdpxqigk8dxym68n0g821axncbdjsy7k"))))
    (build-system trivial-build-system)
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      #~(begin
          (use-modules (guix build utils))
          (let ((bin (string-append #$output "/bin")))
            (mkdir-p bin)
            ;; tar сам gzip не зовёт: путь к нему задаём явно, PATH внутри
            ;; сборки пуст.
            (invoke #$(file-append tar "/bin/tar") "xf" #$source
                    "--use-compress-program"
                    #$(file-append gzip "/bin/gzip"))
            (install-file "bin/glab" bin)
            (chmod (string-append bin "/glab") #o555)))))
    (supported-systems '("x86_64-linux"))
    (home-page "https://gitlab.com/gitlab-org/cli")
    (synopsis "GitLab CLI: merge requests, pipelines, issues из терминала")
    (description
     "@command{glab} — официальный клиент GitLab для терминала: merge
requests, issues, pipelines, релизы, сниппеты.  Здесь — статический
бинарник официального релиза, без пересборки.")
    (license license:expat)))
