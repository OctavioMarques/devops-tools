#!/usr/bin/env bash

# ============================================================
# DevOps Environment Troubleshooter
# ============================================================
#
# Version: 1.0.0
#
# Objectivo:
#   Diagnosticar problemas comuns num ambiente DevOps.
#
# Ambiente actual:
#   - Ubuntu / Debian
#   - WSL2
#   - Docker
#   - Docker Compose
#   - Prometheus
#   - Grafana
#
# Ferramentas futuras detectadas automaticamente:
#   - Git
#   - SSH
#   - Terraform
#   - Ansible
#   - kubectl
#   - Kubernetes
#   - Helm
#   - Python
#   - Node.js
#   - npm
#   - Java
#   - Nginx
#   - PostgreSQL
#   - MySQL
#   - MongoDB
#   - Redis
#   - curl
#   - wget
#   - jq
#   - systemctl
#
# ============================================================

set -Eeuo pipefail

# ============================================================
# CONFIGURATION
# ============================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="1.0.0"

readonly TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"

readonly LOG_DIR="/var/log/devops-troubleshooter"
readonly LOG_FILE="${LOG_DIR}/troubleshooting-${TIMESTAMP}.log"

readonly REPORT_DIR="${HOME}/devops-troubleshooting"
readonly REPORT_FILE="${REPORT_DIR}/report-${TIMESTAMP}.txt"

readonly MONITORING_DIR="/opt/monitoring"

readonly PROMETHEUS_PORT="9090"
readonly GRAFANA_PORT="3000"

readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

ERRORS=0
WARNINGS=0
CHECKS=0

# ============================================================
# SETUP
# ============================================================

setup_environment() {

    mkdir -p "$REPORT_DIR"

    if command -v sudo >/dev/null 2>&1; then

        sudo mkdir -p "$LOG_DIR"

        if [[ ! -f "$LOG_FILE" ]]; then
            sudo touch "$LOG_FILE"
        fi

        sudo chown "$(id -un)":"$(id -gn)" "$LOG_FILE"

    else

        mkdir -p "$LOG_DIR" 2>/dev/null || true

    fi

    touch "$REPORT_FILE"
}

# ============================================================
# LOGGING
# ============================================================

log() {

    local level="$1"
    shift

    local timestamp

    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    echo "[$timestamp] [$level] $*" | tee -a "$LOG_FILE" >> "$REPORT_FILE"
}

info() {

    echo -e "${BLUE}[INFO]${NC} $*"

    log "INFO" "$*"
}

success() {

    echo -e "${GREEN}[ OK ]${NC} $*"

    log "OK" "$*"
}

warning() {

    ((WARNINGS+=1))

    echo -e "${YELLOW}[WARN]${NC} $*"

    log "WARN" "$*"
}

error() {

    ((ERRORS+=1))

    echo -e "${RED}[ERROR]${NC} $*"

    log "ERROR" "$*"
}

skip() {

    echo -e "${YELLOW}[SKIP]${NC} $*"

    log "SKIP" "$*"
}

check() {

    ((CHECKS+=1))

    echo -e "${CYAN}[CHECK]${NC} $*"

    log "CHECK" "$*"
}

section() {

    echo
    echo "============================================================"
    echo " $*"
    echo "============================================================"
    echo
}

# ============================================================
# ERROR HANDLER
# ============================================================

error_handler() {

    local exit_code=$?

    echo
    error "Ocorreu um erro inesperado."
    error "Código: ${exit_code}"
    error "Linha aproximada: ${BASH_LINENO[0]}"

    log "ERROR" "Unexpected script error: ${exit_code}"
}

trap error_handler ERR

# ============================================================
# HEADER
# ============================================================

show_header() {

    clear 2>/dev/null || true

    echo
    echo "============================================================"
    echo "             DEVOPS ENVIRONMENT TROUBLESHOOTER"
    echo "============================================================"
    echo "Script      : ${SCRIPT_NAME}"
    echo "Version     : ${SCRIPT_VERSION}"
    echo "Host        : $(hostname)"
    echo "User        : $(id -un)"
    echo "Date        : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================================"
    echo
}

# ============================================================
# SYSTEM INFORMATION
# ============================================================

check_system() {

    section "1. SYSTEM INFORMATION"

    check "Operating System"

    if [[ -f /etc/os-release ]]; then

        # shellcheck disable=SC1091
        source /etc/os-release

        echo "OS            : ${PRETTY_NAME}"
        echo "Kernel        : $(uname -r)"
        echo "Architecture  : $(uname -m)"

        success "Operating System detectado."

    else

        error "Não foi possível identificar o sistema operativo."

    fi


    check "CPU"

    echo "CPU cores     : $(nproc)"
    echo "Architecture  : $(uname -m)"


    check "Memory"

    free -h


    check "Disk"

    df -h /


    check "Load Average"

    uptime
}

