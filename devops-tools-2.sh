#!/usr/bin/env bash

# ============================================================
# DEVOPS TOOLS INSTALLER
# Version: 2.0.0
#
# Purpose:
#   Bootstrap a professional DevOps / DevSecOps environment.
#
# Designed for:
#   Ubuntu / Debian-based systems
#   WSL2
#   Linux VMs
#
# Principles:
#   - Idempotent
#   - Modular
#   - Safe
#   - Detect before installing
#   - Validate after installation
#   - Easy to extend
#
# ============================================================

set -Eeuo pipefail

# ============================================================
# CONFIGURATION
# ============================================================

SCRIPT_NAME="DevOps Tools Installer"
VERSION="2.0.0"

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"

LOG_DIR="${HOME}/devops-tools-logs"
LOG_FILE="${LOG_DIR}/install-${TIMESTAMP}.log"

INSTALL_DIR="/usr/local/bin"

TOTAL_TOOLS=0
INSTALLED=0
ALREADY_INSTALLED=0
SKIPPED=0
FAILED=0

# ============================================================
# COLORS
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
RESET='\033[0m'

# ============================================================
# LOGGING
# ============================================================

mkdir -p "$LOG_DIR"

log() {
    local message="$1"

    echo -e "$message" | tee -a "$LOG_FILE"
}

info() {
    log "${BLUE}[INFO]${RESET} $1"
}

success() {
    log "${GREEN}[OK]${RESET} $1"
}

warning() {
    log "${YELLOW}[WARNING]${RESET} $1"
}

error() {
    log "${RED}[ERROR]${RESET} $1"
}

section() {
    log ""
    log "${CYAN}============================================================${RESET}"
    log "${CYAN}$1${RESET}"
    log "${CYAN}============================================================${RESET}"
}

skip() {
    ((SKIPPED+=1))
    log "${YELLOW}[SKIP]${RESET} $1"
}

# ============================================================
# ERROR HANDLER
# ============================================================

error_handler() {

    local exit_code=$?
    local line="${BASH_LINENO[0]:-unknown}"

    error "Falha inesperada na linha ${line}. Exit code: ${exit_code}"

    return "$exit_code"
}

trap error_handler ERR

# ============================================================
# REQUIREMENTS
# ============================================================

check_sudo() {

    section "1. SYSTEM REQUIREMENTS"

    if [[ "${EUID}" -eq 0 ]]; then

        warning "O script está a ser executado como root."

        warning "Recomendação: execute como utilizador normal."

    elif command -v sudo >/dev/null 2>&1; then

        success "sudo disponível."

    else

        error "sudo não está instalado."

        exit 1
    fi
}

check_os() {

    if [[ ! -f /etc/os-release ]]; then

        error "Não foi possível identificar o sistema operativo."

        exit 1
    fi

    source /etc/os-release

    info "OS: ${PRETTY_NAME}"

    if [[ "${ID}" != "ubuntu" && "${ID_LIKE:-}" != *"debian"* ]]; then

        warning "Este script foi optimizado para Ubuntu/Debian."

        warning "Distribuição detectada: ${ID}"
    fi
}

check_architecture() {

    local arch

    arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"

    info "Architecture: ${arch}"

    case "$arch" in

        amd64|x86_64)
            success "Arquitectura x86_64/amd64 suportada."
            ;;

        arm64|aarch64)
            warning "ARM64 detectado. Alguns binários poderão exigir instalação específica."
            ;;

        *)
            warning "Arquitectura não testada: ${arch}"
            ;;
    esac
}

check_network() {

    section "2. NETWORK"

    if curl -fsSI --max-time 10 https://www.google.com >/dev/null 2>&1; then

        success "Conectividade HTTPS funcionando."

    else

        error "Sem conectividade HTTPS."

        error "Corrija a rede antes de continuar."

        exit 1
    fi

    if getent hosts github.com >/dev/null 2>&1; then

        success "DNS funcionando."

    else

        error "DNS não está funcionando."

        exit 1
    fi
}

# ============================================================
# APT
# ============================================================

apt_update() {

    info "Atualizando índice APT..."

    sudo apt-get update -y
}

apt_install() {

    local packages=("$@")

    sudo DEBIAN_FRONTEND=noninteractive \
        apt-get install -y "${packages[@]}"
}

# ============================================================
# GENERIC HELPERS
# ============================================================

