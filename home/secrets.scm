;;; Имена ключей sops-файла — общее для home/ssh.scm и home/kube.scm.
;;;
;;; В sops шифруются только ЗНАЧЕНИЯ, имена верхнеуровневых ключей
;;; остаются открытым текстом. Поэтому список ключей читается прямо из
;;; зашифрованного файла, без ключа расшифровки, — и списки секретов не
;;; приходится держать в коде.
;;;
;;; ПРО ПАПКИ. sops-guix берёт имя файла из имени ключа, склеивая части
;;; через "/" (sops/secrets.scm, key->file-name). Значит ключ, названный
;;;
;;;     ssh/croc-gitlab
;;;
;;; расшифровывается в /run/user/<uid>/secrets/ssh/croc-gitlab — подкаталог
;;; появляется сам, а YAML остаётся плоским. Вложенные ключи дают тот же
;;; результат, но их пришлось бы разбирать по отступам, а там и служебный
;;; блок sops: с такими же четырьмя пробелами. Оба варианта проверены на
;;; t1, выбран плоский.

(define-module (home secrets)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 regex)
  #:export (secret-keys))

(define (secret-keys file)
  "Верхнеуровневые ключи sops-файла FILE, кроме служебного блока sops."
  (call-with-input-file file
    (lambda (port)
      (let loop ((keys '()))
        (let ((line (read-line port)))
          (if (eof-object? line)
              (reverse keys)
              (let ((m (string-match "^([^ \t#][^:]*):" line)))
                (loop (if (and m (not (string=? (match:substring m 1) "sops")))
                          (cons (match:substring m 1) keys)
                          keys)))))))))
