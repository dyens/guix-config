;; Домашнее окружение пользователя dyens (Guix Home).
;;
;; Применять БЕЗ root:
;;     guix home reconfigure /mnt/guix-config/home/dyens.scm
;;
;; Откат:  guix home roll-back
;; Список: guix home list-generations
;;
;; ВАЖНО: Guix Home делает ~/.bashrc и прочие dotfiles симлинками
;; в /gnu/store, то есть read-only. Править надо файлы в files/,
;; а потом reconfigure. Это и есть та дисциплина, которая даёт
;; воспроизводимость.

(use-modules (gnu home)
             (gnu home services)
             (gnu home services shells)
             (gnu packages)
             (gnu services)
             (guix gexp))

(home-environment

 ;; Пакеты пользователя. Системные (i3, xorg) остаются в systems/vm.scm.
 (packages
  (map specification->package
       '("git"
         "ripgrep"
         "fd"
         "htop"
         "curl"
         "unzip"
         "vim")))

 (services
  (list
   (service home-bash-service-type
            (home-bash-configuration
             (aliases '(("ll"  . "ls -alF")
                        ("la"  . "ls -A")
                        ("gs"  . "git status")
                        ("gd"  . "git diff")
                        ;; reconfigure системы и home из проброшенного репозитория
                        ("sysrec"  . "sudo -i guix system reconfigure /mnt/guix-config/systems/vm.scm")
                        ("homerec" . "guix home reconfigure /mnt/guix-config/home/dyens.scm")))
             (bashrc (list (local-file "../files/bashrc" "bashrc")))))

   ;; Dotfiles в ~/.config/. Раскомментируйте, когда положите
   ;; реальный конфиг в files/i3/config.
   ;; (simple-service 'dotfiles
   ;;                 home-xdg-configuration-files-service-type
   ;;                 `(("i3/config" ,(local-file "../files/i3/config"))))
   )))