command_exists() {

    command -v "$1" >/dev/null 2>&1
}

install_apt_tool() {

    local name="$1"
    shift

    ((TOTAL_TOOLS+=1))

    if command_exists "$name"; then

        success "$name já está instalado."

        ((ALREADY_INSTALLED+=1))

        return 0
    fi

    info "Instalando $name..."

    if apt_install "$@"; then

        success "$name instalado."

        ((INSTALLED+=1))

    else

        error "Falha ao instalar $name."

        ((FAILED+=1))

        return 1
    fi
}

# ============================================================
# BASE TOOLS
# ============================================================

install_base_tools() {

    section "3. BASE LINUX TOOLS"

    apt_install \
        ca-certificates \
        curl \
        wget \
        gnupg \
        lsb-release \
        apt-transport-https \
        software-properties-common \
        unzip \
        zip \
        tar \
        gzip \
        xz-utils \
        tree \
        jq \
        vim \
        nano \
        less \
        file \
        rsync \
        build-essential \
        pkg-config \
        make

    success "Ferramentas base instaladas."
}

# ============================================================
# SYSTEM DIAGNOSTICS
# ============================================================

install_system_tools() {

    section "4. SYSTEM DIAGNOSTICS"

    apt_install \
        htop \
        iotop \
        lsof \
        strace \
        sysstat \
        procps \
        psmisc \
        ncdu

    success "Ferramentas de diagnóstico instaladas."
}

# ============================================================
# NETWORK TOOLS
# ============================================================

install_network_tools() {

    section "5. NETWORKING TOOLS"

    apt_install \
        iproute2 \
        iputils-ping \
        net-tools \
        netcat-openbsd \
        dnsutils \
        traceroute \
        tcpdump \
        nmap \
        whois \
        telnet

    success "Ferramentas de networking instaladas."
}

# ============================================================
# GIT
# ============================================================

install_git_tools() {

    section "6. GIT / VERSION CONTROL"

    install_apt_tool git git

    install_apt_tool git-lfs git-lfs

    if command_exists git-lfs; then

        git lfs install >/dev/null 2>&1 || true

        success "Git LFS configurado."
    fi

    info "Git version:"
    git --version
}

# ============================================================
# SSH
# ============================================================

install_ssh_tools() {

    section "7. SSH"

    install_apt_tool ssh openssh-client

    install_apt_tool ssh-keygen openssh-client

    info "SSH version:"
    ssh -V 2>&1 || true
}

# ============================================================
# GITHUB CLI
# ============================================================

install_github_cli() {

    section "8. GITHUB CLI"

    if command_exists gh; then

        success "GitHub CLI já está instalado."
        ((ALREADY_INSTALLED+=1))
        return
    fi

    info "Instalando GitHub CLI..."

    sudo mkdir -p -m 755 /etc/apt/keyrings

    curl -fsSL \
        https://cli.github.com/packages/githubcli-archive-keyring.gpg |
        sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg \
        >/dev/null

    sudo chmod go+r \
        /etc/apt/keyrings/githubcli-archive-keyring.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) \
        signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] \
        https://cli.github.com/packages stable main" |
        sudo tee /etc/apt/sources.list.d/github-cli.list \
        >/dev/null

    sudo apt-get update -y

    if sudo apt-get install -y gh; then

        success "GitHub CLI instalado."

        ((INSTALLED+=1))

    else

        error "Falha ao instalar GitHub CLI."

        ((FAILED+=1))
    fi
}

# ============================================================
# DOCKER
# ============================================================

install_docker() {

    section "9. DOCKER"

    if command_exists docker; then

        success "Docker já está instalado."

    else

        info "Configurando Docker official repository..."

        sudo install -m 0755 -d /etc/apt/keyrings

        sudo curl -fsSL \
            https://download.docker.com/linux/ubuntu/gpg \
            -o /etc/apt/keyrings/docker.asc

        sudo chmod a+r \
            /etc/apt/keyrings/docker.asc

        source /etc/os-release

        echo \
            "deb [arch=$(dpkg --print-architecture) \
            signed-by=/etc/apt/keyrings/docker.asc] \
            https://download.docker.com/linux/ubuntu \
            ${VERSION_CODENAME} stable" |
            sudo tee /etc/apt/sources.list.d/docker.list \
            >/dev/null

        sudo apt-get update -y

        sudo apt-get install -y \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin

        success "Docker instalado."
    fi

    if command_exists docker; then

        info "Docker version:"
        docker --version

        info "Docker Compose:"
        docker compose version || true

        if getent group docker >/dev/null 2>&1; then

            if id -nG "$USER" | grep -qw docker; then

                success "Utilizador já pertence ao grupo docker."

            else

                warning "Utilizador ainda não pertence ao grupo docker."

                sudo usermod -aG docker "$USER"

                warning "Faça logout/login para aplicar a alteração."
            fi
        fi
    fi
}

