(add-to-load-path "/home/dyens/vms/guix-config")
(use-modules (home base))

(make-home
 #:repo "/home/dyens/vms/guix-config"
 ;; The file already sets %load-path above. -L would also make Guix scan
 ;; this entire repository for package modules, including non-module configs.
 #:homerec "guix home reconfigure /home/dyens/vms/guix-config/home/fedora.scm")
