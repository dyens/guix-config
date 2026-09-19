;; -*- lexical-binding: t; -*-
(defun dy-capitalize-first-char (&optional string)
  "Capitalize only the first character of the input STRING."
  (when (and string (> (length string) 0))
    (let ((first-char (substring string nil 1))
          (rest-str   (substring string 1)))
      (concat (capitalize first-char) rest-str))))

(defun dy-screaming-to-camel (s)
  "Convert screaming to camel case.
  Example:
      HELLO_WORLD -> HelloWorld
  " 
  (mapconcat 'capitalize (split-string s "_") ""))


(defun dy--random-alnum ()
  (let* ((alnum "abcdefghijklmnopqrstuvwxyz0123456789")
         (i (% (abs (random)) (length alnum))))
    (substring alnum i (1+ i))))

;;;###autoload
(defun dy-insert-random-string (len)
  "Insert random string.
   Use c-U 10 M-x insert-random-string
   "
  (interactive "p")
  (message (format "%d" len))
  (dotimes (i len)
  (insert (dy--random-alnum))))


(provide 'dy-string)
