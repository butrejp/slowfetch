#!/bin/sh
#
# slowfetch - a deliberately slow system fetch
#

field() {
    printf "%-14s %s\n" "$1" "$2"
}

have() {
    command -v "$1" >/dev/null 2>&1
}

# ---------- OS ----------

if [ -r /etc/os-release ]; then
    . /etc/os-release
fi

os=${PRETTY_NAME:-${NAME:-$(uname -s)}}
distro_id=${ID:-unknown}
based_on=${ID_LIKE:-unknown}

# ---------- basic ----------

user=$(id -un 2>/dev/null || printf '%s' "$USER")
host=$(hostname 2>/dev/null || uname -n)
kernel=$(uname -r)
arch=$(uname -m)
shell=${SHELL##*/}

# ---------- variant ----------

variant="Traditional"
atomic="no"

if have rpm-ostree; then
    variant="OSTree"
    atomic="yes"
elif [ -f /.dockerenv ]; then
    variant="Container"
fi

# ---------- uptime ----------

uptime=""

if [ -r /proc/uptime ]; then
    uptime=$(
        awk '{
            s=int($1)
            d=int(s/86400)
            h=int((s%86400)/3600)
            m=int((s%3600)/60)

            if (d) printf "%dd ", d
            if (h) printf "%dh ", h
            printf "%dm", m
        }' /proc/uptime
    )
fi

# ---------- CPU ----------

cpu=""

if [ -r /proc/cpuinfo ]; then
    cpu=$(
        awk -F: '
        /model name/ {
            sub(/^[ \t]+/, "", $2)
            print $2
            exit
        }' /proc/cpuinfo
    )
fi

# ---------- GPU ----------

gpu=""

if have lspci; then
    gpu=$(
        lspci 2>/dev/null |
        awk -F': ' '
        /VGA|3D|Display/ {
            print $2
            exit
        }'
    )
fi

# ---------- NVIDIA ----------

nvidia_driver=""

if have nvidia-smi; then
    nvidia_driver=$(
        nvidia-smi \
        --query-gpu=driver_version \
        --format=csv,noheader 2>/dev/null |
        head -n1
    )
fi

# ---------- Memory ----------

memory=""

if [ -r /proc/meminfo ]; then
    memory=$(
        awk '
        /^MemTotal:/ {t=$2}
        /^MemAvailable:/ {a=$2}
        END {
            printf "%.1f / %.1f GiB",
            (t-a)/1048576,
            t/1048576
        }' /proc/meminfo
    )
fi

# ---------- Disk ----------

disk=""

if have df; then
    disk=$(
        df -h / 2>/dev/null |
        awk 'NR==2 {
            print $3 " / " $2 " (" $5 ")"
        }'
    )
fi

# ---------- Root filesystem ----------

rootfs=""

if have findmnt; then
    rootfs=$(findmnt -n -o FSTYPE / 2>/dev/null)
elif have df; then
    rootfs=$(df -T / 2>/dev/null |
        awk 'NR==2 {print $2}')
fi

# ---------- rpm-ostree ----------

image=""
pretty_image=""
deployment=""
state=""
commit=""

if have rpm-ostree; then

    image=$(
        rpm-ostree status 2>/dev/null |
        awk '
        /ostree-image-signed:/ {
            sub(/^.*ostree-image-signed:/, "")
            print
            exit
        }
        /origin ref:/ {
            sub(/^.*origin ref: /, "")
            print
            exit
        }'
    )

    pretty_image=$(printf '%s' "$image" |
        sed \
        -e 's#docker://##' \
        -e 's#ghcr.io/##')

    deployment=$(
        rpm-ostree status 2>/dev/null |
        awk '
        /Version:/ {
            print $2
            exit
        }'
    )

    state=$(
        rpm-ostree status 2>/dev/null |
        awk '
        /State:/ {
            print $2
            exit
        }'
    )

    commit=$(
        rpm-ostree status 2>/dev/null |
        awk '
        /Commit:/ {
            print substr($2,1,12)
            exit
        }'
    )
fi

# ---------- Deployment age ----------

age=""

if have rpm-ostree && have stat; then
    deploy_dir="/ostree/deploy"

    if [ -d "$deploy_dir" ]; then
        age=$(
            find "$deploy_dir" \
            -maxdepth 3 \
            -type f \
            -printf '%T@ %p\n' 2>/dev/null |
            sort -nr |
            head -n1 |
            awk '{print int((systime()-$1)/86400) " days"}'
        )
    fi
fi

# ---------- Packages ----------

packages=""

if have rpm-ostree; then
    packages=$(
        rpm-ostree status 2>/dev/null |
        awk '
        /Packages:/ {
            print $2
            exit
        }'
    )
fi

if [ -z "$packages" ] && have rpm; then
    packages=$(rpm -qa 2>/dev/null | wc -l)
fi

# ---------- Init ----------

if [ -d /run/systemd/system ]; then
    init="systemd"
elif have openrc; then
    init="OpenRC"
else
    init="unknown"
fi

# ---------- Desktop ----------

desktop=${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-tty}}

if [ -n "$WAYLAND_DISPLAY" ]; then
    display="Wayland"
elif [ -n "$DISPLAY" ]; then
    display="X11"
else
    display="TTY"
fi

# ---------- Battery ----------

battery=""

if [ -d /sys/class/power_supply ]; then
    bat=$(find /sys/class/power_supply \
        -name 'BAT*' \
        | head -n1)

    if [ -n "$bat" ] && [ -r "$bat/capacity" ]; then
        battery="$(cat "$bat/capacity")%"

        if [ -r "$bat/status" ]; then
            battery="$battery $(cat "$bat/status")"
        fi
    fi
fi

# ---------- Kernel command line ----------

cmdline=""

if [ -r /proc/cmdline ]; then
    cmdline=$(cat /proc/cmdline)
fi

# ---------- output ----------

printf '\n'
printf '\033[1;36mslowfetch\033[0m\n'
printf '\033[1;36m%s@%s\033[0m\n' "$user" "$host"
printf '%s\n' '-----------------------------'

field OS "$os"

[ -n "$pretty_image" ] && field Image "$pretty_image"
[ -n "$deployment" ] && field Version "$deployment"
[ -n "$state" ] && field State "$state"
[ -n "$commit" ] && field Commit "$commit"
[ -n "$age" ] && field Deploy-Age "$age"

field Variant "$variant"
field Atomic "$atomic"

field ID "$distro_id"
field Based-On "$based_on"

field Kernel "$kernel"
field Arch "$arch"
field Shell "$shell"

[ -n "$cpu" ] && field CPU "$cpu"
[ -n "$gpu" ] && field GPU "$gpu"
[ -n "$nvidia_driver" ] && field NVIDIA "$nvidia_driver"

[ -n "$memory" ] && field Memory "$memory"
[ -n "$disk" ] && field Disk "$disk"
[ -n "$rootfs" ] && field RootFS "$rootfs"

[ -n "$uptime" ] && field Uptime "$uptime"
[ -n "$packages" ] && field Packages "$packages"

field Init "$init"
field Desktop "$desktop"
field Display "$display"

[ -n "$battery" ] && field Battery "$battery"
[ -n "$cmdline" ] && field Cmdline "$cmdline"

field Directory "$PWD"

printf '\n'