# ============================================================
# WSL CHECK
# ============================================================

check_wsl() {

    section "2. WSL / VIRTUALIZATION"

    if grep -qi microsoft /proc/version 2>/dev/null; then

        success "WSL detectado."

        echo
        echo "WSL version information:"
        uname -a

    else

        info "WSL não detectado."

    fi
}

# ============================================================
# PROCESSES
# ============================================================

check_processes() {

    section "3. PROCESSES"

    check "Top CPU processes"

    ps aux --sort=-%cpu | head -n 8

    echo

    check "Top Memory processes"

    ps aux --sort=-%mem | head -n 8
}

# ============================================================
# NETWORK
# ============================================================

check_network() {

    section "4. NETWORK"

    check "Network interfaces"

    if command -v ip >/dev/null 2>&1; then

        ip -br addr

    else

        warning "ip command não está instalado."

    fi


    check "Default route"

    ip route | grep '^default' || warning "Default route não encontrada."


    check "DNS"

    if command -v getent >/dev/null 2>&1; then

        if getent hosts google.com >/dev/null 2>&1; then

            success "DNS está a funcionar."

        else

            error "DNS não conseguiu resolver google.com."

        fi

    fi


    check "Internet connectivity"

    if command -v curl >/dev/null 2>&1; then

        if curl -fsS \
            --connect-timeout 10 \
            --max-time 20 \
            https://www.google.com \
            >/dev/null 2>&1; then

            success "Conectividade HTTPS disponível."

        else

            error "Conectividade HTTPS indisponível."

        fi

    else

        warning "curl não está instalado."

    fi
}

# ============================================================
# PORT CHECK
# ============================================================

check_port() {

    local host="$1"
    local port="$2"
    local name="$3"

    check "Porta ${port} - ${name}"

    if command -v nc >/dev/null 2>&1; then

        if nc -z -w 3 "$host" "$port" >/dev/null 2>&1; then

            success "${name} está acessível em ${host}:${port}"

        else

            warning "${name} não responde em ${host}:${port}"

        fi

    elif command -v curl >/dev/null 2>&1; then

        if curl -fsS \
            --connect-timeout 3 \
            "http://${host}:${port}" \
            >/dev/null 2>&1; then

            success "${name} responde em ${host}:${port}"

        else

            warning "${name} não responde em ${host}:${port}"

        fi

    else

        warning "Não existe ferramenta disponível para testar portas."

    fi
}

# ============================================================
# INSTALLED TOOLS
# ============================================================

check_tool() {

    local tool="$1"

    check "Tool: ${tool}"

    if command -v "$tool" >/dev/null 2>&1; then

        local version

        version="$(
            "$tool" --version 2>&1 \
            | head -n 1 \
            || true
        )"

        success "${tool}: INSTALLED"

        echo "    ${version}"

    else

        skip "${tool}: NOT INSTALLED"
    fi
}

check_tools() {

    section "5. DEVOPS TOOLS"

    local tools=(
        git
        ssh
        curl
        wget
        jq
        docker
        terraform
        ansible
        kubectl
        helm
        python3
        node
        npm
        java
        nginx
        psql
        mysql
        mongosh
        redis-cli
    )

    for tool in "${tools[@]}"; do

        check_tool "$tool"

    done
}

# ============================================================
# GIT
# ============================================================

check_git() {

    section "6. GIT"

    if ! command -v git >/dev/null 2>&1; then

        skip "Git não está instalado."

        return 0
    fi

    success "Git instalado."

    echo
    git --version

    echo

    check "Git configuration"

    git config --global --list 2>/dev/null \
        || warning "Configuração Git não encontrada."

    echo

    check "GitHub SSH connectivity"

    if command -v ssh >/dev/null 2>&1; then

        if ssh -T \
            -o BatchMode=yes \
            -o ConnectTimeout=10 \
            git@github.com \
            2>&1 | grep -qi "successfully authenticated"; then

            success "Autenticação SSH com GitHub OK."

        else

            warning "Não foi possível confirmar autenticação SSH com GitHub."

        fi
    fi
}

# ============================================================
# SSH
# ============================================================

check_ssh() {

    section "7. SSH"

    if ! command -v ssh >/dev/null 2>&1; then

        skip "SSH client não instalado."

        return 0
    fi

    success "SSH client instalado."

    ssh -V 2>&1 || true


    if command -v systemctl >/dev/null 2>&1; then

        check "SSH service"

        if systemctl is-active --quiet ssh 2>/dev/null; then

            success "SSH service está activo."

        elif systemctl is-active --quiet sshd 2>/dev/null; then

            success "SSHD service está activo."

        else

            warning "SSH service não está activo ou não existe."

        fi
    fi
}

# ============================================================
# DOCKER
# ============================================================

