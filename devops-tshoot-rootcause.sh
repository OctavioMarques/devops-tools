#!/usr/bin/env bash

# ============================================================
# DevOps Troubleshooter v2.0
# Deep Diagnostic & Root Cause Analysis
# ============================================================

set -Eeuo pipefail

SCRIPT_NAME="DevOps Troubleshooter"
VERSION="2.0.0"

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"

LOG_DIR="/var/log/devops-troubleshooter"
REPORT_DIR="${HOME}/devops-troubleshooting"

REPORT_FILE="${REPORT_DIR}/diagnostic-${TIMESTAMP}.log"
LOG_FILE="${LOG_DIR}/troubleshooter-${TIMESTAMP}.log"

MONITORING_DIR="/opt/monitoring"

PROMETHEUS_PORT=9090
GRAFANA_PORT=3000

ERRORS=0
WARNINGS=0
CHECKS=0
ROOT_CAUSES=0

# ============================================================
# CORES
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

setup_environment() {

    mkdir -p "$REPORT_DIR"

    if command -v sudo >/dev/null 2>&1; then
        sudo mkdir -p "$LOG_DIR"
        sudo touch "$LOG_FILE"
        sudo chmod 664 "$LOG_FILE"
    else
        echo "WARNING: sudo não encontrado."
    fi

    touch "$REPORT_FILE"
}

log() {

    local message="$1"

    echo -e "$message" | tee -a "$REPORT_FILE"

    if [[ -w "$LOG_FILE" ]]; then
        echo -e "$message" >> "$LOG_FILE"
    elif command -v sudo >/dev/null 2>&1; then
        echo -e "$message" | sudo tee -a "$LOG_FILE" >/dev/null
    fi
}

info() {
    log "${BLUE}[INFO]${RESET} $1"
}

success() {
    log "${GREEN}[OK]${RESET} $1"
}

warning() {

    ((WARNINGS+=1))

    log "${YELLOW}[WARNING]${RESET} $1"
}

error() {

    ((ERRORS+=1))

    log "${RED}[ERROR]${RESET} $1"
}

section() {

    log ""
    log "${CYAN}============================================================${RESET}"
    log "${CYAN}$1${RESET}"
    log "${CYAN}============================================================${RESET}"
}

evidence() {

    log "  ${MAGENTA}Evidence:${RESET} $1"
}

cause() {

    ((ROOT_CAUSES+=1))

    log "  ${RED}Likely Root Cause:${RESET} $1"
}

action() {

    log "  ${GREEN}Recommended Action:${RESET} $1"
}

skip() {

    log "${YELLOW}[SKIP]${RESET} $1"
}

