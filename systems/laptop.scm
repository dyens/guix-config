;;; ЗАГОТОВКА для физической машины с UEFI.
;;;
;;; ВНИМАНИЕ: UUID-ы ниже — нули-заглушки. Пока их не заменить,
;;; `guix system reconfigure` упадёт на проверке файловых систем.
;;; Это сделано намеренно: лучше громкая ошибка, чем незагружающаяся
;;; система.
;;;
;;; Как заполнить:
;;;   lsblk -f            # или blkid
;;;   - UUID корневого раздела        -> #:root-device
;;;   - UUID swap-раздела             -> #:swap-device (или убрать строку)
;;;   - UUID ESP (раздел FAT32)       -> в extra-file-systems ниже
;;;
;;; Если машина грузится через BIOS, а не UEFI:
;;;   #:bootloader-type    grub-bootloader
;;;   #:bootloader-targets (list "/dev/sda")
;;;   и убрать /boot/efi из extra-file-systems.
;;;
;;; Применять:
;;;     guix time-machine -C channels.scm -- \
;;;          system reconfigure systems/laptop.scm

(add-to-load-path (dirname (current-filename)))
(use-modules (gnu) (base))

(make-system
 #:host-name "laptop"

 #:root-device (uuid "00000000-0000-0000-0000-000000000000" 'ext4)
 #:root-type "ext4"
 #:swap-device (uuid "00000000-0000-0000-0000-000000000000")

 ;; UEFI: цель загрузчика — точка монтирования ESP, а не диск.
 #:bootloader-type grub-efi-bootloader
 #:bootloader-targets (list "/boot/efi")

 #:extra-file-systems
 (list
  ;; ESP. У FAT32 UUID короткий, вида "1234-ABCD".
  (file-system
    (mount-point "/boot/efi")
    (device (uuid "0000-0000" 'fat32))
    (type "vfat")))

 ;; Пример: на реальном железе часто нужны прошивки и утилиты,
 ;; которых нет в %base-packages.
 ;; #:extra-packages (list (specification->package "nss-certs"))
 )