# ============================================================
# PYTHON
# ============================================================

install_python_tools() {

    section "10. PYTHON"

    apt_install \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev

    if command_exists python3; then

        success "Python instalado."

        python3 --version
        pip3 --version || true
    fi
}

# ============================================================
# NODE.JS
# ============================================================

install_node_tools() {

    section "11. NODE.JS"

    if command_exists node; then

        success "Node.js já está instalado."

        node --version

    else

        info "Node.js não encontrado."

        info "Instalaremos Node.js através do NodeSource."

        curl -fsSL \
            https://deb.nodesource.com/setup_22.x |
            sudo -E bash -

        sudo apt-get install -y nodejs

        success "Node.js instalado."

        node --version
    fi

    if command_exists npm; then

        success "npm disponível."

        npm --version
    fi

    if ! command_exists corepack; then

        warning "Corepack não encontrado."

    else

        corepack enable >/dev/null 2>&1 || true

        success "Corepack habilitado."
    fi
}

# ============================================================
# TERRAFORM
# ============================================================

install_terraform() {

    section "12. TERRAFORM / IaC"

    if command_exists terraform; then

        success "Terraform já está instalado."

        terraform version | head -1

        return
    fi

    info "Configurando HashiCorp repository..."

    wget -O- \
        https://apt.releases.hashicorp.com/gpg |
        sudo gpg \
            --dearmor \
            -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) \
        signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
        https://apt.releases.hashicorp.com \
        $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) \
        main" |
        sudo tee /etc/apt/sources.list.d/hashicorp.list \
        >/dev/null

    sudo apt-get update -y

    sudo apt-get install -y terraform

    success "Terraform instalado."

    terraform version | head -1
}

# ============================================================
# ANSIBLE
# ============================================================

install_ansible() {

    section "13. ANSIBLE"

    apt_install \
        ansible \
        ansible-lint

    success "Ansible instalado."

    ansible --version | head -1

    if command_exists ansible-lint; then
        ansible-lint --version
    fi
}

# ============================================================
# KUBERNETES - KUBECTL
# ============================================================

install_kubectl() {

    section "14. KUBERNETES - KUBECTL"

    if command_exists kubectl; then

        success "kubectl já está instalado."

        kubectl version --client 2>/dev/null | head -1 || true

        return
    fi

    info "Instalando kubectl..."

    sudo install -m 0755 -d /etc/apt/keyrings

    curl -fsSL \
        https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key |
        sudo gpg \
            --dearmor \
            -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    echo \
        'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
        https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' |
        sudo tee /etc/apt/sources.list.d/kubernetes.list \
        >/dev/null

    sudo apt-get update -y

    sudo apt-get install -y kubectl

    success "kubectl instalado."

    kubectl version --client 2>/dev/null | head -1 || true
}

# ============================================================
# HELM
# ============================================================

install_helm() {

    section "15. KUBERNETES - HELM"

    if command_exists helm; then

        success "Helm já está instalado."

        helm version --short

        return
    fi

    info "Instalando Helm..."

    curl -fsSL \
        https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 |
        bash

    success "Helm instalado."

    helm version --short
}

# ============================================================
# KUSTOMIZE
# ============================================================

install_kustomize() {

    section "16. KUBERNETES - KUSTOMIZE"

    if command_exists kustomize; then

        success "Kustomize já está instalado."

        kustomize version

        return
    fi

    info "Instalando Kustomize..."

    local tmp_dir

    tmp_dir="$(mktemp -d)"

    curl -fsSL \
        https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh |
        bash -s -- "$tmp_dir"

    if [[ -f "${tmp_dir}/kustomize" ]]; then

        sudo install -m 0755 \
            "${tmp_dir}/kustomize" \
            "${INSTALL_DIR}/kustomize"

        rm -rf "$tmp_dir"

        success "Kustomize instalado."

        kustomize version

    else

        rm -rf "$tmp_dir"

        error "Falha ao instalar Kustomize."

        ((FAILED+=1))
    fi
}