check() {

    ((CHECKS+=1))

    log "${BLUE}[CHECK]${RESET} $1"
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
# HEADER
# ============================================================

show_header() {

    clear || true

    log "${CYAN}"
    log "============================================================"
    log "              DEVOPS TROUBLESHOOTER v${VERSION}"
    log "         DEEP DIAGNOSTIC / ROOT CAUSE ANALYSIS"
    log "============================================================"
    log "${RESET}"

    log "Data: $(date)"
    log "Host: $(hostname)"
    log "User: ${USER}"
    log "Report: ${REPORT_FILE}"
    log ""
}

# ============================================================
# SYSTEM INFORMATION
# ============================================================

diagnose_system() {

    section "1. SYSTEM / OS"

    check "Operating System"

    if [[ -f /etc/os-release ]]; then

        source /etc/os-release

        info "Distribution: ${PRETTY_NAME}"
        info "Version: ${VERSION_ID}"

    else

        warning "Não foi possível identificar a distribuição."
    fi

    info "Kernel: $(uname -r)"
    info "Architecture: $(uname -m)"
    info "CPU cores: $(nproc)"

    if command -v free >/dev/null 2>&1; then
        free -h
    fi

    info "Uptime: $(uptime -p 2>/dev/null || uptime)"

    if grep -qi microsoft /proc/version 2>/dev/null; then

        info "Ambiente: WSL"

        if command -v wsl.exe >/dev/null 2>&1; then
            info "WSL detectado."
        fi

    else

        info "Ambiente: Linux nativo/VM."
    fi
}

# ============================================================
# RESOURCE DIAGNOSTICS
# ============================================================

diagnose_resources() {

    section "2. RESOURCE / CAPACITY ANALYSIS"

    check "Disk space"

    df -h | tee -a "$REPORT_FILE"

    local root_usage

    root_usage="$(df / | awk 'NR==2 {gsub("%","",$5); print $5}')"

    if [[ "$root_usage" -ge 90 ]]; then

        warning "Filesystem / está acima de 90%."

        evidence "Uso de / = ${root_usage}%."

        cause "Falta de espaço em disco pode impedir Docker, logs, builds, databases e pipelines."

        action "Executar: docker system df"
        action "Remover recursos Docker não utilizados."
        action "Investigar diretórios grandes com: sudo du -xh /var | sort -h | tail"
    else

        success "Espaço em disco dentro de limites aceitáveis."
    fi

    check "Inodes"

    df -ih | tee -a "$REPORT_FILE"

    check "Memory pressure"

    if command -v free >/dev/null 2>&1; then

        free -h

        local mem_available

        mem_available="$(free | awk '/Mem:/ {print $7}')"

        if [[ "$mem_available" -lt 500000 ]]; then

            warning "Memória disponível muito baixa."

            cause "Possível pressão de memória (memory pressure)."

            action "Investigar processos com: ps aux --sort=-%mem | head"
            action "Verificar containers Docker."
            action "Verificar limites de memória do WSL/VM."
        fi
    fi
}

# ============================================================
# NETWORK
# ============================================================

diagnose_network() {

    section "3. NETWORK DEEP DIAGNOSTICS"

    check "Network interfaces"

    ip -br addr 2>/dev/null || true

    check "Default route"

    ip route | tee -a "$REPORT_FILE"

    if ! ip route | grep -q '^default'; then

        error "Default route não encontrada."

        evidence "ip route não apresenta default gateway."

        cause "A máquina provavelmente não consegue aceder à Internet ou a outras redes."

        action "Verificar configuração da interface."
        action "Verificar WSL networking / VM NAT."
    fi

    check "DNS"

    if command -v getent >/dev/null 2>&1; then

        if getent hosts google.com >/dev/null 2>&1; then

            success "DNS funcionando."

        else

            error "Falha na resolução DNS."

            evidence "getent hosts google.com falhou."

            cause "Problema de DNS, resolv.conf, rede ou configuração do WSL."

            action "Verificar /etc/resolv.conf."
            action "Testar: ping 8.8.8.8"
            action "Testar: getent hosts registry-1.docker.io"
        fi
    fi

    check "Internet HTTPS"

    if curl -fsSI --max-time 10 https://www.google.com >/dev/null 2>&1; then

        success "HTTPS funcional."

    else

        error "HTTPS indisponível."

        cause "Problema de conectividade, proxy, firewall, DNS ou rota."

        action "Executar: curl -v https://www.google.com"
    fi

    check "Docker Registry connectivity"

    if curl -fsSI --max-time 10 https://registry-1.docker.io >/dev/null 2>&1; then

        success "Docker Registry acessível."

    else

        warning "Docker Registry não respondeu ao teste HTTP."

        evidence "registry-1.docker.io não respondeu ao curl."

        cause "Pode existir bloqueio de rede, proxy, DNS ou o endpoint pode não responder ao método HTTP utilizado."

        action "Testar diretamente: docker pull hello-world"
    fi
}

# ============================================================
# PORT DIAGNOSTICS
# ============================================================

check_port() {

    local host="$1"
    local port="$2"

    if command -v nc >/dev/null 2>&1; then

        nc -z -w 3 "$host" "$port" >/dev/null 2>&1
        return $?

    fi

    if timeout 3 bash -c "</dev/tcp/${host}/${port}" >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

diagnose_ports() {

    section "4. LISTENING PORTS"

    check "Listening sockets"

    ss -tulpn 2>/dev/null | tee -a "$REPORT_FILE"

    log ""

    local ports=(22 80 443 3000 9090)

    for port in "${ports[@]}"; do

        if check_port 127.0.0.1 "$port"; then

            success "Porta ${port} está aberta."

        else

            info "Porta ${port} não está aberta."
        fi

    done
}

# ============================================================
# TOOL DIAGNOSTICS
# ============================================================

diagnose_tools() {

    section "5. DEVOPS TOOLCHAIN"

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

        if command -v "$tool" >/dev/null 2>&1; then

            local version=""

            case "$tool" in

                kubectl)
                    version="$(kubectl version --client 2>/dev/null | head -1 || true)"
                    ;;

                java)
                    version="$(java -version 2>&1 | head -1 || true)"
                    ;;

                ansible)
                    version="$(ansible --version 2>/dev/null | head -1 || true)"
                    ;;

                *)
                    version="$("$tool" --version 2>&1 | head -1 || true)"
                    ;;
            esac

            success "$tool: ${version}"

        else

            skip "$tool não instalado."

        fi
    done
}

