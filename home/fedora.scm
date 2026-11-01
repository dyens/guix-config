(add-to-load-path "/home/dyens/vms/guix-config")
(use-modules (home base))

(make-home
 #:repo "/home/dyens/vms/guix-config"
 #:homerec "guix home reconfigure -L /home/dyens/vms/guix-config  /home/dyens/vms/guix-config/home/fedora.scm")
