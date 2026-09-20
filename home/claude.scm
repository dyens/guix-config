;;; Своё хозяйство Claude Code: скиллы и хук уведомлений.
;;;
;;;     files/claude/skills -> ~/.claude/skills
;;;     files/claude/hooks  -> ~/.claude/hooks
;;;
;;; А вот ~/.claude/settings.json Guix Home НЕ трогает, и это намеренно:
;;; туда Claude Code пишет сам (тема, включённые плагины), симлинк в стор
;;; это сломает. Блок "hooks" там правится руками — см. README, раздел
;;; «Уведомления Claude Code».
;;;
;;; Скилл — это каталог с SKILL.md (и, если нужно, скриптами рядом).
;;; Claude Code подхватывает всё, что лежит в ~/.claude/skills.
;;;
;;; Симлинкуется КАЖДЫЙ скилл по отдельности, а не каталог skills целиком.
;;; Это принципиально: сам ~/.claude/skills должен остаться обычным
;;; каталогом, потому что Claude Code пишет в него ~/.claude/skills/synced
;;; — скиллы, которые он синхронизирует из облака сам (pdf, docx, xlsx,
;;; skill-creator и прочие, несколько мегабайт). Сделай симлинком весь
;;; skills — и синхронизация упрётся в read-only стор.
;;;
;;; По той же причине synced/ нет и в репозитории: он не наш и не
;;; воспроизводится из него.
;;;
;;; Остальное в ~/.claude (settings.json, projects, sessions, credentials)
;;; Guix Home не трогает — как и ~/.docker/config.json в home/docker.scm.
;;;
;;; Новый скилл: положить каталог в files/claude/skills/ и дописать сюда
;;; строку. Цикл по списку имён тут не годится — local-file разрешает
;;; относительный путь во время раскрытия макроса и требует литерала.
;;;
;;; Скиллы уезжают в стор, который читает любой пользователь машины, и
;;; лежат в git — токенам в них не место. Секреты берутся из окружения
;;; (JIRA_API_TOKEN, GITLAB_TOKEN), см. .envrc проекта.

(define-module (home claude)
  #:use-module (gnu home services)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:export (%claude-services))

(define %claude-services
  (list (simple-service 'claude-skills home-files-service-type
                        `((".claude/skills/implement"
                           ,(local-file "../files/claude/skills/implement"
                                        #:recursive? #t))
                          (".claude/skills/jira"
                           ,(local-file "../files/claude/skills/jira"
                                        #:recursive? #t))
                          (".claude/skills/to-tickets"
                           ,(local-file "../files/claude/skills/to-tickets"
                                        #:recursive? #t))
                          (".claude/skills/update-cs-service-on-d3"
                           ,(local-file "../files/claude/skills/update-cs-service-on-d3"
                                        #:recursive? #t))
                          ;; #:recursive? #t здесь не ради каталога, а ради
                          ;; бита +x: без него local-file кладёт одиночный
                          ;; файл в стор без права на исполнение, и хук
                          ;; молча не запустится.
                          (".claude/hooks/notify.sh"
                           ,(local-file "../files/claude/hooks/notify.sh"
                                        #:recursive? #t))))))
