;; Пин версии Guix. Определяет ВСЕ версии пакетов в системе и в home.
;;
;; ЭТО ЗАГЛУШКА — она не пиннит ничего, ветка master плавающая.
;; Замените реальным слепком, выполнив в VM:
;;
;;     guix describe -f channels > /mnt/guix-config/channels.scm
;;
;; После этого `guix pull -C channels.scm` на любой машине даст
;; побитово тот же Guix, а значит и те же версии всех пакетов.
;;
;; Цикл обновления: guix pull -> проверили, что всё живо ->
;; guix describe -f channels > channels.scm -> git commit.
;; Этот файл — ваша точка отката.

(list (channel
       (name 'guix)
       (url "https://git.savannah.gnu.org/git/guix.git")
       (branch "master")))
