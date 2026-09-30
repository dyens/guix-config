;;; Прозрачный туннель для выбранных адресов: tun-интерфейс Xray + маршруты.
;;;
;;; Схема та же, что на хосте (xray + net.sh с tun2socks), только tun2socks
;;; не нужен — в Xray с 25.x есть встроенный tun-вход:
;;;
;;;   программа → маршрут на xray0 → Xray (этот сервис, root)
;;;             → SOCKS 127.0.0.1:10808 → Xray-клиент (home, пользователь)
;;;             → VLESS/REALITY → сервер
;;;
;;; Секретов здесь нет: ключи и адрес сервера знает только home-клиент
;;; (files/secrets/xray.yaml, см. home/base.scm). Этот экземпляр лишь
;;; перекладывает пакеты из xray0 в локальный SOCKS.
;;;
;;; tun в Xray только поднимает интерфейс, маршруты — забота ОС (см.
;;; proxy/tun/README.md в Xray-core). Поэтому после старта процесса сервис
;;; ждёт появления xray0 и добавляет `ip route` на каждый адрес из списка.
;;; Остальной трафик идёт как обычно — в том числе трафик к самому
;;; VPN-серверу, иначе была бы петля. Не добавляйте в список его адрес
;;; и не заворачивайте 0.0.0.0/0.
;;;
;;; Если home-клиент не запущен (пользователь не вошёл), адреса из списка
;;; просто недоступны; остальная сеть не страдает.

(define-module (systems xray-tun)
  #:use-module (gnu packages base)              ; glibc/getent
  #:use-module (gnu packages linux)             ; iproute
  #:use-module (gnu services)
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:use-module (packages xray)
  #:export (xray-tun-service))

(define %interface "xray0")

;; Собственный IPv4 интерфейса. Без него у xray0 только IPv6 link-local, и
;; ядро (7.1 на t1) не выбирает исходный адрес для маршрута через него:
;; connect() сразу падает с EINVAL, `ip route get` — «Invalid argument».
;; 198.18.0.0/15 — зарезервированный немаршрутизируемый диапазон, его
;; обычно и берут tun-прокси; /32 не добавляет своего маршрута.
(define %address "198.18.0.1/32")

(define (xray-tun-config socks-port)
  (plain-file "xray-tun.json"
              (string-append "{
  \"log\": {\"loglevel\": \"warning\"},
  \"inbounds\": [{
    \"port\": 0,
    \"protocol\": \"tun\",
    \"settings\": {\"name\": \"" %interface "\", \"MTU\": 1500}
  }],
  \"outbounds\": [{
    \"protocol\": \"socks\",
    \"settings\": {\"servers\": [{\"address\": \"127.0.0.1\", \"port\": "
                             (number->string socks-port) "}]}
  }]
}
")))

(define* (xray-tun-service destinations #:key (socks-port 10808))
  "Сервис: tun-интерфейс xray0 и маршруты на DESTINATIONS (адреса или
подсети) через SOCKS-прокси на 127.0.0.1:SOCKS-PORT."
  (simple-service
   'xray-tun shepherd-root-service-type
   (list
    (shepherd-service
     (provision '(xray-tun))
     (requirement '(networking))
     (documentation "Xray tun: выбранные адреса через локальный SOCKS.")
     (start
      #~(lambda _
          (let ((pid ((make-forkexec-constructor
                       (list #$(file-append xray "/bin/xray")
                             "run" "-c" #$(xray-tun-config socks-port))
                       #:log-file "/var/log/xray-tun.log"))))
            ;; Интерфейс появляется не сразу после fork — ждём до 10 с.
            (let wait ((n 0))
              (unless (or (file-exists? (string-append "/sys/class/net/" #$%interface))
                          (> n 100))
                (usleep 100000)
                (wait (+ n 1))))
            (let ((ip #$(file-append iproute "/sbin/ip"))
                  (getent #$(file-append glibc "/bin/getent"))
                  (open-input-pipe (@ (ice-9 popen) open-input-pipe))
                  (close-pipe (@ (ice-9 popen) close-pipe))
                  (read-line (@ (ice-9 rdelim) read-line))
                  (string-match (@ (ice-9 regex) string-match))
                  (match:substring (@ (ice-9 regex) match:substring)))
              (define (literal-route? dst)
                ;; IPv4 or IPv4/CIDR.  Domains are resolved below at service start.
                (string-match "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+(/[0-9]+)?$" dst))
              (define (first-field line)
                (match:substring (string-match "^[^[:space:]]+" line)))
              (define (resolved-routes dst)
                (if (literal-route? dst)
                    (list dst)
                    (let* ((port (open-input-pipe
                                   (string-append getent " ahostsv4 " dst))))
                      (let loop ((routes '()))
                        (let ((line (read-line port)))
                          (if (eof-object? line)
                              (begin
                                (close-pipe port)
                                (reverse routes))
                              (loop (cons (first-field line) routes))))))))
              (define (route-dst dst)
                (let ((routes (resolved-routes dst)))
                  (if (null? routes)
                      (format (current-error-port)
                              "xray-tun: no IPv4 routes resolved for ~a~%" dst)
                      (for-each (lambda (route)
                                  (system* ip "route" "replace" route
                                           "dev" #$%interface))
                                routes))))
              (system* ip "addr" "replace" #$%address "dev" #$%interface)
              (system* ip "link" "set" "dev" #$%interface "up")
              (for-each route-dst '#$destinations))
            pid)))
     ;; Маршруты исчезают вместе с интерфейсом, убирать их отдельно не нужно.
     (stop #~(make-kill-destructor))))))
