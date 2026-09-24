;;; Своё хозяйство Claude Code: настройки, скиллы, слэш-команды,
;;; хук уведомлений в Telegram.
;;;
;;;     files/claude/<файл>       -> ~/.claude/<файл>
;;;     files/claude/<каталог>/*  -> ~/.claude/<каталог>/*
;;;
;;; СПИСКА ФАЙЛОВ ЗДЕСЬ НЕТ. Содержимое files/claude перечисляется на
;;; этапе вычисления конфигурации: положили скилл или команду в папку,
;;; сделали homerec — и всё. Раньше каждый файл был прописан руками, и
;;; это уже подвело: скилл debug-ruclaw-trace лежал в репозитории, но на
;;; машину не приезжал, потому что строчку дописать забыли.
;;;
;;; Как обходится ограничение local-file. Макрос требует ЛИТЕРАЛА: он
;;; разрешает относительный путь во время раскрытия. Поэтому local-file
;;; ровно один, на всю папку, а отдельные записи собираются file-append'ом
;;; по готовому объекту. #:recursive? #t нужен ради бита +x у hooks/*.sh:
;;; без него скрипт уедет в стор без права на исполнение и молча не
;;; запустится.
;;;
;;; КАТАЛОГ ВЕРХНЕГО УРОВНЯ НЕ СИМЛИНКУЕТСЯ ЦЕЛИКОМ, симлинкуется его
;;; содержимое поштучно. Для skills это принципиально: сам ~/.claude/skills
;;; обязан остаться обычным каталогом, потому что Claude Code пишет в него
;;; synced/ — скиллы, которые он синхронизирует из облака сам (pdf, docx,
;;; xlsx, skill-creator, несколько мегабайт). Симлинк на весь skills — и
;;; синхронизация упрётся в read-only стор. Для commands и hooks то же
;;; правило даёт приятный побочный эффект: рядом можно положить локальную
;;; команду, не трогая репозиторий.
;;;
;;; По той же причине synced/ нет и в репозитории: он не наш и не
;;; воспроизводится из него.
;;;
;;; Скилл — это каталог с SKILL.md (и, если нужно, скриптами рядом), он
;;; уезжает в стор целиком.
;;;
;;; settings.json — read-only симлинк в стор, со всеми вытекающими: сам
;;; Claude Code в него больше не запишет. Значит тема и список включённых
;;; плагинов правятся ЗДЕСЬ, а /config и менеджер плагинов изменение не
;;; сохранят. Это осознанный размен, тот же, что с конфигом Emacs.
;;; Проверено на t1: с read-only settings.json claude запускается и
;;; работает штатно, на файл не ругается.
;;;
;;; Остальное в ~/.claude (projects, sessions, .credentials.json, history,
;;; plugins) Guix Home не трогает — туда Claude Code пишет постоянно.
;;;
;;; Всё это уезжает в стор, который читает любой пользователь машины, и
;;; лежит в git — токенам здесь не место. Секреты берутся из окружения
;;; (JIRA_API_TOKEN, GITLAB_TOKEN) или из sops (home/telegram.scm).

(define-module (home claude)
  #:use-module (gnu home services)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (ice-9 ftw)
  #:use-module (srfi srfi-1)
  #:export (%claude-services))

;; Литерал — иначе local-file не сможет разрешить относительный путь.
(define claude-files
  (local-file "../files/claude" "claude" #:recursive? #t))

;; Тот же каталог, но как путь на диске: по нему перечисляем содержимое.
;; Ищем по известному файлу и берём dirname — надёжнее, чем искать каталог.
(define %claude-directory
  (let ((marker (search-path %load-path "files/claude/settings.json")))
    (unless marker
      (error "не нашёл в %load-path: files/claude/settings.json"))
    (dirname marker)))

(define (listing subdir)
  "Отсортированное содержимое files/claude/SUBDIR, без точечных записей.
SUBDIR = \"\" означает сам files/claude."
  (let ((dir (if (string-null? subdir)
                 %claude-directory
                 (string-append %claude-directory "/" subdir))))
    (or (scandir dir (lambda (f) (not (string-prefix? "." f))))
        '())))

(define (entry target sub)
  (list target (file-append claude-files sub)))

(define (claude-entries)
  (let ((entries
         (append-map
          (lambda (name)
            (let ((path (string-append %claude-directory "/" name)))
              (if (file-is-directory? path)
                  (map (lambda (child)
                         (entry (string-append ".claude/" name "/" child)
                                (string-append "/" name "/" child)))
                       (listing name))
                  (list (entry (string-append ".claude/" name)
                               (string-append "/" name))))))
          (listing ""))))
    ;; Падать громко: пустой список означал бы, что не приедет ничего, а
    ;; заметили бы мы это в лучшем случае по пропавшему скиллу.
    (when (null? entries)
      (error "в files/claude пусто:" %claude-directory))
    entries))

(define %claude-services
  (list (simple-service 'claude-files home-files-service-type
                        (claude-entries))))
