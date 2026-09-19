;;; WireGuard-туннель из конфига wg-quick, который лежит в sops.
;;;
;;; Штатный wireguard-service-type Guix описывает пиров в самом конфиге
;;; системы — адрес сервера и ключи попали бы в стор и в git открытым
;;; текстом. Здесь весь конфиг wg-quick (с PrivateKey) — секрет sops,
;;; его на загрузке расшифровывает системный sops-guix в /run/secrets,
;;; а сервис делает `wg-quick up`/`down`.
;;;
;;; Имя интерфейса wg-quick берёт из имени файла: ключ "ruclaw.conf" →
;;; /run/secrets/ruclaw.conf → интерфейс ruclaw.
;;;
;;; В конфиге НЕ должно быть строки DNS = … (wg-quick перепишет
;;; /etc/resolv.conf) и AllowedIPs = 0.0.0.0/0 (весь трафик, включая ssh,
;;; уйдёт в туннель). Имена внутри VPN — через /etc/hosts, параметр HOSTS.
;;;
;;; Системному sops нужен age-ключ root: /root/.config/sops/age/keys.txt
;;; (см. README, «WireGuard»).

(define-module (systems wg-quick)
  #:use-module (gnu packages base)              ; coreutils (env)
  #:use-module (gnu packages vpn)               ; wireguard-tools
  #:use-module (gnu services)
  #:use-module (gnu services base)              ; hosts-service-type, host
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:use-module (sops secrets)
  #:use-module (sops services sops)
  #:export (wg-quick-services))

(define* (wg-quick-services name secrets-file #:key (hosts '()))
  "Туннель NAME: конфиг wg-quick — ключ \"NAME.conf\" в SECRETS-FILE (sops).
HOSTS — список (адрес . имя) для /etc/hosts."
  (let ((conf (string-append "/run/secrets/" name ".conf"))
        (provision (string->symbol (string-append "wg-" name))))
    (append
     (list
      (simple-service (symbol-append provision '-secret) sops-secrets-service-type
                      (list (sops-secret
                             (key (list (string-append name ".conf")))
                             (file secrets-file)
                             (user "root")
                             (group "root")
                             (permissions #o400))))

      (simple-service
       provision shepherd-root-service-type
       (list
        (shepherd-service
         (provision (list provision))
         (requirement '(sops-secrets networking))
         (documentation (string-append "WireGuard " name " (wg-quick)."))
         (start
          #~(lambda _
              ;; wg-quick обёрнут PATH'ом с ip/iptables, но без самого wg.
              ;; timeout: start выполняется в shepherd (PID 1) — он же запускает
              ;; sshd на каждое соединение и login на консоли. Зависший
              ;; wg-quick не должен держать его бесконечно.
              (zero? (system* #$(file-append coreutils "/bin/timeout") "30"
                              #$(file-append coreutils "/bin/env")
                              (string-append "PATH=" #$(file-append wireguard-tools "/bin"))
                              #$(file-append wireguard-tools "/bin/wg-quick")
                              "up" #$conf))))
         (stop
          #~(lambda _
              (system* #$(file-append coreutils "/bin/timeout") "30"
                       #$(file-append coreutils "/bin/env")
                       (string-append "PATH=" #$(file-append wireguard-tools "/bin"))
                       #$(file-append wireguard-tools "/bin/wg-quick")
                       "down" #$conf)
              #f))
         (respawn? #f)))))
     (if (null? hosts)
         '()
         (list (simple-service (symbol-append provision '-hosts) hosts-service-type
                               (map (lambda (h) (host (car h) (cdr h))) hosts)))))))
