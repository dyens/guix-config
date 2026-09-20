;;; Xray-core — готовый статический бинарник из релиза на GitHub.
;;;
;;; Собирать из исходников в Guix — это упаковать десятки Go-зависимостей,
;;; которых в Guix нет. Релизный бинарник собран с CGO_ENABLED=0 и
;;; статически слинкован: ни загрузчик, ни библиотеки ему не нужны, так что
;;; в отличие от claude-code даже patchelf не требуется. Версия зафиксирована
;;; хешем архива.
;;;
;;; ВАЖНО: версия ядра и TLS-отпечаток связаны. С 25.7.26 клиента резал DPI
;;; провайдера t1 — но виновата не версия, а отпечаток: в конфиге стояло
;;; "fingerprint": "chrome", это псевдоним HelloChrome_Auto, который при
;;; каждом обновлении ядра переезжает на новый профиль uTLS. В конфиге
;;; (секрет files/secrets/xray.yaml) должен стоять ЯВНЫЙ профиль, сейчас
;;; hellochrome_131. Подробности и таблица JA4 — README, «VPN (Xray)».
;;;
;;; Обновить:
;;;   1. version ниже;
;;;   2. сумма из Xray-linux-64.zip.dgst релиза (SHA2-256) — для сверки;
;;;   3. guix download <url>  (или curl + guix hash, если guix download
;;;      спотыкается на редиректе GitHub) — вписать nix-base32 в sha256;
;;;   4. проверить серией запросов (README): если начало резать — дело
;;;      скорее в отпечатке, чем в версии.

(define-module (packages xray)
  #:use-module (gnu packages compression)       ; unzip
  #:use-module (guix build-system trivial)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:export (xray))

(define-public xray
  (package
    (name "xray")
    (version "26.3.27")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "https://github.com/XTLS/Xray-core/releases/download/v"
                           version "/Xray-linux-64.zip"))
       ;; SHA2-256 из Xray-linux-64.zip.dgst релиза:
       ;; 23cd9af937744d97776ee35ecad4972cf4b2109d1e0fe6be9930467608f7c8ae
       (sha256
        (base32 "1bn8yw47ciihk6zfc3qykl8b5x1cjzaclpp3drvrfkbl6zwrmk93"))))
    (build-system trivial-build-system)
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      #~(begin
          (use-modules (guix build utils))
          (let ((bin   (string-append #$output "/bin"))
                (share (string-append #$output "/share/xray")))
            (mkdir-p bin)
            (mkdir-p share)
            (invoke #$(file-append unzip "/bin/unzip") "-q" #$source "-d" "xray")
            (install-file "xray/xray" bin)
            (chmod (string-append bin "/xray") #o555)
            ;; Базы для маршрутизации по geoip:/geosite: в конфиге. Xray ищет
            ;; их по XRAY_LOCATION_ASSET — его выставляют сервисы.
            (for-each (lambda (f) (install-file (string-append "xray/" f) share))
                      '("geoip.dat" "geosite.dat"))))))
    (supported-systems '("x86_64-linux"))
    (home-page "https://github.com/XTLS/Xray-core")
    (synopsis "Прокси-платформа Xray (VLESS, REALITY, tun, …)")
    (description
     "Xray-core — прокси-платформа, развитие v2ray: протоколы VLESS, VMess,
Trojan, Shadowsocks, транспорт REALITY и XTLS, входы SOCKS/HTTP и tun.
Здесь — официальный статический бинарник релиза, без пересборки.")
    (license license:mpl2.0)))
