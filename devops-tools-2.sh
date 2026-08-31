#!/usr/bin/env bash

# ============================================================
# DevOps Lab Bootstrap & Health Check
# ============================================================
# Instala e verifica ferramentas essenciais para um laboratório
# DevOps.
#
# Características:
#   - Idempotente
#   - Evita reinstalações
#   - Verifica serviços
#   - Verifica ferramentas
#   - Instala Docker, Terraform, Kubernetes, Helm, Kind, Ansible
#   - Apresenta um resumo final do ambiente
#
# ============================================================

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="2.0.0"

readonly LOG_DIR="/var/log/devops-tool"
readonly LOG_FILE="${LOG_DIR}/devops-tools.log"

readonly CURRENT_USER="${SUDO_USER:-$USER}"
readonly CURRENT_HOME="$(eval echo "~${CURRENT_USER}")"

# ============================================================
# CORES
# ============================================================

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# ============================================================
# LOGGING
# ============================================================

setup_logging() {

    sudo install -d -m 0755 "$LOG_DIR"

    if [[ ! -f "$LOG_FILE" ]]; then
        sudo touch "$LOG_FILE"
        sudo chown "$CURRENT_USER":"$CURRENT_USER" "$LOG_FILE"
    fi
}

log() {

    local level="$1"
    shift

    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    echo "[$timestamp] [$level] $*" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[ OK ]${NC} $*"
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

section() {

    echo
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN} $*${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo
}

# ============================================================
# HEADER
# ============================================================

show_header() {

    clear 2>/dev/null || true

    echo
    echo "============================================================"
    echo "              DEVOPS LAB BOOTSTRAP"
    echo "============================================================"
    echo "Script      : $SCRIPT_NAME"
    echo "Version     : $SCRIPT_VERSION"
    echo "Host        : $(hostname)"
    echo "User        : $CURRENT_USER"
    echo "Date        : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================================"
    echo
}

# ============================================================
# ERROR HANDLER
# ============================================================

error_handler() {

    local exit_code=$?

    error "O script terminou com erro."
    error "Linha: ${BASH_LINENO[0]}"
    error "Código: $exit_code"

    log "ERROR" "Script failed with exit code $exit_code"

    exit "$exit_code"
}

trap error_handler ERR

# ============================================================
# CLEANUP
# ============================================================

cleanup() {

    log "INFO" "Script finished"
}

trap cleanup EXIT

# ============================================================
# ROOT / SUDO
# ============================================================

check_sudo() {

    if ! command -v sudo >/dev/null 2>&1; then
        error "sudo não está instalado."
        exit 1
    fi

    if ! sudo -v; then
        error "Não foi possível obter privilégios sudo."
        exit 1
    fi
}

# ============================================================
# OS
# ============================================================

check_os() {

    section "OPERATING SYSTEM"

    if [[ ! -f /etc/os-release ]]; then
        error "/etc/os-release não encontrado."
        exit 1
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    echo "Distribution : ${PRETTY_NAME}"
    echo "Kernel       : $(uname -r)"
    echo "Architecture : $(dpkg --print-architecture)"
    echo "Hostname     : $(hostname)"
    echo "User         : $CURRENT_USER"

    if [[ "${ID:-}" != "ubuntu" ]]; then
        warning "Este script foi desenvolvido principalmente para Ubuntu."
        warning "Sistema detectado: ${PRETTY_NAME}"
    fi
}

# ============================================================
# APT
# ============================================================

apt_update() {

    section "APT UPDATE"

    info "Actualizando índices dos repositórios..."

    sudo apt-get update

    success "APT actualizado."
}

# ============================================================
# PACKAGE INSTALLER
# ============================================================

install_package() {

    local package="$1"

    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null \
        | grep -q "install ok installed"; then

        success "$package já está instalado."
        return 0
    fi

    info "A instalar: $package"

    sudo apt-get install -y "$package"

    success "$package instalado."
}

# ============================================================
# BASE TOOLS
# ============================================================

install_base_tools() {

    section "BASE DEVOPS TOOLS"

    local packages=(
        ca-certificates
        curl
        wget
        gnupg
        lsb-release
        software-properties-common
        apt-transport-https

        git
        openssh-client
        openssh-server

        vim
        nano
        tree
        htop

        unzip
        zip
        tar

        net-tools
        dnsutils
        traceroute
        nmap

        jq
        
        build-essential
        make

        python3
        python3-pip
        python3-venv
        pipx

        shellcheck

        tmux
        rsync

        cron
    )

    for package in "${packages[@]}"; do
        install_package "$package"
    done
}

# ============================================================
# PYTHON / PIPX
# ============================================================

configure_python() {

    section "PYTHON / PIPX"

    if command -v pipx >/dev/null 2>&1; then

        info "Configurando PATH do pipx..."

        sudo -u "$CURRENT_USER" pipx ensurepath \
            >/dev/null 2>&1 || true

        success "pipx disponível."

    else

        warning "pipx não encontrado."
    fi
}

# ============================================================
# DOCKER REPOSITORY
# ============================================================

configure_docker_repository() {

    if [[ -f /etc/apt/sources.list.d/docker.sources ]]; then
        success "Repositório Docker já configurado."
        return 0
    fi

    info "Configurando repositório oficial do Docker..."

    sudo install -m 0755 -d /etc/apt/keyrings

    if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then

        sudo curl -fsSL \
            https://download.docker.com/linux/ubuntu/gpg \
            -o /etc/apt/keyrings/docker.asc

        sudo chmod a+r /etc/apt/keyrings/docker.asc
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    local codename="${UBUNTU_CODENAME:-$VERSION_CODENAME}"

    sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    success "Repositório Docker configurado."
}

# ============================================================
# DOCKER
# ============================================================

install_docker() {

    section "DOCKER"

    if command -v docker >/dev/null 2>&1; then

        success "Docker já está instalado."
        docker --version

    else

        info "A preparar instalação do Docker..."

        # Remover pacotes que podem entrar em conflito
        local conflicting_packages=(
            docker.io
            docker-compose
            docker-compose-v2
            docker-doc
            docker-buildx
            podman-docker
        )

        for package in "${conflicting_packages[@]}"; do

            if dpkg-query -W -f='${Status}' "$package" 2>/dev/null \
                | grep -q "install ok installed"; then

                warning "Removendo pacote conflitante: $package"

                sudo apt-get remove -y "$package"
            fi
        done

        configure_docker_repository

        apt_update

        sudo apt-get install -y \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin

        success "Docker instalado."
    fi

    # Activar Docker
    sudo systemctl enable docker >/dev/null 2>&1 || true
    sudo systemctl start docker

    # Adicionar utilizador ao grupo docker
    if getent group docker >/dev/null 2>&1; then

        if id -nG "$CURRENT_USER" | grep -qw docker; then
            success "$CURRENT_USER já pertence ao grupo docker."
        else
            sudo usermod -aG docker "$CURRENT_USER"

            warning "O utilizador $CURRENT_USER foi adicionado ao grupo docker."
            warning "Será necessário terminar sessão e voltar a entrar para aplicar."
        fi
    fi

    echo
    docker --version

    if docker compose version >/dev/null 2>&1; then
        docker compose version
    fi

    if docker buildx version >/dev/null 2>&1; then
        docker buildx version
    fi
}

# ============================================================
# TERRAFORM
# ============================================================

configure_hashicorp_repository() {

    if [[ -f /etc/apt/sources.list.d/hashicorp.list ]]; then
        success "Repositório HashiCorp já configurado."
        return 0
    fi

    info "Configurando repositório HashiCorp..."

    sudo mkdir -p /usr/share/keyrings

    if [[ ! -f /usr/share/keyrings/hashicorp-archive-keyring.gpg ]]; then

        curl -fsSL \
            https://apt.releases.hashicorp.com/gpg \
            | sudo gpg --dearmor \
            -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    local codename="${UBUNTU_CODENAME:-$VERSION_CODENAME}"

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${codename} main" \
        | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

    success "Repositório HashiCorp configurado."
}

install_terraform() {

    section "TERRAFORM"

    if command -v terraform >/dev/null 2>&1; then

        success "Terraform já está instalado."
        terraform version

        return 0
    fi

    configure_hashicorp_repository

    apt_update

    sudo apt-get install -y terraform

    success "Terraform instalado."

    terraform version
}

# ============================================================
# KUBECTL
# ============================================================

install_kubectl() {

    section "KUBERNETES / KUBECTL"

    if command -v kubectl >/dev/null 2>&1; then

        success "kubectl já está instalado."
        kubectl version --client 2>/dev/null || true

        return 0
    fi

    info "A instalar kubectl..."

    local version

    version="$(curl -L -s https://dl.k8s.io/release/stable.txt)"

    curl -LO \
        "https://dl.k8s.io/release/${version}/bin/linux/amd64/kubectl"

    sudo install \
        -o root \
        -g root \
        -m 0755 \
        kubectl \
        /usr/local/bin/kubectl

    rm -f kubectl

    success "kubectl instalado."

    kubectl version --client
}

# ============================================================
# HELM
# ============================================================

install_helm() {

    section "HELM"

    if command -v helm >/dev/null 2>&1; then

        success "Helm já está instalado."
        helm version

        return 0
    fi

    info "A instalar Helm..."

    curl -fsSL \
        https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
        | bash

    success "Helm instalado."

    helm version
}

# ============================================================
# KIND
# ============================================================

install_kind() {

    section "KIND"

    if command -v kind >/dev/null 2>&1; then

        success "Kind já está instalado."
        kind version

        return 0
    fi

    info "A instalar Kind..."

    local arch

    arch="$(uname -m)"

    case "$arch" in

        x86_64)
            arch="amd64"
            ;;

        aarch64)
            arch="arm64"
            ;;

        *)
            error "Arquitectura não suportada pelo Kind: $arch"
            return 1
            ;;
    esac

    curl -Lo kind \
        "https://kind.sigs.k8s.io/dl/latest/kind-linux-${arch}"

    chmod +x kind

    sudo mv kind /usr/local/bin/kind

    success "Kind instalado."

    kind version
}

