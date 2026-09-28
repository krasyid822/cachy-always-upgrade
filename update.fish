#!/usr/bin/env fish
#
# update.fish — Script pembaruan sistem CachyOS/Arch Linux (versi fish)
#
# Mendukung beberapa metode pembaruan:
#   1. pacman -Syu        → Hanya repositori resmi
#   2. paru -Syu          → Resmi + AUR
#   3. cachy-update        → Resmi + AUR + berita Arch + paket yatim + cache + restart layanan
#   4. shelly upgrade all  → Resmi + AUR + Flatpak (manajer paket grafis CachyOS)
#   5. all                 → Jalankan semua tool yang tersedia secara berurutan
#   6. auto                → Deteksi otomatis: cachy-update > shelly > paru > pacman
#
# Penggunaan:
#   ./update.fish              → Mode interaktif (pilih metode)
#   ./update.fish [1|2|3|4|5|6] → Langsung jalankan metode tertentu
#

# ── Warna output ──────────────────────────────────────────────────────────────
set -g RED    '\033[0;31m'
set -g GREEN  '\033[0;32m'
set -g YELLOW '\033[1;33m'
set -g CYAN   '\033[0;36m'
set -g BOLD   '\033[1m'
set -g DIM    '\033[2m'
set -g NC     '\033[0m'

# ── Helper ────────────────────────────────────────────────────────────────────
function info
    printf "%b[INFO]%b %b\n" $CYAN $NC $argv
end

function success
    printf "%b[ OK ]%b %b\n" $GREEN $NC $argv
end

function warn
    printf "%b[WARN]%b %b\n" $YELLOW $NC $argv
end

function error
    printf "%b[FAIL]%b %b\n" $RED $NC $argv >&2
end

function header
    printf "\n%b╔══════════════════════════════════════════════╗%b\n" $CYAN $NC
    printf "%b║%b  $BOLD%b  $NC\n" $CYAN $NC $argv
    printf "%b╚══════════════════════════════════════════════╝%b\n\n" $CYAN $NC
end

function separator
    printf "%b────────────────────────────────────────────────%b\n" $DIM $NC
end

# ── Cek apakah tool tersedia ─────────────────────────────────────────────────
function tool_exists
    command -v $argv[1] >/dev/null 2>&1
end

# ── Cek apakah sistem menggunakan sudo atau sudah root ────────────────────────
function check_privileges
    if test (id -u) -eq 0
        set -g SUDO ""
    else if tool_exists sudo
        set -g SUDO "sudo"
    else
        error "Script ini memerlukan akses root atau sudo."
        exit 1
    end
end

# ── Retry logic untuk perintah yang gagal (misal: timeout jaringan) ───────────
function run_cmd_retry
    set -l max_retries 3
    set -l retry_delay 5
    set -l desc $argv[1]
    set -e argv[1]

    for i in (seq 1 $max_retries)
        info "Menjalankan (percobaan $i/$max_retries): $BOLD$argv$NC"

        # Jalankan langsung — output tampil real-time seperti versi bash
        if eval $argv
            success "$desc selesai."
            return 0
        else
            set -l exit_code $status
            if test $i -lt $max_retries
                warn "Percobaan $i gagal (exit code: $exit_code). Retry dalam $retry_delay detik..."
                sleep $retry_delay
                # Sync database sebelum retry
                if test "$SUDO" = ""
                    pacman -Sy --noconfirm >/dev/null 2>&1
                else
                    sudo pacman -Sy --noconfirm >/dev/null 2>&1
                end
            else
                error "$desc gagal setelah $max_retries percobaan (exit code: $exit_code)."
                return 1
            end
        end
    end
end

# ── Jalankan perintah dengan penanganan error ────────────────────────────────
function run_cmd
    set -l desc $argv[1]
    set -e argv[1]
    run_cmd_retry $desc $argv
end

# ── Definisi metode pembaruan ────────────────────────────────────────────────
function do_pacman
    header "Metode 1: pacman -Syu (Resmi)"
    run_cmd "Sinkronisasi database" $SUDO pacman -Sy
    run_cmd "Upgrade paket" $SUDO pacman -Su
end

function do_paru
    header "Metode 2: paru -Syu (Resmi + AUR)"
    if not tool_exists paru
        error "paru tidak terinstal. Instal dengan: $SUDO pacman -S paru"
        return 1
    end
    run_cmd "paru -Syu" paru -Syu --noconfirm
end

function do_flatpak
    header "Flatpak: Update aplikasi Flatpak"
    if not tool_exists flatpak
        warn "flatpak tidak terinstal, melewati..."
        return 0
    end
    run_cmd "flatpak update" flatpak update -y
