;;; Xray-клиент VPN — сервис home-shepherd.
;;;
;;; Слушает SOCKS5 на 127.0.0.1:10808 и уводит трафик на VLESS/REALITY-сервер.
;;; Конфиг с ключами и адресом сервера — секрет sops: files/secrets/xray.yaml,
;;; ключ "xray.json" (содержимое — JSON-конфиг Xray целиком). Расшифровывается
;;; при старте home-shepherd в tmpfs и симлинкается в ~/.config/xray/config.json.
;;;
;;; Кто пользуется SOCKS:
;;;   - программы с поддержкой прокси — напрямую (socks5://127.0.0.1:10808);
;;;   - всё остальное к выбранным адресам — через системный tun
;;;     (systems/xray-tun.scm, подключается в systems/<host>.scm).
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

(define %config
  (string-append (getenv "HOME") "/.config/xray/config.json"))

(define %xray-services
  (list
   (simple-service 'xray-package home-profile-service-type (list xray))

   (simple-service 'xray-secret home-sops-secrets-service-type
                   (list (sops-secret
                          (key '("xray.json"))
                          (file (local-file "../files/secrets/xray.yaml" "xray.yaml"))
                          (permissions #o400)
                          (path %config))))

   (simple-service 'xray home-shepherd-service-type
                   (list
                    (shepherd-service
                     (provision '(xray))
                     ;; Секрет расшифровывает home-sops-secrets (one-shot).
                     (requirement '(home-sops-secrets))
                     (documentation "Xray-клиент VPN: SOCKS5 на 127.0.0.1:10808.")
                     (start
                      #~(make-forkexec-constructor
                         (list #$(file-append xray "/bin/xray") "run" "-c" #$%config)
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