# ============================================================
# ANSIBLE
# ============================================================

install_ansible() {

    section "ANSIBLE"

    if command -v ansible >/dev/null 2>&1; then

        success "Ansible já está instalado."
        ansible --version | head -n 1

        return 0
    fi

    info "A instalar Ansible..."

    install_package ansible

    success "Ansible instalado."

    ansible --version | head -n 1
}

# ============================================================
# GITHUB CLI
# ============================================================

install_gh() {

    section "GITHUB CLI"

    if command -v gh >/dev/null 2>&1; then

        success "GitHub CLI já está instalado."
        gh --version | head -n 1

        return 0
    fi

    info "A instalar GitHub CLI..."

    install_package gh

    success "GitHub CLI instalado."
}

# ============================================================
# SSH
# ============================================================

configure_ssh() {

    section "SSH"

    if systemctl list-unit-files \
        | grep -q '^ssh.service'; then

        sudo systemctl enable ssh >/dev/null 2>&1 || true
        sudo systemctl start ssh

        success "SSH Server está activo."

    elif systemctl list-unit-files \
        | grep -q '^sshd.service'; then

        sudo systemctl enable sshd >/dev/null 2>&1 || true
        sudo systemctl start sshd

        success "SSH Server está activo."

    else

        warning "Serviço SSH Server não encontrado."
    fi

    if command -v ssh >/dev/null 2>&1; then
        echo "SSH Client : $(ssh -V 2>&1)"
    fi
}

