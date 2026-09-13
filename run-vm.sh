#!/usr/bin/env bash
# Запуск dev-VM с Guix: проброс ssh на 10022 и этого репозитория по 9p.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VMS="$(dirname "$REPO")"

DISK="${GUIX_VM_DISK:-$VMS/guix.qcow2}"
PORT="${GUIX_VM_SSH_PORT:-10022}"
MEM="${GUIX_VM_MEM:-4096}"
CPUS="${GUIX_VM_CPUS:-4}"
USER_IN_VM="${GUIX_VM_USER:-dyens}"
PIDFILE="$VMS/.guix-vm.pid"

qemu_args=(
  # -cpu host ОБЯЗАТЕЛЕН. Без него QEMU поднимает модель qemu64,
  # которая маскирует AVX/AVX2 даже под KVM. Бинарники, собранные
  # Bun'ом (например Claude Code), на таком CPU уходят в бесконечный
  # цикл вместо честного SIGILL. Заодно это заметно быстрее.
  -enable-kvm -cpu host -m "$MEM" -smp "$CPUS"
  -nic "user,model=virtio-net-pci,hostfwd=tcp::${PORT}-:22"
  -drive "file=$DISK,if=virtio"
  # security_model=none => гостевые uid/gid совпадают с хостовыми,
  # поэтому из VM можно и читать, и писать в этот каталог.
  -virtfs "local,path=$REPO,mount_tag=guixcfg,security_model=none"
)

case "${1:-start}" in
  start)
    exec qemu-system-x86_64 "${qemu_args[@]}" -vga virtio
    ;;
  headless)
    qemu-system-x86_64 "${qemu_args[@]}" -display none -daemonize -pidfile "$PIDFILE"
    echo "VM запущена в фоне, pid $(cat "$PIDFILE"). SSH: $0 ssh"
    ;;
  ssh)
    shift
    exec ssh -p "$PORT" \
      -o UserKnownHostsFile="$VMS/.known_hosts.guixvm" \
      -o StrictHostKeyChecking=accept-new \
      "$USER_IN_VM@127.0.0.1" "$@"
    ;;
  stop)
    if [[ -f "$PIDFILE" ]]; then
      kill "$(cat "$PIDFILE")" && rm -f "$PIDFILE"
      echo "остановлена"
    else
      echo "pidfile не найден — VM запущена не через 'headless'?" >&2
      exit 1
    fi
    ;;
  *)
    echo "usage: $0 {start|headless|ssh [cmd...]|stop}" >&2
    exit 1
    ;;
esac
