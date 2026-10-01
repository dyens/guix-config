;;; dyvpn helper scripts: transparent Xray via iptables.
;;;
;;; Installs:
;;;   ~/.local/bin/dyvpn-iptables [timeweb|fornex|/path/to/xray-client.json]
;;;   ~/.local/bin/dyvpn-stop-iptables
;;;   ~/.config/dyvpn/domains.txt
;;;
;;; dyvpn-iptables derives a temporary transparent Xray config from an ordinary
;;; SOCKS client config (xray.json/xray-fornex.json from sops): it keeps the
;;; VLESS/REALITY outbound, adds dokodemo-door inbound + direct outbound, and
;;; routes domains from ~/.config/dyvpn/domains.txt through proxy using Xray
;;; sniffing. Only local TCP 80/443 is redirected by iptables.

(define-module (home dyvpn)
  #:use-module (gnu home services)
  #:use-module (gnu packages python)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (sops secrets)
  #:use-module (sops home services sops)
  #:use-module (packages xray)
  #:export (%dyvpn-services))

(define dyvpn-files
  (local-file "../files/dyvpn" "dyvpn" #:recursive? #t))

(define dyvpn-domains
  (local-file "../files/xray-domains.txt" "dyvpn-domains.txt"))

(define xray.yaml
  (local-file "../files/secrets/xray.yaml" "xray.yaml"))

(define (xray-secret key)
  (sops-secret
   (key (list key))
   (file xray.yaml)
   (permissions #o400)))

(define %dyvpn-services
  (list
   ;; python3 is needed by dyvpn-iptables to transform ordinary Xray client
   ;; JSON/JSONC into a transparent config.
   (simple-service 'dyvpn-packages home-profile-service-type (list xray python))
   (simple-service 'dyvpn-secrets home-sops-secrets-service-type
                   (list (xray-secret "xray.json")
                         (xray-secret "xray-fornex.json")))
   (simple-service 'dyvpn-files
                   home-files-service-type
                   `((".local/bin/dyvpn-iptables"
                      ,(file-append dyvpn-files "/dyvpn-iptables"))
                     (".local/bin/dyvpn-stop-iptables"
                      ,(file-append dyvpn-files "/dyvpn-stop-iptables"))))
   (simple-service 'dyvpn-config
                   home-xdg-configuration-files-service-type
                   `(("dyvpn/domains.txt" ,dyvpn-domains)))))
