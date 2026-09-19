;;; WireGuard-туннель из конфига wg-quick, который лежит в sops.
;;;
;;; Штатный wireguard-service-type Guix описывает пиров в самом конфиге
;;; системы — адрес сервера и ключи попали бы в стор и в git открытым
;;; текстом. Здесь весь конфиг wg-quick (с PrivateKey) — секрет sops.
;;;
;;; Секрет расшифровывает home-sops пользователя (home/wireguard.scm) — как
;;; конфиг Xray: в /run/user/<uid>/secrets/NAME.conf, тем же ~/.age-key.
;;; Ключа у root и системного sops не нужно. Цена — туннель поднимается
;;; после входа пользователя (до этого расшифровывать нечем).
;;;
;;; wg-quick нужен root, поэтому сам туннель — системный сервис. Он
;;; запускает отдельный процесс (а не выполняет wg-quick внутри shepherd,
;;; PID 1): тот ждёт появления конфига, делает `wg-quick up` и живёт до
;;; SIGTERM (`herd stop`), по которому делает `wg-quick down`.
;;;
;;; Имя интерфейса wg-quick берёт из имени файла: NAME.conf → интерфейс NAME.
;;; Строка DNS = … работает: wg-quick через resolvconf (openresolv в его
;;; обёртке) ставит эти серверы в /etc/resolv.conf на время туннеля — имена
;;; сети VPN разрешаются и на машине, и в контейнерах Docker.
;;; AllowedIPs = 0.0.0.0/0 недопустимо: весь трафик, включая ssh, уйдёт
;;; в туннель.

(define-module (systems wg-quick)
  #:use-module (gnu packages base)              ; coreutils (env, timeout)
  #:use-module (gnu packages vpn)               ; wireguard-tools
  #:use-module (gnu services)
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:export (wg-quick-services))

(define (wg-quick-program name user)
  (program-file
   (string-append "wg-quick-" name)
   #~(begin
       (define conf
         (or (getenv "WG_QUICK_CONF")         ; для проверки вне системы
             (string-append "/run/user/"
                            (number->string (passwd:uid (getpwnam #$user)))
                            "/secrets/" #$name ".conf")))

       (define (wg-quick action)
         ;; wg-quick обёрнут PATH'ом с ip/iptables/resolvconf, но без самого wg.
         (zero? (system* #$(file-append coreutils "/bin/timeout") "60"
                         #$(file-append coreutils "/bin/env")
                         (string-append "PATH=" #$(file-append wireguard-tools "/bin"))
                         #$(file-append wireguard-tools "/bin/wg-quick")
                         action conf)))

       (define (log fmt . args)
         (apply format #t (string-append "wg-quick-" #$name ": " fmt "~%") args)
         (force-output))

       (define up? #f)
       (sigaction SIGTERM
         (lambda _
           (when up? (wg-quick "down"))
           (primitive-exit 0)))

       ;; Сообщения в логе — латиницей: у процесса нет локали, кириллица
       ;; превращается в «???».
       ;; Конфиг появится, когда пользователь войдёт и home-sops его расшифрует.
       (log "waiting for ~a" conf)
       (let wait ()
         (unless (and (file-exists? conf) (> (stat:size (stat conf)) 0))
           (sleep 2)
           (wait)))

       ;; Интерфейс мог остаться от прошлого запуска (respawn) — иначе up упадёт.
       (when (file-exists? (string-append "/sys/class/net/" #$name))
         (wg-quick "down"))
       (unless (wg-quick "up")
         (log "wg-quick up failed, retry via respawn")
         (sleep 10)
         (exit 1))
       (set! up? #t)
       (log "tunnel is up")
       ;; Не (pause): Guile выполняет обработчик сигнала только в безопасной
       ;; точке, и из pause SIGTERM его так и не вызывал. sleep — вызывает.
       (let loop () (sleep 1) (loop)))))

(define* (wg-quick-services name #:key (user "dyens"))
  "Туннель NAME: конфиг wg-quick — секрет NAME.conf из home-sops пользователя
USER (/run/user/<uid>/secrets/NAME.conf)."
  (let ((provision (string->symbol (string-append "wg-" name))))
    (list
     (simple-service
      provision shepherd-root-service-type
      (list
       (shepherd-service
        (provision (list provision))
        (requirement '(networking))
        (documentation (string-append "WireGuard " name " (wg-quick), после входа "
                                      user "."))
        (start #~(make-forkexec-constructor
                  (list #$(wg-quick-program name user))
                  #:log-file #$(string-append "/var/log/wg-" name ".log")))
        (stop #~(make-kill-destructor))
        (respawn? #t)))))))
