;;; Pi coding agent: декларативно нужные Pi packages.
;;;
;;; Собственно бинарник `pi' ставится пакетом packages/pi-coding-agent.scm.
;;; Расширения Pi — это не Guix-пакеты, а Pi packages из npm/git/local;
;;; `pi install' пишет декларацию в ~/.pi/agent/settings.json и ставит npm
;;; зависимости в ~/.pi/agent/npm. Поэтому здесь активация делает ровно это,
;;; но идемпотентно: если source уже упомянут в settings.json, не трогает.
;;;
;;; Важно: если активация была без сети и установка не удалась, homerec не
;;; падает. Повторить руками:
;;;
;;;     pi update --extensions
;;;     # или: pi install npm:pi-subagents && pi install npm:pi-web-access

(define-module (home pi)
  #:use-module (gnu home services)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (packages pi-coding-agent)
  #:export (%pi-services))

(define %pi-package-sources
  '("npm:pi-subagents"
    "npm:pi-web-access"))

(define %pi-services
  (list
   (simple-service
    'pi-packages home-activation-service-type
    #~(begin
        (use-modules (ice-9 textual-ports))
        (let* ((home (getenv "HOME"))
               (agent-dir (string-append home "/.pi/agent"))
               (settings (string-append agent-dir "/settings.json"))
               (pi #$(file-append pi-coding-agent "/bin/pi"))
               (path (string-append #$(file-append pi-coding-agent "/bin")
                                    ":" home "/.guix-home/profile/bin"
                                    ":" home "/.guix-profile/bin"
                                    ":" (or (getenv "PATH") ""))))
          (setenv "PATH" path)
          (unless (file-exists? agent-dir)
            (mkdir-p agent-dir))
          (define (settings-text)
            (if (file-exists? settings)
                (call-with-input-file settings get-string-all)
                ""))
          (for-each
           (lambda (source)
             ;; Достаточно текстовой проверки: `pi install' сам корректно
             ;; обновляет JSON, а нам важно не гонять npm на каждый homerec.
             (unless (string-contains (settings-text) source)
               (format #t "Installing Pi package ~a...~%" source)
               (let ((status (system* pi "install" source)))
                 (unless (zero? status)
                   (format (current-error-port)
                           "warning: failed to install Pi package ~a; retry with `pi update --extensions'~%"
                           source)))))
           (list #$@%pi-package-sources)))))))
