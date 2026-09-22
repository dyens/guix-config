;;; kubectl — официальный бинарник релиза Kubernetes.
;;;
;;; В Guix его нет: есть библиотеки k8s (kubernetes-apiserver,
;;; go-k8s-io-apimachinery и прочие), но самого CLI нет ни как `kubectl',
;;; ни как `kubernetes-cli'. Собирать из исходников — упаковать пол-экосистемы
;;; Go, которой в Guix тоже нет.
;;;
;;; Бинарник чистый Go и статически слинкован, проверено:
;;;
;;;     patchelf --print-interpreter kubectl
;;;     -> cannot find section '.interp'. The input file is most likely
;;;        statically linked
;;;
;;; Значит ни загрузчик из systems/fhs.scm, ни patchelf не нужны — как у
;;; packages/glab.scm и packages/xray.scm. Источник не архив, а сам файл,
;;; поэтому сборка сводится к copy-file.
;;;
;;; ПРО ВЕРСИЮ. Kubernetes допускает расхождение kubectl и кластера не
;;; больше чем на один минорный выпуск. Здесь стоит тогдашний stable; если
;;; кластер заметно старше, версию нужно понизить, а не брать свежую.
;;;
;;; Обновить:
;;;   1. curl -s https://dl.k8s.io/release/stable.txt   — или нужная версия;
;;;   2. version ниже;
;;;   3. сверить с официальной суммой: curl -s <url>.sha256
;;;   4. guix download <url> — вписать nix-base32 в sha256;
;;;   5. проверить: kubectl version --client.

(define-module (packages kubectl)
  #:use-module (guix build-system trivial)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:export (kubectl))

(define-public kubectl
  (package
    (name "kubectl")
    (version "1.37.0")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "https://dl.k8s.io/release/v" version
                           "/bin/linux/amd64/kubectl"))
       (file-name (string-append "kubectl-" version))
       ;; Сверено с https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubectl.sha256
       ;; 6129359f4e1f3848a5572ccb0b26cf28b8ca08cef38c95a765b2f64a2c961a2f
       (sha256
        (base32 "0bqsjqn4mxmjcnkrb37krq4cmf18rwk0pjrcayjlhf0z9sgkaab1"))))
    (build-system trivial-build-system)
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      #~(begin
          (use-modules (guix build utils))
          (let* ((bin  (string-append #$output "/bin"))
                 (dest (string-append bin "/kubectl")))
            (mkdir-p bin)
            (copy-file #$source dest)
            (chmod dest #o555)))))
    (supported-systems '("x86_64-linux"))
    (home-page "https://kubernetes.io/docs/reference/kubectl/")
    (synopsis "Клиент командной строки для Kubernetes")
    (description
     "@command{kubectl} — official command-line client for Kubernetes
clusters.  Здесь — статический бинарник официального релиза, без
пересборки.")
    (license license:asl2.0)))