# ============================================================
# K9S
# ============================================================

install_k9s() {

    section "17. KUBERNETES - K9S"

    if command_exists k9s; then

        success "K9s já está instalado."

        k9s version 2>/dev/null || true

        return
    fi

    warning "K9s não está disponível via APT padrão."

    info "Instalando através do GitHub release."

    local arch
    local version
    local tmp_dir

    arch="$(uname -m)"

    case "$arch" in
        x86_64)
            arch="amd64"
            ;;
        aarch64)
            arch="arm64"
            ;;
        *)
            error "Arquitectura não suportada para instalação automática do K9s."
            return
            ;;
    esac

    version="$(
        curl -fsSL \
        https://api.github.com/repos/derailed/k9s/releases/latest |
        jq -r '.tag_name'
    )"

    tmp_dir="$(mktemp -d)"

    curl -fsSL \
        "https://github.com/derailed/k9s/releases/download/${version}/k9s_Linux_${arch}.tar.gz" \
        -o "${tmp_dir}/k9s.tar.gz"

    tar -xzf \
        "${tmp_dir}/k9s.tar.gz" \
        -C "$tmp_dir"

    sudo install -m 0755 \
        "${tmp_dir}/k9s" \
        "${INSTALL_DIR}/k9s"

    rm -rf "$tmp_dir"

    success "K9s instalado."

    k9s version 2>/dev/null || true
}

# ============================================================
# SECURITY - TRIVY
# ============================================================

install_trivy() {

    section "18. SECURITY - TRIVY"

    if command_exists trivy; then

        success "Trivy já está instalado."

        trivy --version

        return
    fi

    info "Instalando Trivy..."

    local tmp_dir

    tmp_dir="$(mktemp -d)"

    curl -fsSL \
        https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh |
        sh -s -- -b "$tmp_dir"

    sudo install -m 0755 \
        "${tmp_dir}/trivy" \
        "${INSTALL_DIR}/trivy"

    rm -rf "$tmp_dir"

    success "Trivy instalado."

    trivy --version
}

# ============================================================
# SECURITY - GITLEAKS
# ============================================================

install_gitleaks() {

    section "19. SECURITY - GITLEAKS"

    if command_exists gitleaks; then

        success "Gitleaks já está instalado."

        gitleaks version 2>/dev/null || true

        return
    fi

    info "Instalando Gitleaks..."

    local arch
    local version
    local tmp_dir

    arch="$(uname -m)"

    case "$arch" in
        x86_64)
            arch="x64"
            ;;
        aarch64)
            arch="arm64"
            ;;
        *)
            error "Arquitectura não suportada para Gitleaks."
            return
            ;;
    esac

    version="$(
        curl -fsSL \
        https://api.github.com/repos/gitleaks/gitleaks/releases/latest |
        jq -r '.tag_name'
    )"

    tmp_dir="$(mktemp -d)"

    curl -fsSL \
        "https://github.com/gitleaks/gitleaks/releases/download/${version}/gitleaks_${version#v}_linux_${arch}.tar.gz" \
        -o "${tmp_dir}/gitleaks.tar.gz"

    tar -xzf \
        "${tmp_dir}/gitleaks.tar.gz" \
        -C "$tmp_dir"

    sudo install -m 0755 \
        "${tmp_dir}/gitleaks" \
        "${INSTALL_DIR}/gitleaks"

    rm -rf "$tmp_dir"

    success "Gitleaks instalado."

    gitleaks version 2>/dev/null || true
}

# ============================================================
# CODE QUALITY - SHELLCHECK
# ============================================================

install_shellcheck() {

    section "20. CODE QUALITY - SHELLCHECK"

    install_apt_tool shellcheck shellcheck

    if command_exists shellcheck; then

        shellcheck --version | head -3
    fi
}

# ============================================================
# CODE QUALITY - HADOLINT
# ============================================================

