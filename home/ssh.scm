;;; ssh-клиент: ~/.ssh/config и ключи из sops.
;;;
;;; Отступление от правила «приватная половина не покидает машину»
;;; (README, «Приватные ssh-ключи»): ключ для GitLab CROC хранится в sops,
;;; чтобы пересоздание облачной VM не требовало выпускать и регистрировать
;;; новый. Это тот же ключ, что на хосте (~/.ssh/crocgithub); им не
;;; заходят на машины, отзыв — удалить его в GitLab.
;;;
;;; Секрет files/secrets/ssh.yaml, ключ "croc-gitlab" → home-sops
;;; расшифровывает в /run/user/<uid>/secrets/croc-gitlab (права 400).
;;; В ~/.ssh/config путь через %i (uid) — он у ssh свой, без симлинков.
;;;
;;; Guix Home управляет только ~/.ssh/config (read-only); known_hosts и
;;; authorized_keys не трогает. Новый хост — openssh-host ниже и homerec.

(define-module (home ssh)
  #:use-module (gnu home services)
  #:use-module (gnu home services ssh)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (sops secrets)
  #:use-module (sops home services sops)
  #:export (%ssh-services))

(define %ssh-services
  (list
   (simple-service 'ssh-secrets home-sops-secrets-service-type
                   (list (sops-secret
                          (key '("croc-gitlab"))
                          (file (local-file "../files/secrets/ssh.yaml" "ssh.yaml"))
                          (permissions #o400))))

   (service home-openssh-service-type
            (home-openssh-configuration
             (hosts
              (list (openssh-host
                     (name "gitlab.croc.ru")
                     (user "git")
                     (identity-file "/run/user/%i/secrets/croc-gitlab")
                     ;; Только этот ключ: иначе ssh перебирает все из агента
                     ;; и ~/.ssh/id_*, и GitLab может отбить по числу попыток.
                     (extra-content "  IdentitiesOnly yes\n"))))))))
