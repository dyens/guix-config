;;; Xray-клиент VPN — сервис home-shepherd.
;;;
;;; Слушает SOCKS5 на 127.0.0.1:10808 и уводит трафик на VLESS/REALITY-сервер.
;;; Конфиг с ключами и адресом сервера — секрет sops: files/secrets/xray.yaml,
;;; ключ "xray.json" (содержимое — JSON-конфиг Xray целиком). Расшифровывается
;;; при старте home-shepherd в tmpfs $XDG_RUNTIME_DIR/secrets/xray.json, оттуда
;;; его и читает Xray (без симлинка `path' — см. home-secret в home/base.scm).
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

(define %xray-services
  (list
   (simple-service 'xray-package home-profile-service-type (list xray))

   (simple-service 'xray-secret home-sops-secrets-service-type
                   (list (sops-secret
                          (key '("xray.json"))
                          (file (local-file "../files/secrets/xray.yaml" "xray.yaml"))
                          (permissions #o400))))

   (simple-service 'xray home-shepherd-service-type
                   (list
                    (shepherd-service
                     (provision '(xray))
                     ;; Секрет расшифровывает home-sops-secrets (one-shot).
                     (requirement '(home-sops-secrets))
                     (documentation "Xray-клиент VPN: SOCKS5 на 127.0.0.1:10808.")
                     (start
                      #~(make-forkexec-constructor
                         (list #$(file-append xray "/bin/xray") "run" "-c"
                               (string-append
                                (or (getenv "XDG_RUNTIME_DIR")
                                    (string-append "/run/user/"
                                                   (number->string (getuid))))
                                "/secrets/xray.json"))
                         #:log-file (string-append
                                     (or (getenv "XDG_STATE_HOME")
                                         (string-append (getenv "HOME") "/.local/state"))
                                     "/xray.log")
                         ;; Где искать geoip.dat/geosite.dat (для правил
                         ;; маршрутизации geoip:/geosite: в конфиге).
                         #:environment-variables
                         (cons (string-append "XRAY_LOCATION_ASSET="
                                              #$(file-append xray "/share/xray"))
                               (environ))))
                     (stop #~(make-kill-destructor)))))))