install_hadolint() {

    section "21. CODE QUALITY - HADOLINT"

    if command_exists hadolint; then

        success "Hadolint já está instalado."

        hadolint --version

        return
    fi

    info "Instalando Hadolint..."

    local arch

    arch="$(uname -m)"

    case "$arch" in
        x86_64)
            arch="x86_64"
            ;;
        aarch64)
            arch="aarch64"
            ;;
        *)
            error "Arquitectura não suportada para Hadolint."
            return
            ;;
    esac

    sudo curl -fsSL \
        "https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-${arch}" \
        -o "${INSTALL_DIR}/hadolint"

    sudo chmod +x "${INSTALL_DIR}/hadolint"

    success "Hadolint instalado."

    hadolint --version
}

# ============================================================
# OPTIONAL: SKOPEO
# ============================================================

install_skopeo() {

    section "22. CONTAINER REGISTRY - SKOPEO"

    install_apt_tool skopeo skopeo

    if command_exists skopeo; then

        skopeo --version
    fi
}

# ============================================================
# OPTIONAL: SOPS
# ============================================================

install_sops() {

    section "23. SECRETS - SOPS"

    if command_exists sops; then

        success "SOPS já está instalado."

        sops --version

        return
    fi

    warning "SOPS é uma ferramenta futura do laboratório."

    info "Instalando SOPS para gestão segura de secrets."

    local arch
    local version
    local tmp_dir

    arch="$(uname -m)"

    case "$arch" in
        x86_64)
            arch="amd64"
            ;;
        aarch64)
            arch="arm64"
            ;;
        *)
            error "Arquitectura não suportada para SOPS."
            return
            ;;
    esac

    version="$(
        curl -fsSL \
        https://api.github.com/repos/getsops/sops/releases/latest |
        jq -r '.tag_name'
    )"

    tmp_dir="$(mktemp -d)"

    curl -fsSL \
        "https://github.com/getsops/sops/releases/download/${version}/sops-${version}.linux.${arch}" \
        -o "${tmp_dir}/sops"

    sudo install -m 0755 \
        "${tmp_dir}/sops" \
        "${INSTALL_DIR}/sops"

    rm -rf "$tmp_dir"

    success "SOPS instalado."

    sops --version
}

# ============================================================
# OPTIONAL: AGE
# ============================================================

install_age() {

    section "24. SECRETS - AGE"

    if command_exists age; then

        success "age já está instalado."

        age --version

        return
    fi

    apt_install age

    success "age instalado."

    age --version
}

# ============================================================
# FUTURE CLOUD TOOLS
# ============================================================

show_future_cloud_tools() {

    section "25. FUTURE CLOUD TOOLS"

    info "Cloud CLIs não serão instaladas automaticamente nesta versão."

    log ""
    log "Planeadas:"
    log "  - AWS CLI"
    log "  - Azure CLI"
    log "  - Google Cloud CLI"
    log ""
    log "Motivo:"
    log "  Instalar apenas a cloud necessária evita"
    log "  aumentar desnecessariamente o ambiente."
}

# ============================================================
# FUTURE GITOPS TOOLS
# ============================================================

show_future_gitops_tools() {

    section "26. FUTURE GITOPS"

    info "Ferramentas previstas para fases futuras:"

    log "  - Argo CD CLI"
    log "  - Flux CLI"
    log "  - Argo Rollouts"
}

# ============================================================
# FUTURE MONITORING
# ============================================================

show_monitoring_stack() {

    section "27. MONITORING / OBSERVABILITY"

    info "Estas ferramentas NÃO serão instaladas pelo APT."

    log ""
    log "A plataforma de observabilidade será executada"
    log "preferencialmente através de Docker Compose/Kubernetes."
    log ""
    log "Planeadas:"
    log "  - Prometheus"
    log "  - Grafana"
    log "  - Node Exporter"
    log "  - cAdvisor"
    log "  - Alertmanager"
    log "  - Loki"
    log "  - Blackbox Exporter"
}

# ============================================================
# VALIDATION
# ============================================================

validate_tool() {

    local tool="$1"

    if command_exists "$tool"; then

        success "Validation: ${tool} OK"

    else

        warning "Validation: ${tool} NÃO encontrado."
    fi
}

validate_installation() {

    section "28. INSTALLATION VALIDATION"

    local tools=(
        git
        git-lfs
        ssh
        curl
        wget
        jq
        docker
        terraform
        ansible
        ansible-lint
        kubectl
        helm
        kustomize
        k9s
        python3
        pip3
        node
        npm
        gh
        trivy
        gitleaks
        shellcheck
        hadolint
        skopeo
        sops
        age
        htop
        lsof
        strace
        nc
        dig
        tcpdump
        nmap
    )

    for tool in "${tools[@]}"; do

        validate_tool "$tool"

    done
}

