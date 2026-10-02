(add-to-load-path (dirname (dirname (current-filename))))
 (use-modules (home base))

(make-home
 #:repo "/home/dyens/vms/guix-config"
 #:homerec "guix home reconfigure -L /home/dyens/vms/guix-config  /home/dyens/vms/guix-config/home/fedora.scm")