# ============================================================
# CRON
# ============================================================

configure_cron() {

    section "CRON"

    if systemctl list-unit-files \
        | grep -q '^cron.service'; then

        sudo systemctl enable cron >/dev/null 2>&1 || true
        sudo systemctl start cron

        success "Cron está activo."

    else

        warning "Cron service não encontrado."
    fi
}

# ============================================================
# SYSTEM SERVICES
# ============================================================

check_services() {

    section "SERVICES STATUS"

    local services=(
        docker
        containerd
        ssh
        cron
    )

    printf "%-15s %-12s\n" "SERVICE" "STATUS"
    printf "%-15s %-12s\n" "---------------" "------------"

    for service in "${services[@]}"; do

        if systemctl list-unit-files \
            | grep -q "^${service}.service"; then

            if systemctl is-active --quiet "$service"; then
                printf "%-15s ${GREEN}%-12s${NC}\n" \
                    "$service" "RUNNING"
            else
                printf "%-15s ${RED}%-12s${NC}\n" \
                    "$service" "STOPPED"
            fi

        else

            printf "%-15s ${YELLOW}%-12s${NC}\n" \
                "$service" "NOT FOUND"
        fi
    done
}

# ============================================================
# TOOL VERSION
# ============================================================

show_tool() {

    local name="$1"
    local command="$2"

    if command -v "$command" >/dev/null 2>&1; then

        local version

        case "$command" in

            docker)
                version="$(docker --version 2>/dev/null)"
                ;;

            terraform)
                version="$(terraform version 2>/dev/null | head -n 1)"
                ;;

            kubectl)
                version="$(kubectl version --client 2>/dev/null | head -n 1)"
                ;;

            helm)
                version="$(helm version --short 2>/dev/null)"
                ;;

            kind)
                version="$(kind version 2>/dev/null)"
                ;;

            ansible)
                version="$(ansible --version 2>/dev/null | head -n 1)"
                ;;

            git)
                version="$(git --version 2>/dev/null)"
                ;;

            python3)
                version="$(python3 --version 2>/dev/null)"
                ;;

            ssh)
                version="$(ssh -V 2>&1)"
                ;;

            gh)
                version="$(gh --version 2>/dev/null | head -n 1)"
                ;;

            *)
                version="$("$command" --version 2>/dev/null | head -n 1)"
                ;;
        esac

        printf "${GREEN}%-15s${NC} %s\n" "$name" "$version"

    else

        printf "${RED}%-15s${NC} NOT INSTALLED\n" "$name"
    fi
}

