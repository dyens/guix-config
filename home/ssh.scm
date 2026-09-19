;;; ssh-клиент: ~/.ssh/config и ключи из sops.
;;;
;;; Отступление от правила «приватная половина не покидает машину»
;;; (README, «Приватные ssh-ключи»): ключ для GitLab хранится в sops, чтобы
;;; пересоздание облачной VM не требовало выпускать и регистрировать новый.
;;; Ключ отдельный — только для GitLab, не тот, которым заходят на машины;
;;; отзыв — удалить его в GitLab.
;;;
;;; Секрет files/secrets/ssh.yaml, ключ "gitlab-ed25519" → home-sops
;;; расшифровывает в /run/user/<uid>/secrets/gitlab-ed25519 (права 400).
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
                          (key '("gitlab-ed25519"))
                          (file (local-file "../files/secrets/ssh.yaml" "ssh.yaml"))
                          (permissions #o400))))

   (service home-openssh-service-type
            (home-openssh-configuration
             (hosts
              (list (openssh-host
                     (name "gitlab.croc.ru")
                     (user "git")
                     (identity-file "/run/user/%i/secrets/gitlab-ed25519")
                     ;; Только этот ключ: иначе ssh перебирает все из агента
                     ;; и ~/.ssh/id_*, и GitLab может отбить по числу попыток.
                     (extra-content "  IdentitiesOnly yes\n"))))))))
