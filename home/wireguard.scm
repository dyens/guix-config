;;; Секреты WireGuard для home-sops — как конфиг Xray (home/xray.scm).
;;;
;;; Конфиг wg-quick проектной сети ruclaw (files/secrets/wg-ruclaw.yaml,
;;; ключ "ruclaw.conf") расшифровывается в /run/user/<uid>/secrets/ruclaw.conf.
;;; Поднимает туннель системный сервис (systems/wg-quick.scm) — ему нужен root.

(define-module (home wireguard)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (sops secrets)
  #:use-module (sops home services sops)
  #:export (%wireguard-secrets))

(define %wireguard-secrets
  (list (simple-service 'wg-ruclaw-secret home-sops-secrets-service-type
                        (list (sops-secret
                               (key '("ruclaw.conf"))
                               (file (local-file "../files/secrets/wg-ruclaw.yaml"
                                                 "wg-ruclaw.yaml"))
                               (permissions #o400))))))