# ============================================================
# GIT
# ============================================================

diagnose_git() {

    section "6. GIT / GITHUB DEEP DIAGNOSTICS"

    if ! command -v git >/dev/null 2>&1; then

        skip "Git não instalado."
        return
    fi

    check "Git identity"

    info "user.name: $(git config --global user.name 2>/dev/null || echo 'not configured')"
    info "user.email: $(git config --global user.email 2>/dev/null || echo 'not configured')"

    if [[ -d .git ]]; then

        info "Git repository detectado."

        git status --short | tee -a "$REPORT_FILE"

        info "Remote:"
        git remote -v | tee -a "$REPORT_FILE"

    else

        skip "Diretório atual não é um Git repository."
    fi

    if command -v ssh >/dev/null 2>&1; then

        check "GitHub SSH authentication"

        local ssh_output

        ssh_output="$(ssh -T -o ConnectTimeout=10 git@github.com 2>&1 || true)"

        echo "$ssh_output" | tee -a "$REPORT_FILE"

        if echo "$ssh_output" | grep -qi "successfully authenticated"; then

            success "Autenticação SSH com GitHub funcionando."

        elif echo "$ssh_output" | grep -qi "permission denied"; then

            error "GitHub rejeitou a autenticação SSH."

            evidence "$ssh_output"

            cause "Chave SSH ausente, não carregada, incorreta ou não associada à conta GitHub."

            action "Executar: ssh-add -l"
            action "Verificar ~/.ssh/"
            action "Testar: ssh -vT git@github.com"

        else

            warning "Resultado SSH inconclusivo."
        fi
    fi
}

# ============================================================
# SSH
# ============================================================

diagnose_ssh() {

    section "7. SSH"

    if ! command -v ssh >/dev/null 2>&1; then

        skip "SSH client não instalado."
        return
    fi

    success "SSH client instalado."

    info "SSH version:"
    ssh -V 2>&1 | tee -a "$REPORT_FILE"

    if command -v systemctl >/dev/null 2>&1; then

        if systemctl is-active --quiet ssh 2>/dev/null; then

            success "SSH service está ativo."

        elif systemctl is-active --quiet sshd 2>/dev/null; then

            success "SSHD service está ativo."

        else

            warning "SSH service não está ativo ou não é gerido pelo systemd."

            evidence "systemctl não reportou ssh/sshd como ativo."

            action "Em WSL, confirmar se realmente precisa do serviço SSH."
            action "Em servidor Linux, verificar: sudo systemctl status ssh"
        fi
    else

        info "systemctl não disponível — provável WSL sem systemd."
    fi
}

# ============================================================
# DOCKER
# ============================================================

