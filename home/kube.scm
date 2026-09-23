;;; Kubeconfig'и кластеров: files/secrets/kube.yaml -> ~/k8s/<кластер>.yaml.
;;;
;;; Переключение — руками, симлинком:
;;;
;;;     ln -sf ~/k8s/<кластер>.yaml ~/.kube/config
;;;
;;; Имена файлов НЕ прописаны здесь списком: они читаются из самого
;;; kube.yaml. В sops-файле шифруются только ЗНАЧЕНИЯ, верхнеуровневые
;;; ключи остаются открытым текстом — поэтому перечислить кластеры можно,
;;; не имея ключа расшифровки. Добавить кластер = добавить ключ в секрет
;;; (`sops files/secrets/kube.yaml') и сделать homerec, правок здесь не
;;; нужно.
;;;
;;; Цикл по именам тут законен, в отличие от home/claude.scm: local-file
;;; один и тот же на все секреты, меняется только строка key.
;;;
;;; ПОЧЕМУ НЕ ПОЛЕ `path' У SOPS-SECRET, хотя оно ровно для этого.
;;;
;;; Оно работает в пределах одной загрузки и ломается после следующей.
;;; sops ведёт учёт своих ссылок в каталоге .extra-links ВНУТРИ каталога
;;; секретов, то есть в tmpfs /run/user/<uid>/, а сами ссылки кладёт в
;;; $HOME. Перезагрузка стирает tmpfs: учёт пропадает, ссылки в ~/k8s
;;; остаются. Дальше cleanup их не находит, а create падает на
;;;
;;;     In procedure symlink: File exists
;;;
;;; и падает уже навсегда. А так как от home-sops-secrets зависит xray,
;;; вместе с ним ложится и VPN. Проверено на t1 ценой лежащего VPN.
;;;
;;; Поэтому ссылки создаём сами, в активации, идемпотентно: сначала
;;; удалить, потом создать. Цель ссылки — фиксированный путь, от наличия
;;; расшифрованного файла она не зависит и спокойно висит битой до старта
;;; home-shepherd. Заодно ушёл прибитый гвоздями /home/dyens: активация
;;; берёт $HOME и getuid.
;;;
;;; Сам открытый текст лежит в tmpfs (/run/user/<uid>/secrets/), а в ~/k8s
;;; попадают симлинки на него. После перезагрузки до старта home-shepherd
;;; ссылки висят битыми — это норма, лечится `herd restart home-sops-secrets'.
;;;
;;; Права 0400, поэтому `kubectl config use-context' по такому файлу не
;;; отработает: он пишет в kubeconfig. При переключении целым файлом это и
;;; не нужно, но знать стоит.

(define-module (home kube)
  #:use-module (gnu home services)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 regex)
  #:use-module (sops secrets)
  #:use-module (sops home services sops)
  #:export (%kube-secrets))

(define %kube-secrets-file "files/secrets/kube.yaml")

(define kube.yaml
  (local-file "../files/secrets/kube.yaml" "kube.yaml"))

(define (kubeconfig-names)
  "Имена кластеров — верхнеуровневые ключи файла секретов, кроме
служебного блока sops."
  (let ((file (search-path %load-path %kube-secrets-file)))
    (unless file
      (error "не нашёл в %load-path:" %kube-secrets-file))
    (let ((names
           (call-with-input-file file
             (lambda (port)
               (let loop ((names '()))
                 (let ((line (read-line port)))
                   (if (eof-object? line)
                       (reverse names)
                       (let ((m (string-match "^([^ \t#][^:]*):" line)))
                         (loop (if (and m
                                        (not (string=? (match:substring m 1)
                                                       "sops")))
                                   (cons (match:substring m 1) names)
                                   names))))))))))
      ;; Падать громко. Пустой список означал бы, что секретов просто не
      ;; будет создано, и узнали бы мы об этом в лучшем случае при первом
      ;; kubectl. Так уже вышло однажды с systems/base.scm: правка молча
      ;; не влияла ни на что (см. «Грабли»).
      (when (null? names)
        (error "не нашёл ни одного кластера в" file))
      names)))

(define (kubeconfig-secret name)
  ;; Без поля `path' — см. преамбулу. Файл появляется в
  ;; /run/user/<uid>/secrets/<имя>, ссылку на него делаем сами.
  (sops-secret
   (key (list name))
   (file kube.yaml)
   (permissions #o400)))

(define %kube-secrets
  (let ((names (kubeconfig-names)))
    (list
     ;; Ссылки ~/k8s/<кластер>.yaml -> /run/user/<uid>/secrets/<кластер>.
     ;; Сначала удаляем, потом создаём: активация должна проходить сколько
     ;; угодно раз подряд. delete-file на несуществующем бросает исключение,
     ;; на битой ссылке — работает, поэтому просто ловим и игнорируем.
     (simple-service
      'kube-links home-activation-service-type
      #~(let ((dir (string-append (getenv "HOME") "/k8s"))
              (secrets (string-append "/run/user/"
                                      (number->string (getuid))
                                      "/secrets")))
          (unless (file-exists? dir)
            (mkdir dir #o755))
          (for-each
           (lambda (name)
             (let ((link (string-append dir "/" name ".yaml"))
                   (target (string-append secrets "/" name)))
               (catch #t
                 (lambda () (delete-file link))
                 (lambda _ #t))
               (symlink target link)))
           (list #$@names))))

     (simple-service 'kube-secrets home-sops-secrets-service-type
                     (map kubeconfig-secret names)))))