end

function do_cachy_update
    header "Metode 3: cachy-update (Resmi + AUR + Perawatan + Flatpak)"
    if not tool_exists cachy-update
        error "cachy-update tidak terinstal."
        return 1
    end
    do_flatpak
    run_cmd "cachy-update" cachy-update
end

function do_shelly
    header "Metode 4: shelly upgrade all (Resmi + AUR + Flatpak)"
    if not tool_exists shelly
        error "shelly tidak terinstal."
        return 1
    end
    run_cmd "shelly upgrade all" shelly upgrade all
end

function do_all
    header "Metode 5: Jalankan SEMUA Metode Pembaruan"
    printf "%b  Mode ini menjalankan semua tool yang tersedia secara berurutan.%b\n" $YELLOW $NC
    printf "%b  Jika ada tool yang tidak terinstal, akan dilewati.%b\n\n" $YELLOW $NC

    set -l ran_any false
    set -l failed 0

    if tool_exists pacman
        do_pacman; or set failed (math $failed + 1)
        set ran_any true
        echo
    else
        warn "pacman tidak ditemukan, melewati..."
    end

    if tool_exists paru
        do_paru; or set failed (math $failed + 1)
        set ran_any true
        echo
    else
        warn "paru tidak terinstal, melewati..."
    end

    if tool_exists shelly
        do_shelly; or set failed (math $failed + 1)
        set ran_any true
        echo
    else
        warn "shelly tidak terinstal, melewati..."
    end

    if tool_exists flatpak
        do_flatpak; or set failed (math $failed + 1)
        set ran_any true
        echo
    else
        warn "flatpak tidak terinstal, melewati..."
    end

    if tool_exists cachy-update
        do_cachy_update; or set failed (math $failed + 1)
        set ran_any true
        echo
    else
        warn "cachy-update tidak terinstal, melewati..."
    end

    if test "$ran_any" = false
        error "Tidak ada tool pembaruan yang tersedia di sistem."
        return 1
    end

    echo
    if test $failed -eq 0
        success "Semua metode pembaruan berhasil dijalankan."
    else
        warn "$failed metode mengalami kegagalan (lihat log di atas)."
    end
end

# ── Mode reload: hapus db.lck + rating mirror ────────────────────────────────
function do_reload
    header "Mode 7: Reload — Hapus db.lck + Rating Mirror"

    if tool_exists pacman
        info "Menghapus /var/lib/pacman/db.lck..."
        run_cmd "Hapus db.lck" $SUDO rm -f /var/lib/pacman/db.lck
    else
        warn "pacman tidak ditemukan, melewati penghapusan db.lck..."
    end

    if tool_exists cachyos-rate-mirrors
        info "Menjalankan cachyos-rate-mirrors..."
        run_cmd "cachyos-rate-mirrors" $SUDO cachyos-rate-mirrors
    else
        warn "cachyos-rate-mirrors tidak terinstal, melewati..."
    end
end

# ── Deteksi otomatis ─────────────────────────────────────────────────────────
function auto_detect
    header "Mode 6: Otomatis — Deteksi tool yang tersedia"

    if tool_exists shelly
        info "shelly ditemukan → menggunakan shelly upgrade all"
        do_shelly
    else if tool_exists paru
        info "paru ditemukan → menggunakan paru -Syu"
        do_paru
    else if tool_exists cachy-update
        info "cachy-update ditemukan → menggunakan cachy-update"
        do_cachy_update
    else
        info "Hanya pacman tersedia → menggunakan pacman -Syu"
        do_pacman
    end
end

# ── Menu interaktif ──────────────────────────────────────────────────────────
function show_menu
    printf "\n"
    printf "%b┌──────────────────────────────────────────────┐%b\n" $CYAN $NC
    printf "%b│%b                                              $BOLD│%b\n" $CYAN $NC
    printf "%b│%b     $BOLD Script Pembaruan Sistem CachyOS $b    │%b\n" $CYAN $NC
    printf "%b│%b                                              $BOLD│%b\n" $CYAN $NC
    printf "%b└──────────────────────────────────────────────┘%b\n" $CYAN $NC
    printf "\n"
    printf "  $BOLD 1)$b pacman -Syu        — Repositori resmi saja\n"
    printf "  $BOLD 2)$b paru -Syu          — Resmi + AUR\n"
    printf "  $BOLD 3)$b cachy-update        — Resmi + AUR + berita + yatim + cache + layanan\n"
    printf "  $BOLD 4)$b shelly upgrade all  — Resmi + AUR + Flatpak\n"
    printf "  $BOLD 5)$b Semua               — Jalankan semua tool yang tersedia\n"
    printf "  $BOLD 6)$b Auto-detect         — Pilih tool terbaik yang tersedia\n"
    printf "  $BOLD 7)$b Reload              — Hapus db.lck + rating mirror\n"
    printf "\n"
    printf "  $BOLD 0)$b Keluar\n"
    printf "\n"