diagnose_docker() {

    section "8. DOCKER DEEP DIAGNOSTICS"

    if ! command -v docker >/dev/null 2>&1; then

        skip "Docker não instalado."
        return
    fi

    success "Docker CLI encontrado."

    info "Docker version:"
    docker version 2>&1 | tee -a "$REPORT_FILE" || true

    check "Docker daemon"

    if docker info >/dev/null 2>&1; then

        success "Docker daemon acessível pelo utilizador."

    else

        warning "Docker daemon não está acessível diretamente."

        evidence "docker info falhou sem sudo."

        if sudo -n true >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then

            cause "O daemon funciona, mas o utilizador atual provavelmente não tem acesso ao socket Docker."

            action "Verificar grupo docker: groups"
            action "Adicionar utilizador: sudo usermod -aG docker \$USER"
            action "Terminar e iniciar sessão novamente."

        else

            cause "Docker daemon pode estar parado ou indisponível."

            action "Verificar: sudo systemctl status docker"
            action "Verificar: sudo journalctl -u docker --no-pager -n 100"
        fi
    fi

    check "Docker socket"

    if [[ -S /var/run/docker.sock ]]; then

        success "Docker socket existe."

        ls -l /var/run/docker.sock | tee -a "$REPORT_FILE"

    else

        error "Docker socket não encontrado."

        cause "Docker daemon provavelmente não está iniciado ou o socket está configurado noutro local."

        action "Verificar Docker context."
        action "Executar: docker context ls"
    fi

    check "Docker containers"

    docker ps -a 2>&1 | tee -a "$REPORT_FILE"

    check "Docker storage"

    docker system df 2>&1 | tee -a "$REPORT_FILE"

    check "Docker connectivity"

    if docker pull hello-world >/dev/null 2>&1; then

        success "Docker consegue comunicar com registry e fazer pull."

    else

        error "Docker não conseguiu fazer pull de hello-world."

        evidence "docker pull hello-world falhou."

        cause "Possível problema de DNS, conectividade, autenticação, proxy, TLS ou Docker daemon."

        action "Executar: docker pull hello-world"
        action "Executar: docker info"
        action "Executar: getent hosts registry-1.docker.io"
    fi
}

# ============================================================
# DOCKER CONTAINER FAILURE ANALYSIS
# ============================================================

diagnose_failed_containers() {

    section "9. DOCKER CONTAINER FAILURE ANALYSIS"

    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker não disponível."
        return
    fi

    local containers

    containers="$(docker ps -aq 2>/dev/null || true)"

    if [[ -z "$containers" ]]; then

        info "Nenhum container encontrado."
        return
    fi

    while read -r container; do

        [[ -z "$container" ]] && continue

        local name
        local status
        local exit_code
        local restart_count

        name="$(docker inspect --format '{{.Name}}' "$container" 2>/dev/null | sed 's#^/##')"
        status="$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null || echo unknown)"
        exit_code="$(docker inspect --format '{{.State.ExitCode}}' "$container" 2>/dev/null || echo unknown)"
        restart_count="$(docker inspect --format '{{.RestartCount}}' "$container" 2>/dev/null || echo unknown)"

        if [[ "$status" == "running" ]]; then

            success "$name está running."

        else

            warning "$name está ${status}."

            evidence "Status=${status}, ExitCode=${exit_code}, RestartCount=${restart_count}"

            if [[ "$restart_count" != "0" ]]; then

                cause "Container apresenta reinícios — possível crash da aplicação, configuração inválida, dependência indisponível ou healthcheck falhando."

                action "Ver logs: docker logs $name"
                action "Ver estado: docker inspect $name"
            fi

            if [[ "$exit_code" != "0" && "$exit_code" != "unknown" ]]; then

                cause "Container terminou com exit code ${exit_code}."

                action "Executar: docker logs $name --tail 200"
            fi
        fi

    done <<< "$containers"
}

# ============================================================
# DOCKER COMPOSE
# ============================================================

