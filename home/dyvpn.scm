;;; dyvpn helper scripts for host experiments.
;;;
;;; Installs:
;;;   ~/.local/bin/dyvpn-iptables [timeweb|fornex|/path/to/xray-client.json]
;;;   ~/.local/bin/dyvpn-stop-iptables
;;;   ~/.config/dyvpn/domains.txt
;;;
;;; dyvpn-iptables derives a temporary transparent Xray config from an ordinary
;;; SOCKS client config (like the sops secrets from home/xray.scm): it keeps the
;;; VLESS/REALITY outbound, adds dokodemo-door inbound + direct outbound, and
;;; routes domains from ~/.config/dyvpn/domains.txt through proxy using Xray
;;; sniffing. Only local TCP 80/443 is redirected by iptables.

(define-module (home dyvpn)
  #:use-module (gnu home services)
  #:use-module (gnu packages python)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (packages xray)
  #:export (%dyvpn-services))

(define dyvpn-files
  (local-file "../files/dyvpn" "dyvpn" #:recursive? #t))

(define dyvpn-domains
  (local-file "../files/xray-domains.txt" "dyvpn-domains.txt"))

(define %dyvpn-services
  (list
   ;; xray already comes from home/xray.scm, but keeping it here makes this
   ;; helper self-contained.  python3 is needed by dyvpn-iptables to transform
   ;; ordinary Xray client JSON/JSONC into a transparent config.
   (simple-service 'dyvpn-packages home-profile-service-type (list xray python))
   (simple-service 'dyvpn-files
                   home-files-service-type
                   `((".local/bin/dyvpn-iptables"
                      ,(file-append dyvpn-files "/dyvpn-iptables"))
                     (".local/bin/dyvpn-stop-iptables"
                      ,(file-append dyvpn-files "/dyvpn-stop-iptables"))))
   (simple-service 'dyvpn-config
                   home-xdg-configuration-files-service-type
                   `(("dyvpn/domains.txt" ,dyvpn-domains)))))
