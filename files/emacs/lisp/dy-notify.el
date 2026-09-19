;;; dy-notify.el --- уведомления -*- lexical-binding: t; -*-

(defun dy-notify (text &optional body)
  "Уведомление TEXT (BODY — подробности) и звук.
Без графики (сервер, ssh) — просто сообщение в эхо-области."
  (interactive "sТекст: ")
  (if (and (getenv "DISPLAY") (executable-find "notify-send"))
      (call-process "notify-send" nil 0 nil "-t" "5000" "-i" "emacs" text (or body ""))
    (message "%s %s" text (string-trim (or body ""))))
  ;; Звук есть не в каждой сборке и не на каждой машине.
  (ignore-errors
    (play-sound-file (expand-file-name "alarm.wav" dy-config-dir))))

(provide 'dy-notify)