diagnose_compose() {

    section "10. DOCKER COMPOSE"

    if ! docker compose version >/dev/null 2>&1; then

        skip "Docker Compose plugin não disponível."
        return
    fi

    success "$(docker compose version)"

    if [[ -f "${MONITORING_DIR}/docker-compose.yml" ]]; then

        check "Monitoring Compose configuration"

        if docker compose \
            -f "${MONITORING_DIR}/docker-compose.yml" \
            config >/dev/null 2>&1; then

            success "docker-compose.yml válido."

        else

            error "docker-compose.yml inválido."

            evidence "docker compose config retornou erro."

            cause "Erro de YAML, variável inexistente, volume inválido, rede inválida ou configuração incorreta."

            action "Executar:"
            action "docker compose -f ${MONITORING_DIR}/docker-compose.yml config"
        fi

    else

        skip "Compose do monitoring não encontrado em ${MONITORING_DIR}."
    fi
}

# ============================================================
# PROMETHEUS
# ============================================================

diagnose_prometheus() {

    section "11. PROMETHEUS DEEP DIAGNOSTICS"

    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker não disponível."
        return
    fi

    local prometheus_container=""

    prometheus_container="$(docker ps --format '{{.Names}}' 2>/dev/null |
        grep -Ei 'prometheus' |
        head -1 || true)"

    if [[ -z "$prometheus_container" ]]; then

        warning "Container Prometheus não encontrado."

        cause "Prometheus pode não estar instalado, pode estar parado ou pode ter outro nome."

        action "Executar: docker ps -a"
        return
    fi

    success "Prometheus encontrado: ${prometheus_container}"

    check "Prometheus HTTP"

    if curl -fsS --max-time 5 \
        "http://127.0.0.1:${PROMETHEUS_PORT}/-/ready" \
        >/dev/null 2>&1; then

        success "Prometheus está READY."

    else

        error "Prometheus não está READY."

        evidence "Endpoint /-/ready não respondeu corretamente."

        cause "Prometheus pode estar parado, inicializando, com configuração inválida ou com problema de storage."

        action "docker logs ${prometheus_container} --tail 200"
    fi

    check "Prometheus targets"

    local targets

    targets="$(curl -fsS \
        "http://127.0.0.1:${PROMETHEUS_PORT}/api/v1/targets" \
        2>/dev/null || true)"

    if [[ -n "$targets" ]]; then

        echo "$targets" | jq '.' 2>/dev/null |
            tee -a "$REPORT_FILE" || true

        local down_targets

        down_targets="$(echo "$targets" |
            jq '[.data.activeTargets[] | select(.health != "up")] | length' \
            2>/dev/null || echo 0)"

        if [[ "$down_targets" -gt 0 ]]; then

            warning "${down_targets} Prometheus target(s) estão DOWN."

            evidence "API /api/v1/targets reportou targets com health != up."

            cause "Exporter indisponível, endpoint incorreto, DNS/rede, firewall ou serviço alvo parado."

            action "Abrir Prometheus → Status → Targets."
            action "Verificar exporter correspondente."
            action "Testar endpoint manualmente."
        else

            success "Todos os targets ativos estão UP."
        fi
    fi

    if [[ -f "${MONITORING_DIR}/prometheus/prometheus.yml" ]]; then

        check "Prometheus configuration"

        if docker exec "$prometheus_container" \
            promtool check config /etc/prometheus/prometheus.yml \
            >/dev/null 2>&1; then

            success "Prometheus configuration válida."

        else

            error "Prometheus configuration inválida."

            cause "Erro de YAML ou configuração de scrape/rules."

            action "Executar promtool check config."
        fi
    fi
}

# ============================================================
# GRAFANA
# ============================================================

diagnose_grafana() {

    section "12. GRAFANA DEEP DIAGNOSTICS"

    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker não disponível."
        return
    fi

    local grafana_container

    grafana_container="$(docker ps --format '{{.Names}}' 2>/dev/null |
        grep -Ei 'grafana' |
        head -1 || true)"

    if [[ -z "$grafana_container" ]]; then

        warning "Container Grafana não encontrado."

        cause "Grafana pode estar parado ou não instalado."

        action "Executar: docker ps -a"
        return
    fi

    success "Grafana encontrado: ${grafana_container}"

    if curl -fsS --max-time 5 \
        "http://127.0.0.1:${GRAFANA_PORT}/api/health" \
        >/dev/null 2>&1; then

        success "Grafana API está saudável."

    else

        error "Grafana API não respondeu."

        evidence "GET /api/health falhou."

        cause "Grafana pode estar parado, com erro de inicialização, porta incorreta ou dependência indisponível."

        action "docker logs ${grafana_container} --tail 200"
    fi
}

