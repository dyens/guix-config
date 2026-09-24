;;; ssh-клиент: ~/.ssh/config и ключи из sops.
;;;
;;; Отступление от правила «приватная половина не покидает машину»
;;; (README, «Приватные ssh-ключи»): ключ для GitLab CROC хранится в sops,
;;; чтобы пересоздание облачной VM не требовало выпускать и регистрировать
;;; новый. Это тот же ключ, что на хосте (~/.ssh/crocgithub); им не
;;; заходят на машины, отзыв — удалить его в GitLab.
;;;
;;; СПИСКА КЛЮЧЕЙ ЗДЕСЬ НЕТ: расшифровываются все ключи files/secrets/ssh.yaml
;;; (см. home/secrets.scm). Добавили ключ в секрет — homerec, и он на
;;; машине. Пока список был в коде, он уже подвёл: ruclaw-test-deploy лежал
;;; в секрете и никуда не приезжал.
;;;
;;; А вот сопоставление «хост -> ключ» остаётся явным: какой ключ к какому
;;; хосту, из самого секрета не выводится.
;;;
;;; Ключ, названный "ssh/croc-gitlab", ляжет в
;;; /run/user/<uid>/secrets/ssh/croc-gitlab — подкаталог из имени ключа,
;;; см. home/secrets.scm. Путь для ~/.ssh/config строится из имени ключа,
;;; как оно записано в секрете, поэтому конфиг верен и до переименования
;;; ключей в ssh/<имя>, и после.
;;;
;;; Guix Home управляет только ~/.ssh/config (read-only); known_hosts и
;;; authorized_keys не трогает. Новый хост — openssh-host ниже и homerec.

(define-module (home ssh)
  #:use-module (gnu home services)
  #:use-module (gnu home services ssh)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (home secrets)
  #:use-module (srfi srfi-1)
  #:use-module (sops secrets)
  #:use-module (sops home services sops)
  #:export (%ssh-services))

(define ssh.yaml
  (local-file "../files/secrets/ssh.yaml" "ssh.yaml"))

(define (ssh-keys)
  (secret-keys (local-file-absolute-file-name ssh.yaml)))

(define (ssh-secret name)
  (sops-secret
   (key (list name))
   (file ssh.yaml)
   (permissions #o400)))

(define (identity-file-for suffix)
  "Путь к расшифрованному ключу, имя которого кончается на SUFFIX.
%i ssh подставляет сам, симлинки ему не нужны."
  (let ((name (find (lambda (k) (string-suffix? suffix k)) (ssh-keys))))
    (unless name
      (error "нет такого ключа в files/secrets/ssh.yaml:" suffix))
    (string-append "/run/user/%i/secrets/" name)))

(define %ssh-services
  (list
   (simple-service 'ssh-secrets home-sops-secrets-service-type
                   (map ssh-secret (ssh-keys)))

   (service home-openssh-service-type
            (home-openssh-configuration
             (hosts
              (list (openssh-host
                     (name "gitlab.croc.ru")
                     (user "git")
                     (identity-file (identity-file-for "croc-gitlab"))
                     ;; Только этот ключ: иначе ssh перебирает все из агента
                     ;; и ~/.ssh/id_*, и GitLab может отбить по числу попыток.
                     (extra-content "  IdentitiesOnly yes\n"))))))))