end

function interactive_menu
    while true
        show_menu
        read -P "  Pilih metode [0-6]: " choice
        printf "\n"
        switch $choice
            case 1
                do_pacman
            case 2
                do_paru
            case 3
                do_cachy_update
            case 4
                do_shelly
            case 5
                do_all
            case 6
                auto_detect
            case 7
                do_reload
            case 0
                info "Sampai jumpa!"
                exit 0
            case '*'
                warn "Pilihan tidak valid. Coba lagi."
        end
        printf "\n"
        read -P "  Tekan Enter untuk melanjutkan..."
    end
end

# ── Pre-flight: cek koneksi internet ──────────────────────────────────────────
function check_internet
    info "Memeriksa koneksi internet..."
    if ping -c 1 -W 3 archlinux.org >/dev/null 2>&1
        success "Koneksi internet OK."
    else
        warn "Tidak ada koneksi internet. Update mungkin gagal."
        read -P "  Lanjutkan? [y/N]: " cont
        if not echo "$cont" | grep -qiE "^y"
            info "Dibatalkan."
            exit 0
        end
    end
end

# ── Post-flight: tampilkan paket yatim & saran restart ───────────────────────
function post_update
    header "Pasca-Pembaruan"

    # Cek paket yatim
    if tool_exists pacman
        set -l orphans (pacman -Qdtq 2>/dev/null)
        if test -n "$orphans"
            warn "Paket yatim (orphaned) ditemukan:"
            echo "$orphans" | sed 's/^/  • /'
            printf "\n"
            info "Hapus dengan: $SUDO pacman -Rns (pacman -Qdtq)"
        else
            success "Tidak ada paket yatim."
        end
    end

    # Cek apakah ada layanan yang perlu di-restart
    if tool_exists needs-restarting
        set -l needs (needs-restarting 2>/dev/null)
        if test -n "$needs"
            warn "Layanan berikut perlu di-restart:"
            echo "$needs" | sed 's/^/  • /'
        end
    end

    # Cek apakah kernel baru terinstal (saran reboot)
    if tool_exists pacman
        set -l current_kernel (uname -r)
        set -l latest_kernel (pacman -Q linux 2>/dev/null | awk '{print $2}')
        if test -n "$latest_kernel"; and not echo "$current_kernel" | grep -q "$latest_kernel"
            warn "Kernel baru terinstal ($latest_kernel). Saat ini: $current_kernel"
            info "Pertimbangkan untuk reboot."
        end
    end
end

# ── Usage ────────────────────────────────────────────────────────────────────
function usage
    printf "Penggunaan: %s [OPSI]\n\n" (basename $argv[0])
    printf "Opsi:\n"
    printf "  1, pacman     Jalankan sudo pacman -Syu (resmi saja)\n"
    printf "  2, paru       Jalankan paru -Syu (resmi + AUR)\n"
    printf "  3, cachy      Jalankan cachy-update (resmi + AUR + perawatan)\n"
    printf "  4, shelly     Jalankan shelly upgrade all (resmi + AUR + Flatpak)\n"
    printf "  5, all        Jalankan SEMUA tool yang tersedia secara berurutan\n"
    printf "  6, auto       Deteksi otomatis tool terbaik (hanya jalankan 1)\n"
    printf "  7, reload     Hapus db.lck + rating mirror CachyOS\n"
    printf "  h, help       Tampilkan bantuan ini\n\n"
    printf "Tanpa argumen → mode interaktif (menu).\n"
end

# ── Main ─────────────────────────────────────────────────────────────────────
function main
    check_privileges

    set -l arg (test (count $argv) -gt 0; and echo $argv[1]; or echo "")

    switch $arg
        case 1 pacman
            check_internet; do_pacman; post_update
        case 2 paru
            check_internet; do_paru; post_update
        case 3 cachy
            check_internet; do_cachy_update; post_update
        case 4 shelly
            check_internet; do_shelly; post_update
        case 5 all
            check_internet; do_all; post_update
        case 6 a auto
            check_internet; auto_detect; post_update
        case 7 r reload
            do_reload; post_update
        case h --help -h
            usage; exit 0
        case ''
            check_internet; interactive_menu; post_update
        case '*'
            error "Argumen tidak dikenal: $arg"
            usage
            exit 1
    end
end

main $argv