# ============================================================
# DOCKER TEST
# ============================================================

validate_docker() {

    section "29. DOCKER VALIDATION"

    if ! command_exists docker; then

        warning "Docker não está disponível."

        return
    fi

    info "Docker:"
    docker --version

    info "Compose:"
    docker compose version || true

    if docker info >/dev/null 2>&1; then

        success "Docker daemon acessível."

    else

        warning "Docker daemon não está acessível pelo utilizador atual."

        warning "Se acabou de adicionar o utilizador ao grupo docker,"
        warning "faça logout/login ou reinicie a sessão WSL."

        info "Teste alternativo:"
        info "sudo docker info"
    fi
}

# ============================================================
# SECURITY VALIDATION
# ============================================================

validate_security_tools() {

    section "30. SECURITY VALIDATION"

    if command_exists trivy; then

        info "Trivy:"
        trivy --version
    fi

    if command_exists gitleaks; then

        info "Gitleaks:"
        gitleaks version 2>/dev/null || true
    fi

    if command_exists shellcheck; then

        info "ShellCheck:"
        shellcheck --version | head -3
    fi

    if command_exists hadolint; then

        info "Hadolint:"
        hadolint --version
    fi
}

# ============================================================
# ENVIRONMENT SUMMARY
# ============================================================

show_environment_summary() {

    section "31. ENVIRONMENT SUMMARY"

    source /etc/os-release

    log ""
    log "Operating System : ${PRETTY_NAME}"
    log "Kernel           : $(uname -r)"
    log "Architecture     : $(uname -m)"
    log "CPU              : $(nproc)"
    log "User             : ${USER}"
    log "Home             : ${HOME}"
    log "Shell            : ${SHELL}"
    log ""

    if grep -qi microsoft /proc/version 2>/dev/null; then

        log "Environment      : WSL2"

    else

        log "Environment      : Linux / VM / Bare Metal"
    fi
}

# ============================================================
# SUMMARY
# ============================================================

show_final_summary() {

    section "32. INSTALLATION SUMMARY"

    log ""
    log "Tools installed       : ${INSTALLED}"
    log "Already installed     : ${ALREADY_INSTALLED}"
    log "Skipped               : ${SKIPPED}"
    log "Failed                : ${FAILED}"
    log ""

    if [[ "${FAILED}" -eq 0 ]]; then

        success "DevOps environment bootstrap concluído."

    else

        error "A instalação terminou com ${FAILED} falha(s)."

        warning "Consulte o log:"
        log "${LOG_FILE}"
    fi

    log ""
    log "Log file:"
    log "${LOG_FILE}"

    log ""

    log "${CYAN}PRÓXIMOS PASSOS:${RESET}"

    log ""
    log "1. Reiniciar a sessão se o grupo docker foi alterado."
    log ""
    log "2. Testar Docker:"
    log "   docker run hello-world"
    log ""
    log "3. Testar Kubernetes:"
    log "   kubectl version --client"
    log ""
    log "4. Testar Terraform:"
    log "   terraform version"
    log ""
    log "5. Testar Ansible:"
    log "   ansible --version"
    log ""
    log "6. Testar segurança:"
    log "   trivy --version"
    log "   gitleaks version"
    log ""
    log "7. Testar qualidade:"
    log "   shellcheck --version"
    log "   hadolint --version"
    log ""
    log "8. Testar GitHub:"
    log "   gh auth status"
    log ""
}

# ============================================================
# MAIN
# ============================================================

main() {

    section "DEVOPS TOOLS INSTALLER v${VERSION}"

    check_sudo
    check_os
    check_architecture
    check_network

    apt_update

    install_base_tools

    install_system_tools

    install_network_tools

    install_git_tools

    install_ssh_tools

    install_github_cli

    install_docker

    install_python_tools

    install_node_tools

    install_terraform

    install_ansible

    install_kubectl

    install_helm

    install_kustomize

    install_k9s

    install_trivy

    install_gitleaks

    install_shellcheck

    install_hadolint

    install_skopeo

    install_sops

    install_age

    show_future_cloud_tools

    show_future_gitops_tools

    show_monitoring_stack

    validate_installation

    validate_docker

    validate_security_tools

    show_environment_summary

    show_final_summary
}

main "$@"
