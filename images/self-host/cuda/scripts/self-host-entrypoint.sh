#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="${SELF_HOST_STATE_DIR:-/var/lib/self-host}"
SSH_PORT="${SSH_PORT:-22}"
INITIALIZED_FILE="${STATE_DIR}/initialized"
PASSWORD_HASH_FILE="${STATE_DIR}/root-password.hash"
AUTHORIZED_KEYS="/root/.ssh/authorized_keys"

install -d -m 0700 "${STATE_DIR}" /root/.ssh
install -d -m 0755 /run/sshd

append_authorized_keys() {
    local source="$1"
    local key

    while IFS= read -r key; do
        [[ -z "${key}" ]] && continue
        grep -qxF "${key}" "${AUTHORIZED_KEYS}" 2>/dev/null || printf '%s\n' "${key}" >> "${AUTHORIZED_KEYS}"
    done < "${source}"
}

if [[ -n "${SSH_AUTHORIZED_KEYS_FILE:-}" ]]; then
    if [[ ! -r "${SSH_AUTHORIZED_KEYS_FILE}" ]]; then
        echo "error: SSH_AUTHORIZED_KEYS_FILE is not readable: ${SSH_AUTHORIZED_KEYS_FILE}" >&2
        exit 1
    fi
    append_authorized_keys "${SSH_AUTHORIZED_KEYS_FILE}"
fi

if [[ -n "${SSH_PUBLIC_KEY:-}" ]]; then
    key_file="$(mktemp)"
    printf '%s\n' "${SSH_PUBLIC_KEY}" > "${key_file}"
    append_authorized_keys "${key_file}"
    rm -f "${key_file}"
fi

touch "${AUTHORIZED_KEYS}"
chmod 0700 /root/.ssh
chmod 0600 "${AUTHORIZED_KEYS}"

if [[ ! -e "${INITIALIZED_FILE}" ]]; then
    initial_password="${INITIAL_ROOT_PASSWORD:-}"
    if [[ -n "${INITIAL_ROOT_PASSWORD_FILE:-}" ]]; then
        if [[ ! -r "${INITIAL_ROOT_PASSWORD_FILE}" ]]; then
            echo "error: INITIAL_ROOT_PASSWORD_FILE is not readable: ${INITIAL_ROOT_PASSWORD_FILE}" >&2
            exit 1
        fi
        initial_password="$(<"${INITIAL_ROOT_PASSWORD_FILE}")"
    fi

    if [[ -n "${initial_password}" ]]; then
        if [[ "${initial_password}" == *$'\n'* || "${initial_password}" == *$'\r'* ]]; then
            echo "error: the initial root password must not contain newlines" >&2
            exit 1
        fi
        printf 'root:%s\n' "${initial_password}" | chpasswd
        getent shadow root | cut -d: -f2 > "${PASSWORD_HASH_FILE}"
        chmod 0600 "${PASSWORD_HASH_FILE}"
    elif [[ ! -s "${AUTHORIZED_KEYS}" ]]; then
        echo "error: first start requires INITIAL_ROOT_PASSWORD, INITIAL_ROOT_PASSWORD_FILE, SSH_PUBLIC_KEY, or SSH_AUTHORIZED_KEYS_FILE" >&2
        exit 1
    fi

    touch "${INITIALIZED_FILE}"
    chmod 0600 "${INITIALIZED_FILE}"
elif [[ -n "${INITIAL_ROOT_PASSWORD:-}" || -n "${INITIAL_ROOT_PASSWORD_FILE:-}" ]]; then
    echo "notice: initial root password input ignored because credentials are already initialized" >&2
fi

if [[ -s "${PASSWORD_HASH_FILE}" ]]; then
    usermod --password "$(tr -d '\r\n' < "${PASSWORD_HASH_FILE}")" root
else
    passwd -d root >/dev/null
fi

if [[ ! -s "${STATE_DIR}/ssh_host_ed25519_key" ]]; then
    ssh-keygen -q -t ed25519 -N '' -f "${STATE_DIR}/ssh_host_ed25519_key"
fi
if [[ ! -s "${STATE_DIR}/ssh_host_rsa_key" ]]; then
    ssh-keygen -q -t rsa -b 4096 -N '' -f "${STATE_DIR}/ssh_host_rsa_key"
fi
chmod 0600 "${STATE_DIR}"/ssh_host_*_key
chmod 0644 "${STATE_DIR}"/ssh_host_*.pub

password_authentication=no
if [[ -s "${PASSWORD_HASH_FILE}" ]]; then
    password_authentication=yes
fi

cat > /etc/ssh/sshd_config.d/99-self-host.conf <<EOF
Port ${SSH_PORT}
HostKey ${STATE_DIR}/ssh_host_ed25519_key
HostKey ${STATE_DIR}/ssh_host_rsa_key
PermitRootLogin yes
PasswordAuthentication ${password_authentication}
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile /root/.ssh/authorized_keys
UsePAM yes
X11Forwarding no
AllowTcpForwarding yes
ClientAliveInterval 60
ClientAliveCountMax 3
EOF

sshd -t
/usr/sbin/sshd -D -e &

unset INITIAL_ROOT_PASSWORD initial_password
exec "$@"
