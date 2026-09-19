;;; dy-tools.el --- мелкие команды -*- lexical-binding: t; -*-

(defun dy-rename-file-and-buffer (name)
  "Переименовать текущий файл (через VC, если он под ним) и его буфер."
  (interactive (list (read-string "Новое имя: " (buffer-file-name))))
  (let ((file (buffer-file-name)))
    (if (vc-registered file)
        (vc-rename-file file name)
      (rename-file file name))
    (set-visited-file-name name t t)))

(defun dy-copy-file-and-line ()
  "Скопировать путь:строка текущего места."
  (interactive)
  (if-let* ((file (buffer-file-name)))
      (let ((result (format "%s:%d" file (line-number-at-pos))))
        (kill-new result)
        (message "Скопировано: %s" result))
    (user-error "Буфер не связан с файлом")))

(provide 'dy-tools)