check_docker() {

    section "8. DOCKER"

    if ! command -v docker >/dev/null 2>&1; then

        skip "Docker não instalado."

        return 0
    fi

    success "Docker CLI instalado."

    docker --version


    check "Docker daemon"

    if docker info >/dev/null 2>&1; then

        success "Docker daemon está operacional."

    elif sudo docker info >/dev/null 2>&1; then

        warning "Docker funciona através de sudo."

    else

        error "Docker daemon não está operacional."

        return 0
    fi


    check "Docker containers"

    docker ps -a \
        --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" \
        || true


    check "Docker images"

    docker images \
        --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" \
        || true


    check "Docker disk usage"

    docker system df || true
}

# ============================================================
# DOCKER COMPOSE
# ============================================================

check_compose() {

    section "9. DOCKER COMPOSE"

    if ! command -v docker >/dev/null 2>&1; then

        skip "Docker não instalado."

        return 0
    fi

    if docker compose version >/dev/null 2>&1; then

        success "Docker Compose disponível."

        docker compose version

    else

        warning "Docker Compose Plugin não disponível."

    fi
}

# ============================================================
# MONITORING STACK
# ============================================================

check_monitoring() {

    section "10. MONITORING STACK"

    if ! command -v docker >/dev/null 2>&1; then

        skip "Docker não disponível."

        return 0
    fi


    check "Prometheus container"

    if docker ps \
        --format '{{.Names}}' \
        | grep -qx "prometheus"; then

        success "Prometheus container está RUNNING."

    else

        warning "Prometheus container não está RUNNING."

    fi


    check "Grafana container"

    if docker ps \
        --format '{{.Names}}' \
        | grep -qx "grafana"; then

        success "Grafana container está RUNNING."

    else

        warning "Grafana container não está RUNNING."

    fi


    check_port "127.0.0.1" \
        "$PROMETHEUS_PORT" \
        "Prometheus"


    check_port "127.0.0.1" \
        "$GRAFANA_PORT" \
        "Grafana"


    check "Prometheus HTTP health"

    if command -v curl >/dev/null 2>&1; then

        if curl -fsS \
            "http://127.0.0.1:${PROMETHEUS_PORT}/-/ready" \
            >/dev/null 2>&1; then

            success "Prometheus está READY."

        else

            warning "Prometheus não respondeu ao health check."

        fi
    fi


    check "Grafana HTTP health"

    if command -v curl >/dev/null 2>&1; then

        if curl -fsS \
            "http://127.0.0.1:${GRAFANA_PORT}/api/health" \
            >/dev/null 2>&1; then

            success "Grafana está READY."

        else

            warning "Grafana não respondeu ao health check."

        fi
    fi
}

# ============================================================
# MONITORING CONFIGURATION
# ============================================================

check_monitoring_config() {

    section "11. MONITORING CONFIGURATION"

    if [[ ! -d "$MONITORING_DIR" ]]; then

        skip "${MONITORING_DIR} não existe."

        return 0
    fi

    success "Monitoring directory encontrado."

    echo
    echo "Directory:"
    ls -lah "$MONITORING_DIR"


    if [[ -f "${MONITORING_DIR}/docker-compose.yml" ]]; then

        check "Docker Compose configuration"

        if docker compose \
            -f "${MONITORING_DIR}/docker-compose.yml" \
            config \
            >/dev/null 2>&1; then

            success "docker-compose.yml válido."

        else

            error "docker-compose.yml contém erros."

        fi

    else

        warning "docker-compose.yml não encontrado."

    fi


    if [[ -f "${MONITORING_DIR}/prometheus/prometheus.yml" ]]; then

        success "prometheus.yml encontrado."

    else

        warning "prometheus.yml não encontrado."

    fi
}

# ============================================================
# CONTAINER LOGS
# ============================================================

show_container_logs() {

    section "12. IMPORTANT CONTAINER LOGS"

    if ! command -v docker >/dev/null 2>&1; then

        skip "Docker não disponível."

        return 0
    fi

    local containers=(
        prometheus
        grafana
        node-exporter
        cadvisor
        alertmanager
        loki
    )

    for container in "${containers[@]}"; do

        if docker ps -a \
            --format '{{.Names}}' \
            | grep -qx "$container"; then

            echo
            echo "----- ${container} -----"

            docker logs \
                --tail 20 \
                "$container" \
                2>&1 \
                || true

        fi

    done
}

# ============================================================
# KUBERNETES
# ============================================================

check_kubernetes() {

    section "13. KUBERNETES"

    if ! command -v kubectl >/dev/null 2>&1; then

        skip "kubectl não instalado."

        return 0
    fi

    success "kubectl instalado."

    kubectl version --client 2>/dev/null || true


    check "Kubernetes cluster connectivity"

    if kubectl cluster-info \
        >/dev/null 2>&1; then

        success "Kubernetes cluster acessível."

        echo

        kubectl get nodes \
            -o wide \
            2>/dev/null \
            || true

    else

        warning "kubectl instalado, mas nenhum cluster acessível."

    fi
}

