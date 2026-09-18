;; Домашнее окружение для программирования без графики: облачные VM.
;; Всё содержимое — в home/base.scm, здесь только машинно-зависимые пути.
;;
;; Применять БЕЗ root:
;;     guix home reconfigure ~/guix-config/home/programming.scm

(add-to-load-path (dirname (dirname (current-filename))))
(use-modules (home base))

(make-home
 #:repo "~/guix-config"
 ;; Конфиг системы — по имени хоста: на t1 это systems/t1.scm.
 ;; sudo без -i: guix pull на облачной VM делает пользователь, не root.
 #:sysrec "sudo guix system reconfigure ~/guix-config/systems/$(hostname).scm"
 #:homerec "guix home reconfigure ~/guix-config/home/programming.scm")
