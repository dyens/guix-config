;;; Xray-core — готовый статический бинарник из релиза на GitHub.
;;;
;;; Собирать из исходников в Guix — это упаковать десятки Go-зависимостей,
;;; которых в Guix нет. Релизный бинарник собран с CGO_ENABLED=0 и
;;; статически слинкован: ни загрузчик, ни библиотеки ему не нужны, так что
;;; в отличие от claude-code даже patchelf не требуется. Версия зафиксирована
;;; хешем архива.
;;;
;;; ВЕРСИЯ ПОДОБРАНА ПОД СЕТЬ, НЕ ОБНОВЛЯТЬ ВСЛЕПУЮ.
;;; Начиная с 25.7.26 клиент REALITY в сети провайдера t1 опознаётся и
;;; режется: первые 2-3 соединения проходят, дальше TCP до сервера
;;; устанавливается, но данные не идут (Claude Code отваливается по
;;; таймауту). 25.6.8 и старше работают. Проверено чередованием версий
;;; с паузами: блокировка залипает на несколько минут, поэтому мерить
;;; надо серией запросов и с перерывами — см. README, «VPN (Xray)».
;;;
;;; Обновить:
;;;   1. проверить новую версию по README (серия запросов через SOCKS);
;;;   2. version ниже;
;;;   3. сумма из Xray-linux-64.zip.dgst релиза (SHA2-256) — для сверки;
;;;   4. guix download <url>  (или curl + guix hash, если guix download
;;;      спотыкается на редиректе GitHub) — вписать nix-base32 в sha256.

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
    (version "25.6.8")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "https://github.com/XTLS/Xray-core/releases/download/v"
                           version "/Xray-linux-64.zip"))
       ;; SHA2-256 из Xray-linux-64.zip.dgst релиза:
       ;; 51bcd3304fdbd64b58048b056da005fbaa6c83577fc351cae34024760e111e4b
       (sha256
        (base32 "0jqy2477c920wg553hvzay1nrapv0nh6s1cb0ic4pmnv9wqd7g2i"))))
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