# ============================================================
# TERRAFORM
# ============================================================

check_terraform() {

    section "14. TERRAFORM"

    if ! command -v terraform >/dev/null 2>&1; then

        skip "Terraform não instalado."

        return 0
    fi

    success "Terraform instalado."

    terraform version


    if [[ -d .terraform ]]; then

        check "Terraform working directory"

        terraform validate \
            2>&1 \
            || warning "Terraform validate encontrou problemas."

    fi
}

# ============================================================
# ANSIBLE
# ============================================================

check_ansible() {

    section "15. ANSIBLE"

    if ! command -v ansible >/dev/null 2>&1; then

        skip "Ansible não instalado."

        return 0
    fi

    success "Ansible instalado."

    ansible --version


    if [[ -f inventory ]]; then

        check "Ansible inventory"

        ansible-inventory \
            --list \
            >/dev/null 2>&1 \
            || warning "Inventory Ansible apresenta problemas."

    fi
}

# ============================================================
# FILESYSTEM
# ============================================================

check_filesystem() {

    section "16. FILESYSTEM"

    check "Disk usage"

    df -h


    check "Inodes"

    df -ih


    check "Large files in /var"

    if command -v du >/dev/null 2>&1; then

        sudo du -xh \
            /var \
            --max-depth=1 \
            2>/dev/null \
            | sort -h \
            | tail -n 10 \
            || true

    fi
}

# ============================================================
# SYSTEM SERVICES
# ============================================================

check_services() {

    section "17. SYSTEM SERVICES"

    if ! command -v systemctl >/dev/null 2>&1; then

        skip "systemctl não disponível."

        return 0
    fi

    local services=(
        docker
        ssh
        cron
        nginx
    )

    for service in "${services[@]}"; do

        check "$service service"

        if systemctl list-unit-files \
            | grep -q "^${service}.service"; then

            if systemctl is-active \
                --quiet "$service" 2>/dev/null; then

                success "${service}: ACTIVE"

            else

                warning "${service}: INACTIVE"

            fi

        else

            skip "${service}: NOT INSTALLED"

        fi

    done
}

# ============================================================
# SYSTEM ERRORS
# ============================================================

check_system_errors() {

    section "18. SYSTEM ERRORS"

    if command -v journalctl >/dev/null 2>&1; then

        check "Recent system errors"

        journalctl \
            -p err \
            -b \
            --no-pager \
            -n 30 \
            2>/dev/null \
            || true

    else

        skip "journalctl não disponível."

    fi
}

# ============================================================
# LISTENING PORTS
# ============================================================

check_listening_ports() {

    section "19. LISTENING PORTS"

    if command -v ss >/dev/null 2>&1; then

        ss -tulpn

    else

        warning "ss command não está disponível."

    fi
}

# ============================================================
# ENVIRONMENT VARIABLES
# ============================================================

check_environment() {

    section "20. ENVIRONMENT"

    echo "PATH:"
    echo "$PATH"

    echo

    echo "SHELL:"
    echo "${SHELL:-unknown}"

    echo

    echo "USER:"
    echo "${USER:-unknown}"

    echo

    echo "HOME:"
    echo "$HOME"
}

# ============================================================
# FINAL SUMMARY
# ============================================================

show_summary() {

    section "TROUBLESHOOTING SUMMARY"

    echo
    echo "Checks performed : ${CHECKS}"
    echo "Warnings         : ${WARNINGS}"
    echo "Errors           : ${ERRORS}"
    echo
    echo "Log file:"
    echo "  ${LOG_FILE}"
    echo
    echo "Report:"
    echo "  ${REPORT_FILE}"
    echo


    if (( ERRORS == 0 && WARNINGS == 0 )); then

        success "Ambiente sem problemas detectados."

    elif (( ERRORS == 0 )); then

        warning "Ambiente funcional, mas existem avisos para investigar."

    else

        error "Foram detectados ${ERRORS} problemas."

    fi

    echo
    echo "============================================================"
}

# ============================================================
# MAIN
# ============================================================

main() {

    setup_environment

    show_header

    log "INFO" "Starting DevOps troubleshooting"

    check_system

    check_wsl

    check_processes

    check_network

    check_tools

    check_git

    check_ssh

    check_docker

    check_compose

    check_monitoring

    check_monitoring_config

    show_container_logs

    check_kubernetes

    check_terraform

    check_ansible

    check_filesystem

    check_services

    check_system_errors

    check_listening_ports

    check_environment

    show_summary

    log "INFO" "DevOps troubleshooting completed"
}

main "$@"

