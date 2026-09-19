;;; MTU внешнего интерфейса.
;;;
;;; В облаке сеть VM часто оверлейная (VXLAN/GENEVE), и полноразмерный пакет
;;; 1500 в неё не проходит. DHCP при этом может не прислать опцию 26
;;; (interface MTU), и интерфейс остаётся с 1500: короткие пакеты ходят,
;;; большие молча теряются. Симптом на t1 был такой: TCP до VPN-сервера
;;; установлен (ESTAB), но данные висят неотправленными, а запросы
;;; Claude Code отваливаются по таймауту.
;;;
;;; dhcpcd-service-type такого поля не имеет, поэтому отдельный one-shot:
;;; после networking выставляет MTU через ip link.

(define-module (systems net-mtu)
  #:use-module (gnu packages linux)             ; iproute
  #:use-module (gnu services)
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:export (interface-mtu-service))

(define (interface-mtu-service interface mtu)
  "One-shot: выставить MTU интерфейса INTERFACE в MTU после поднятия сети."
  (simple-service
   (string->symbol (string-append "mtu-" interface))
   shepherd-root-service-type
   (list
    (shepherd-service
     (provision (list (string->symbol (string-append "mtu-" interface))))
     (requirement '(networking))
     (one-shot? #t)
     (documentation (string-append "MTU " interface " = " (number->string mtu) "."))
     (start
      #~(lambda _
          (zero? (system* #$(file-append iproute "/sbin/ip")
                          "link" "set" "dev" #$interface
                          "mtu" #$(number->string mtu)))))))))
