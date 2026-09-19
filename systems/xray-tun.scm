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
  #:use-module (gnu packages linux)             ; iproute
  #:use-module (gnu services)
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:use-module (packages xray)
  #:export (xray-tun-service))

(define %interface "xray0")

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
            (let ((ip #$(file-append iproute "/sbin/ip")))
              (system* ip "link" "set" "dev" #$%interface "up")
              (for-each (lambda (dst)
                          (system* ip "route" "replace" dst "dev" #$%interface))
                        '#$destinations))
            pid)))
     ;; Маршруты исчезают вместе с интерфейсом, убирать их отдельно не нужно.
     (stop #~(make-kill-destructor))))))