# ============================================================
# MONITORING LOG ANALYSIS
# ============================================================

diagnose_monitoring_logs() {

    section "13. MONITORING LOG ANALYSIS"

    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker não disponível."
        return
    fi

    local containers=(
        prometheus
        grafana
        node-exporter
        cadvisor
        alertmanager
        loki
    )

    for pattern in "${containers[@]}"; do

        local container

        container="$(docker ps --format '{{.Names}}' |
            grep -Ei "$pattern" |
            head -1 || true)"

        if [[ -z "$container" ]]; then
            continue
        fi

        info "Analisando logs de ${container}"

        local logs

        logs="$(docker logs "$container" --tail 100 2>&1 || true)"

        echo "$logs" |
            grep -Ei \
            'error|fatal|panic|failed|failure|timeout|connection refused|no such host|permission denied' |
            tail -30 |
            tee -a "$REPORT_FILE" || true

    done
}

# ============================================================
# KUBERNETES
# ============================================================

diagnose_kubernetes() {

    section "14. KUBERNETES"

    if ! command -v kubectl >/dev/null 2>&1; then

        skip "kubectl não instalado — Kubernetes ainda não configurado."

        return
    fi

    success "kubectl instalado."

    check "Kubernetes cluster"

    if kubectl cluster-info >/dev/null 2>&1; then

        success "Cluster Kubernetes acessível."

        kubectl get nodes -o wide |
            tee -a "$REPORT_FILE"

        kubectl get pods -A |
            tee -a "$REPORT_FILE"

        local not_ready

        not_ready="$(kubectl get nodes --no-headers 2>/dev/null |
            awk '$2 != "Ready" {count++} END {print count+0}')"

        if [[ "$not_ready" -gt 0 ]]; then

            warning "${not_ready} node(s) não estão Ready."

            cause "Problema no kubelet, runtime, rede, recursos ou estado do node."

            action "kubectl describe node <node>"
            action "kubectl get events -A --sort-by=.lastTimestamp"
        fi

    else

        warning "kubectl instalado mas nenhum cluster acessível."

        evidence "kubectl cluster-info falhou."

        cause "Kubernetes ainda não configurado, kubeconfig ausente ou cluster indisponível."

        action "Executar: kubectl config get-contexts"
        action "Executar: kubectl config current-context"
    fi
}

# ============================================================
# TERRAFORM
# ============================================================

diagnose_terraform() {

    section "15. TERRAFORM"

    if ! command -v terraform >/dev/null 2>&1; then

        skip "Terraform não instalado."
        return
    fi

    success "$(terraform version | head -1)"

    if [[ -f "main.tf" ]]; then

        check "Terraform configuration"

        if terraform validate >/dev/null 2>&1; then

            success "Terraform configuration válida."

        else

            error "Terraform validate falhou."

            evidence "$(terraform validate 2>&1 | tail -20)"

            cause "Erro de sintaxe, provider, variável ou estrutura Terraform."

            action "Executar: terraform validate"
            action "Executar: terraform fmt -check"
        fi
    else

        skip "Nenhum main.tf encontrado no diretório atual."
    fi
}

# ============================================================
# ANSIBLE
# ============================================================

diagnose_ansible() {

    section "16. ANSIBLE"

    if ! command -v ansible >/dev/null 2>&1; then

        skip "Ansible não instalado."
        return
    fi

    success "Ansible instalado."

    ansible --version | head -5 | tee -a "$REPORT_FILE"

    if [[ -f "inventory" ]]; then

        check "Ansible inventory"

        if ansible-inventory \
            -i inventory \
            --graph >/dev/null 2>&1; then

            success "Inventory válido."

            ansible-inventory -i inventory --graph |
                tee -a "$REPORT_FILE"

        else

            error "Ansible inventory inválido."

            cause "Problema no formato do inventory ou configuração de hosts."

            action "Executar: ansible-inventory -i inventory --graph"
        fi
    else

        skip "Inventory não encontrado."
    fi
}

