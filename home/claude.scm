;;; Своё хозяйство Claude Code: настройки, скиллы, слэш-команды,
;;; хук уведомлений в Telegram.
;;;
;;;     files/claude/settings.json      -> ~/.claude/settings.json
;;;     files/claude/direnv-bash-env.sh -> ~/.claude/direnv-bash-env.sh
;;;     files/claude/{skills,commands,hooks}/* -> ~/.claude/<то же>/*
;;;
;;; Содержимое трёх каталогов перечисляется само: положили скилл или
;;; команду — homerec, и всё, правок здесь не нужно. Пока список был
;;; прописан руками, он уже подвёл: скилл debug-ruclaw-trace лежал в
;;; репозитории и на машину не приезжал.
;;;
;;; КАТАЛОГ ЦЕЛИКОМ СИМЛИНКОВАТЬ НЕЛЬЗЯ, только его содержимое поштучно.
;;; Claude Code пишет в ~/.claude/skills свой synced/ — скиллы, которые
;;; тянет из облака сам, несколько мегабайт. Ссылка на весь skills упрёт
;;; синхронизацию в read-only стор. Для commands и hooks то же правило
;;; заодно позволяет положить рядом локальную команду, не трогая
;;; репозиторий.
;;;
;;; local-file один на всю папку, потому что макрос требует литерала;
;;; отдельные записи собираются file-append'ом. #:recursive? #t — ради
;;; бита +x у hooks/*.sh.
;;;
;;; settings.json становится read-only: Claude Code в него больше не
;;; запишет, поэтому тема и список плагинов правятся ЗДЕСЬ, а /config их
;;; не сохранит. Остальное в ~/.claude (projects, sessions, credentials)
;;; не трогаем.
;;;
;;; Всё это уезжает в стор, читаемый любым пользователем машины, и лежит
;;; в git — токенам здесь не место. Секреты берутся из окружения или из
;;; sops (home/telegram.scm).

(define-module (home claude)
  #:use-module (gnu home services)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (ice-9 ftw)
  #:export (%claude-services))

(define claude-files
  (local-file "../files/claude" "claude" #:recursive? #t))

(define (file-entry name)
  (list (string-append ".claude/" name)
        (file-append claude-files "/" name)))

(define (dir-entries subdir)
  "По записи на каждый элемент files/claude/SUBDIR."
  (map (lambda (name) (file-entry (string-append subdir "/" name)))
       (scandir (string-append (local-file-absolute-file-name claude-files)
                               "/" subdir)
                (lambda (name) (not (string-prefix? "." name))))))

(define %claude-services
  (list (simple-service 'claude-files home-files-service-type
                        (append (list (file-entry "settings.json")
                                      (file-entry "direnv-bash-env.sh"))
                                (dir-entries "skills")
                                (dir-entries "commands")
                                (dir-entries "hooks")))))
