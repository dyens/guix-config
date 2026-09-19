;; -*- lexical-binding: t; -*-
;; From https://protesilaos.com/codelog/2020-08-03-emacs-custom-functions-galore/
(defconst dy-insert-pair-alist
'(("' Single quote" . (39 39))           ; ' '
    ("\" Double quotes" . (34 34))         ; " "
    ("` Elisp quote" . (96 39))            ; ` '
    ("‘ Single apostrophe" . (8216 8217))  ; ‘ ’
    ("“ Double apostrophes" . (8220 8221)) ; “ ”
    ("( Parentheses" . (40 41))            ; ( )
    ("{ Curly brackets" . (123 125))       ; { }
    ("[ Square brackets" . (91 93))        ; [ ]
    ("< Angled brackets" . (60 62))        ; < >
    ("« tree brakets" . (171 187)))        ; « »
"Alist of pairs for use with.")

;;;###autoload
(defun dy-insert-pair-completion (&optional arg)
"Insert pair from."
(interactive "P")
(let* ((data dy-insert-pair-alist)
        (chars (mapcar #'car data))
        (choice (completing-read "Select character: " chars nil t))
        (left (cadr (assoc choice data)))
        (right (caddr (assoc choice data))))
    (insert-pair arg left right)))


(provide 'dy-insert-pair)