# ============================================================
# SYSTEM SERVICES
# ============================================================

diagnose_services() {

    section "17. SYSTEM SERVICES"

    if ! command -v systemctl >/dev/null 2>&1; then

        skip "systemctl não disponível."
        return
    fi

    local services=(
        docker
        ssh
        cron
        nginx
    )

    for service in "${services[@]}"; do

        if systemctl list-unit-files |
            grep -q "^${service}.service"; then

            if systemctl is-active --quiet "$service"; then

                success "${service}: active"

            else

                warning "${service}: inactive/failed"

                evidence "$(systemctl status "$service" --no-pager -n 10 2>&1 | tail -10)"

                cause "${service} está instalado mas não está operacional."

                action "Executar: sudo systemctl status ${service}"
                action "Executar: sudo journalctl -u ${service} -n 100"
            fi
        fi
    done
}

# ============================================================
# JOURNAL ERRORS
# ============================================================

diagnose_system_errors() {

    section "18. SYSTEM ERROR ANALYSIS"

    if ! command -v journalctl >/dev/null 2>&1; then

        skip "journalctl não disponível."
        return
    fi

    check "Recent system errors"

    journalctl \
        -p err \
        --since "24 hours ago" \
        --no-pager \
        2>/dev/null |
        tail -100 |
        tee -a "$REPORT_FILE" || true
}

# ============================================================
# ENVIRONMENT
# ============================================================

diagnose_environment() {

    section "19. ENVIRONMENT VARIABLES"

    env |
        grep -Ei \
        'PATH|DOCKER|KUBE|KUBECONFIG|AWS|AZURE|GCP|JAVA|NODE|PYTHON|TERRAFORM|ANSIBLE' |
        sort |
        tee -a "$REPORT_FILE" || true
}

# ============================================================
# ROOT CAUSE SUMMARY
# ============================================================

generate_summary() {

    section "20. ROOT CAUSE ANALYSIS SUMMARY"

    log ""
    log "${MAGENTA}Diagnostic counters:${RESET}"
    log "Checks:       ${CHECKS}"
    log "Warnings:     ${WARNINGS}"
    log "Errors:       ${ERRORS}"
    log "Root causes:  ${ROOT_CAUSES}"

    log ""

    if [[ "$ERRORS" -eq 0 && "$WARNINGS" -eq 0 ]]; then

        success "Nenhum problema significativo detectado."

    elif [[ "$ERRORS" -eq 0 ]]; then

        warning "Ambiente funcional, mas existem pontos de atenção."

    else

        error "Foram encontrados problemas que necessitam investigação."
    fi

    log ""

    log "${CYAN}PRIORITY ORDER${RESET}"

    log "1. Network / DNS"
    log "2. Disk / Memory"
    log "3. Docker daemon"
    log "4. Containers"
    log "5. Docker Compose"
    log "6. Prometheus"
    log "7. Grafana"
    log "8. Kubernetes"
    log "9. Terraform / Ansible"
    log "10. Application layer"

    log ""

    log "Report:"
    log "$REPORT_FILE"

    log "Log:"
    log "$LOG_FILE"
}

# ============================================================
# MAIN
# ============================================================

main() {

    setup_environment

    show_header

    diagnose_system

    diagnose_resources

    diagnose_network

    diagnose_ports

    diagnose_tools

    diagnose_git

    diagnose_ssh

    diagnose_docker

    diagnose_failed_containers

    diagnose_compose

    diagnose_prometheus

    diagnose_grafana

    diagnose_monitoring_logs

    diagnose_kubernetes

    diagnose_terraform

    diagnose_ansible

    diagnose_services

    diagnose_system_errors

    diagnose_environment

    generate_summary
}

main "$@"
