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
;;; (`sops files/secrets/kube.yaml`) и сделать homerec, правок здесь не
;;; нужно.
;;;
;;; Цикл по именам тут законен, в отличие от home/claude.scm: local-file
;;; один и тот же на все секреты, а меняются только строки key и path.
;;;
;;; Почему поле `path' — хотя в home/base.scm написано, что оно ломается
;;; при повторном homerec. Тот комментарий устарел: в нынешнем sops-guix
;;; активация сначала зовёт sops-secret-cleanup, и только потом
;;; sops-secret-create (sops/activation.scm), а cleanup ведёт учёт ссылок
;;; в каталоге .extra-links и снимает прежний симлинк перед созданием
;;; нового. То есть path идемпотентен.
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

;; Абсолютный путь обязателен: `~' в поле path не раскрывается. Второе и
;; последнее место в репозитории, где имя пользователя прибито гвоздями
;; (первое — CLAUDE_ENV_FILE в files/claude/settings.json).
(define %kube-directory "/home/dyens/k8s")

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
  (sops-secret
   (key (list name))
   (file kube.yaml)
   (permissions #o400)
   (path (string-append %kube-directory "/" name ".yaml"))))

(define %kube-secrets
  (list
   ;; Каталог должен существовать заранее: sops-guix создаёт родителя
   ;; только для своих служебных ссылок, а для path зовёт голый symlink
   ;; и упал бы с ENOENT. Пустой .keep гарантирует ~/k8s.
   (simple-service 'kube-directory home-files-service-type
                   `(("k8s/.keep" ,(plain-file "kube-keep" ""))))

   (simple-service 'kube-secrets home-sops-secrets-service-type
                   (map kubeconfig-secret (kubeconfig-names)))))
