;;; Dev-VM под QEMU. Загрузка BIOS/GRUB с /dev/vda, каталог с конфигами
;;; проброшен с хоста по 9p.
;;;
;;; Применять:
;;;     sudo -i guix system reconfigure /mnt/guix-config/systems/vm.scm
;;;
;;; Собрать готовый образ, не трогая текущую систему:
;;;     guix system image -t qcow2 --image-size=20G systems/vm.scm

(add-to-load-path (dirname (current-filename)))
(use-modules (gnu) (base))

(make-system
 #:host-name "dyens"
 #:root-device (uuid "981499e3-df04-42f4-adfe-1145b86a5a13" 'ext4)
 #:root-type "ext4"
 #:swap-device (uuid "8cc62121-4969-469d-9f94-5fd10a0d36ad")
 #:bootloader-type grub-bootloader
 #:bootloader-targets (list "/dev/vda")

 ;; Вход по ключу. Раскомментируйте, положив свой публичный ключ
 ;; в files/keys/dyens.pub — см. files/keys/README.md.
 ;; #:ssh-authorized-keys `(("dyens" ,(local-file "../files/keys/dyens.pub")))
 ;;
 ;; И только ПОСЛЕ того, как вход по ключу проверен:
 ;; #:ssh-password-auth? #f

 #:extra-file-systems
 (list
  ;; Каталог с этим репозиторием, проброшенный с хоста.
  ;; Требует запуска qemu с (это делает run-vm.sh):
  ;;   -virtfs local,path=<repo>,mount_tag=guixcfg,security_model=none
  ;; Тег 9p играет роль имени устройства — UUID-ов тут нет.
  ;;
  ;; mount-may-fail? ОБЯЗАТЕЛЕН. Без него неудачное монтирование роняет
  ;; цель file-systems, от которой зависит user-processes, а от неё —
  ;; весь пользовательский стек. Результат: sshd есть, графики нет.
  (file-system
    (mount-point "/mnt/guix-config")
    (device "guixcfg")
    (type "9p")
    (options "trans=virtio,version=9p2000.L,msize=104857600")
    (mount-may-fail? #t)
    (check? #f)
    (create-mount-point? #t))

  ;; Секреты, отдельным приватным репозиторием с хоста.
  ;; Раскладываются по $HOME скриптом активации в home/dyens.scm.
  (file-system
    (mount-point "/mnt/guix-secrets")
    (device "guixsec")
    (type "9p")
    (options "trans=virtio,version=9p2000.L,msize=104857600")
    (mount-may-fail? #t)
    (check? #f)
    (create-mount-point? #t))))
