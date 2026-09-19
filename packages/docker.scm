;;; Docker Engine, compose и buildx — официальные статические бинарники.
;;;
;;; В Guix Docker застрял на 20.10 (2023) с compose v1 на Python и без buildx,
;;; а проектам нужны свежий Engine, `docker compose` v2+ (`!reset`/`!override`,
;;; profiles) и BuildKit (`RUN --mount=type=cache`, `--platform=$BUILDPLATFORM`).
;;; Собирать это из исходников в Guix — сотни Go-зависимостей. Поэтому, как
;;; с xray: релизные статические бинарники, версии зафиксированы хешами.
;;; Все бинарники статические (runc — static-pie), patchelf не нужен.
;;;
;;; Обновить: версия + хеш. Суммы публикуют compose (.sha256) и buildx
;;; (checksums.txt); для static-архивов Docker download.docker.com сумм не
;;; публикует — хеш фиксирует то, что скачано. `guix download` может
;;; спотыкаться на редиректах GitHub: тогда curl, сверка, `guix hash`.

(define-module (packages docker)
  #:use-module (gnu packages base)              ; tar
  #:use-module (gnu packages compression)       ; gzip
  #:use-module (guix build-system trivial)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:export (docker-engine
            docker-compose-plugin
            docker-buildx-plugin))

(define-public docker-engine
  (package
    (name "docker-engine")
    (version "29.8.1")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "https://download.docker.com/linux/static/stable/x86_64/docker-"
                           version ".tgz"))
       ;; sha256 (hex): d8db66739d2e28d4933786d73e918d9be643a67fbd835db1bf740d650a259e70
       (sha256
        (base32 "0w4y4l56a3blpyqmv0xxgyk47rlvin8kxmw66y9x8a1fkmrndnyq"))))
    (build-system trivial-build-system)
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      #~(begin
          (use-modules (guix build utils))
          (let ((bin (string-append #$output "/bin")))
            (setenv "PATH" (string-append #$(file-append gzip "/bin")))
            (invoke #$(file-append tar "/bin/tar") "xzf" #$source)
            (mkdir-p bin)
            ;; docker, dockerd, docker-proxy, docker-init, containerd,
            ;; containerd-shim-runc-v2, ctr, runc.
            (for-each (lambda (f)
                        (install-file f bin)
                        (chmod (string-append bin "/" (basename f)) #o555))
                      (find-files "docker"))))))
    (supported-systems '("x86_64-linux"))
    (home-page "https://www.docker.com/")
    (synopsis "Docker Engine: dockerd, containerd, runc и CLI (статическая сборка)")
    (description
     "Docker Engine из официального статического архива: демон dockerd,
containerd со shim, runc, docker-proxy, docker-init и клиент docker.")
    (license license:asl2.0)))

(define (cli-plugin plugin version url hash description)
  "Плагин docker CLI: один статический бинарник, ставится как bin/docker-PLUGIN.
Параметр не называется name: внутри `package' это имя поля записи."
  (package
    (name (string-append "docker-" plugin "-plugin"))
    (version version)
    (source (origin
              (method url-fetch)
              (uri url)
              (sha256 (base32 hash))))
    (build-system trivial-build-system)
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      #~(begin
          (use-modules (guix build utils))
          (let ((exe (string-append #$output "/bin/docker-" #$plugin)))
            (mkdir-p (dirname exe))
            (copy-file #$source exe)
            (chmod exe #o555)))))
    (supported-systems '("x86_64-linux"))
    (home-page (string-append "https://github.com/docker/" plugin))
    (synopsis description)
    (description (string-append description ". Статический бинарник релиза;
docker ищет плагины в ~/.docker/cli-plugins (см. home/docker.scm)."))
    (license license:asl2.0)))

(define-public docker-compose-plugin
  (cli-plugin "compose" "5.5.1"
              "https://github.com/docker/compose/releases/download/v5.5.1/docker-compose-linux-x86_64"
              ;; sha256 (hex, из .sha256 релиза):
              ;; db1889184726840f75c4f9c001048430d4f25b3be3cb084d3ddd762bc0aed576
              "0xnmmv02nxnx7m6hijz37ddz5m1hhh203h7rqishz1168wc8j66v"
              "Docker Compose v2+: `docker compose`"))

(define-public docker-buildx-plugin
  (cli-plugin "buildx" "0.37.1"
              "https://github.com/docker/buildx/releases/download/v0.37.1/buildx-v0.37.1.linux-amd64"
              ;; sha256 (hex, из checksums.txt релиза):
              ;; 9447199cdb435f25880548343c128a4b6650e8891ee598905d8d29d39a8e359b
              "16rmisdd6acdbn89ir8yi7l50rjbi893qd280n42aps3vff1jiwl"
              "Docker buildx: сборка через BuildKit"))