# ============================================================
# INSTALLED TOOLS SUMMARY
# ============================================================

show_installed_tools() {

    section "DEVOPS TOOLCHAIN"

    echo
    printf "%-15s %s\n" "TOOL" "VERSION"
    printf "%-15s %s\n" "---------------" "----------------------------------------"

    show_tool "Git" "git"
    show_tool "SSH" "ssh"
    show_tool "Docker" "docker"
    show_tool "Terraform" "terraform"
    show_tool "kubectl" "kubectl"
    show_tool "Helm" "helm"
    show_tool "Kind" "kind"
    show_tool "Ansible" "ansible"
    show_tool "Python" "python3"
    show_tool "GitHub CLI" "gh"

    echo
}

# ============================================================
# NETWORK
# ============================================================

check_network() {

    section "NETWORK"

    echo "Interfaces:"
    ip -br addr

    echo
    echo "Default route:"

    ip route | grep default || \
        warning "Default route não encontrada."
}

# ============================================================
# SYSTEM HEALTH
# ============================================================

check_system_health() {

    section "SYSTEM HEALTH"

    echo "Uptime:"
    uptime

    echo
    echo "Memory:"
    free -h

    echo
    echo "Disk:"
    df -h /

    local usage

    usage="$(df / | awk 'NR==2 {print $5}' | tr -d '%')"

    if (( usage >= 90 )); then

        error "Disk usage crítico: ${usage}%"
        log "ERROR" "Disk usage critical: ${usage}%"

    elif (( usage >= 80 )); then

        warning "Disk usage elevado: ${usage}%"
        log "WARN" "Disk usage high: ${usage}%"

    else

        success "Disk usage saudável: ${usage}%"
        log "INFO" "Disk usage healthy: ${usage}%"
    fi

    echo
    echo "Top CPU processes:"
    ps aux --sort=-%cpu | head -n 6
}

# ============================================================
# DOCKER TEST
# ============================================================

test_docker() {

    section "DOCKER TEST"

    if ! command -v docker >/dev/null 2>&1; then
        warning "Docker não está disponível."
        return 0
    fi

    if ! systemctl is-active --quiet docker; then
        warning "Docker não está activo."
        return 0
    fi

    if docker info >/dev/null 2>&1; then

        success "Docker Engine está funcional."

    else

        warning "Docker está instalado mas o utilizador actual ainda pode não ter a sessão do grupo docker."
        warning "Se necessário, faça logout/login."
    fi
}

# ============================================================
# FINAL SUMMARY
# ============================================================

show_summary() {

    section "FINAL SUMMARY"

    echo "Host       : $(hostname)"
    echo "User       : $CURRENT_USER"
    echo "Date       : $(date '+%Y-%m-%d %H:%M:%S')"

    echo
    echo "DevOps environment:"
    echo

    show_tool "Git" "git"
    show_tool "SSH" "ssh"
    show_tool "Docker" "docker"
    show_tool "Terraform" "terraform"
    show_tool "kubectl" "kubectl"
    show_tool "Helm" "helm"
    show_tool "Kind" "kind"
    show_tool "Ansible" "ansible"
    show_tool "Python" "python3"
    show_tool "GitHub CLI" "gh"

    echo
    echo "Services:"
    echo

    check_services

    echo
    echo "Log:"
    echo "$LOG_FILE"

    echo
    echo "============================================================"
    echo "        DEVOPS LAB CONFIGURATION COMPLETE"
    echo "============================================================"
    echo
}

# ============================================================
# MAIN
# ============================================================

main() {

    show_header

    check_sudo
    setup_logging

    log "INFO" "Starting DevOps Lab Bootstrap"

    check_os

    # --------------------------------------------------------
    # 1. Base packages
    # --------------------------------------------------------

    apt_update
    install_base_tools

    # --------------------------------------------------------
    # 2. DevOps tools
    # --------------------------------------------------------

    install_docker
    install_terraform
    install_kubectl
    install_helm
    install_kind
    install_ansible
    install_gh

    # --------------------------------------------------------
    # 3. Services
    # --------------------------------------------------------

    configure_ssh
    configure_cron

    # --------------------------------------------------------
    # 4. Health checks
    # --------------------------------------------------------

    check_network
    check_system_health
    test_docker

    # --------------------------------------------------------
    # 5. Final report
    # --------------------------------------------------------

    show_installed_tools
    show_summary

    log "INFO" "DevOps Lab Bootstrap completed successfully"
}

main "$@"
