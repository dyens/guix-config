(add-to-load-path "/home/dyens/vms/guix-config")
(use-modules (home base)
             (gnu home services))

(make-home
 #:repo "/home/dyens/vms/guix-config"
 ;; The file already sets %load-path above. -L would also make Guix scan
 ;; this entire repository for package modules, including non-module configs.
 #:homerec "guix home reconfigure /home/dyens/vms/guix-config/home/fedora.scm"
 #:extra-services
 (list
  ;; Use Fedora's trust store, including locally installed corporate CAs.
  (simple-service 'fedora-system-ca
                  home-environment-variables-service-type
                  '(("SSL_CERT_FILE" . "/etc/ssl/certs/ca-certificates.crt")))))
