;;; Xray-клиент VPN — сервис home-shepherd.
;;;
;;; По умолчанию стартует timeweb: SOCKS5 на 127.0.0.1:10808 и VLESS/REALITY.
;;; Fornex лежит рядом отдельным сервисом, но сам не стартует: сначала
;;; `herd stop xray`, потом `herd start xray-fornex`.
;;;
;;; Конфиги с ключами и адресами серверов — секрет sops: files/secrets/xray.yaml,
;;; ключи "xray.json" (timeweb) и "xray-fornex.json" (содержимое — JSON-конфиг
;;; Xray целиком). Расшифровываются при старте home-shepherd в tmpfs
;;; $XDG_RUNTIME_DIR/secrets, оттуда их и читает Xray (без симлинка `path' — см.
;;; home-secret в home/base.scm).
;;;
;;; Кто пользуется SOCKS:
;;;   - программы с поддержкой прокси — напрямую (socks5://127.0.0.1:10808);
;;;   - всё остальное к выбранным адресам — через системный tun
;;;     (systems/xray-tun.scm, подключается в systems/<host>.scm).
;;;
;;; В конфиге обязателен ЯВНЫЙ TLS-отпечаток: "fingerprint": "hellochrome_131",
;;; а не "chrome" (тот переезжает вместе с версией ядра, и DPI это ловит) —
;;; см. README, «VPN (Xray)».
;;;
;;; Первый раз: создать секрет — см. README, «VPN».

(define-module (home xray)
  #:use-module (gnu home services)
  #:use-module (gnu home services shepherd)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (sops secrets)
  #:use-module (sops home services sops)
  #:use-module (packages xray)
  #:export (%xray-services))

(define xray.yaml
  (local-file "../files/secrets/xray.yaml" "xray.yaml"))

(define (xray-secret key)
  (sops-secret
   (key (list key))
   (file xray.yaml)
   (permissions #o400)))

(define* (xray-shepherd-service provision secret-file log-file documentation
                                #:key (auto-start? #t))
  (shepherd-service
   (provision (list provision))
   ;; Секрет расшифровывает home-sops-secrets (one-shot).
   (requirement '(home-sops-secrets))
   (documentation documentation)
   (auto-start? auto-start?)
   (start
    #~(make-forkexec-constructor
       (list #$(file-append xray "/bin/xray") "run" "-c"
             (string-append
              (or (getenv "XDG_RUNTIME_DIR")
                  (string-append "/run/user/"
                                 (number->string (getuid))))
              "/secrets/" #$secret-file))
       #:log-file (string-append
                   (or (getenv "XDG_STATE_HOME")
                       (string-append (getenv "HOME") "/.local/state"))
                   "/" #$log-file)
       ;; Где искать geoip.dat/geosite.dat (для правил маршрутизации
       ;; geoip:/geosite: в конфиге).
       #:environment-variables
       (cons (string-append "XRAY_LOCATION_ASSET="
                            #$(file-append xray "/share/xray"))
             (environ))))
   (stop #~(make-kill-destructor))))

(define %xray-services
  (list
   (simple-service 'xray-package home-profile-service-type (list xray))

   (simple-service 'xray-secrets home-sops-secrets-service-type
                   (list (xray-secret "xray.json")
                         (xray-secret "xray-fornex.json")))

   (simple-service 'xray home-shepherd-service-type
                   (list
                    (xray-shepherd-service
                     'xray
                     "xray.json"
                     "xray.log"
                     "Xray-клиент VPN timeweb: SOCKS5 на 127.0.0.1:10808.")
                    (xray-shepherd-service
                     'xray-fornex
                     "xray-fornex.json"
                     "xray-fornex.log"
                     "Xray-клиент VPN fornex: SOCKS5 на 127.0.0.1:10808. Запускать вручную вместо xray."
                     #:auto-start? #f)))))
