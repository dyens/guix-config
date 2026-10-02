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
              (list
               ;; Из старого ~/.ssh/config
               (openssh-host
                (name "github.com")
                (host-name "github.com")
                (user "git")
                (identity-file "~/.ssh/id_ed25519"))
               (openssh-host
                (name "gitlab.croc.ru")
                (host-name "gitlab.croc.ru")
                (user "git")
                (identity-file (identity-file-for "croc-gitlab"))
                ;; Только этот ключ: иначе ssh перебирает все из агента
                ;; и ~/.ssh/id_*, и GitLab может отбить по числу попыток.
                (extra-content "  IdentitiesOnly yes\n"))
               (openssh-host
                (name "gist.github.com")
                (host-name "gist.github.com")
                (user "git")
                (identity-file "~/.ssh/id_ed25519"))
               (openssh-host
                (name "github.com-qs")
                (host-name "github.com")
                (user "git")
                (identity-file "~/.ssh/quantusoft_git"))
               (openssh-host
                (name "git.service.t1-cloud.ru")
                (host-name "git.service.t1-cloud.ru")
                (user "git")
                (identity-file "~/.ssh/t1-cloud"))
               (openssh-host
                (name "git.int.nova-platform.io")
                (host-name "git.int.nova-platform.io")
                (user "git")
                (identity-file "~/.ssh/nova"))
               (openssh-host
                (name "gitlab-dev.t1.cloud")
                (host-name "gitlab-dev.t1.cloud")
                (user "git")
                (identity-file "~/.ssh/t1gitlab"))
               (openssh-host
                (name "gitlab-prod.t1.cloud")
                (host-name "gitlab-prod.t1.cloud")
                (user "git")
                (identity-file "~/.ssh/t1gitlab"))
               (openssh-host
                (name "c2-178-216-96-208.elastic.cloud.croc.ru")
                (host-name "c2-178-216-96-208.elastic.cloud.croc.ru")
                (identity-file "~/.ssh/3110runner"))
               (openssh-host
                (name "user-audit")
                (host-name "10.15.20.116")
                (user "user-audit")
                (identity-file "~/.ssh/user-audit"))
               (openssh-host
                (name "ai-ift-worker1")
                (host-name "10.13.241.9")
                (user "dyens")
                (identity-file "~/.ssh/ai_cluster2"))
               (openssh-host
                (name "ai-ift-master")
                (host-name "10.13.241.6")
                (user "dyens")
                (identity-file "~/.ssh/ai_cluster2"))
               (openssh-host
                (name "nova-andrey")
                (host-name "172.31.0.12")
                (user "ec2-user")
                (identity-file "~/.ssh/nova"))
               (openssh-host
                (name "ai-dev-master")
                (host-name "10.13.241.5")
                (user "dyens")
                (identity-file "~/.ssh/ai_cluster2"))
               (openssh-host
                (name "ai-dev-master-ai-3")
                (host-name "10.13.241.7")
                (user "dyens")
                (identity-file "~/.ssh/ai_cluster2"))
               (openssh-host
                (name "ai-dev-worker-ai-1")
                (host-name "10.13.241.8")
                (user "dyens")
                (identity-file "~/.ssh/ai_cluster2"))
               (openssh-host
                (name "dyvpn")
                (host-name "85.234.107.29")
                (user "dyens")
                (identity-file "~/.ssh/timeweb"))
               (openssh-host
                (name "d3kapustin")
                (host-name "10.128.0.54")
                (user "dyens")
                (identity-file "~/.ssh/t1-cloud")
                (extra-content "  ServerAliveInterval 30\n  ServerAliveCountMax 5\n"))
               (openssh-host
                (name "t1")
                (host-name "45.145.190.133")
                (user "dyens")
                (identity-file "~/.ssh/t1-cloud")
                (extra-content "  ServerAliveInterval 30\n  ServerAliveCountMax 5\n  SendEnv COLORTERM\n"))
               (openssh-host
                (name "mlhub-dev-sample")
                (host-name "185.159.111.104")
                (port 2222)
                (user "mluser@dev-sample"))
               (openssh-host
                (name "fornex")
                (host-name "81.85.77.10")
                (user "dyens")
                (identity-file "~/.ssh/fornex"))
               (openssh-host
                (name "guixvm")
                (host-name "127.0.0.1")
                (user "dyens")
                (port 10022)
                (identity-file "~/.ssh/guix"))

               ;; Дополнительный host, которого не было в backup-конфиге.
               (openssh-host
                (name "vm-gpu")
                (host-name "172.31.16.27")
                (user "ec2-user")
                (identity-file (identity-file-for "ruclaw-test-deploy"))
                ;; Только этот ключ: иначе ssh перебирает все из агента
                ;; и ~/.ssh/id_*, и GitLab может отбить по числу попыток.
                (extra-content "  IdentitiesOnly yes\n"))))))))
