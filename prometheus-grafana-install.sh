#!/usr/bin/env bash

# ============================================================
# Prometheus + Grafana Docker Installer
# ============================================================
#
# Instala e configura:
#   - Prometheus
#   - Grafana
#
# Pré-requisitos:
#   - Ubuntu/Debian
#   - Docker Engine
#   - Docker Compose Plugin
#
# Características:
#   - Verificação do sistema
#   - Verificação do Docker
#   - Teste real do Docker Engine
#   - Instalação idempotente
#   - Persistent volumes
#   - Prometheus configuration
#   - Grafana provisioning
#   - Health checks
#   - Logs
#
# ============================================================

set -Eeuo pipefail

# ============================================================
# CONFIGURAÇÃO
# ============================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="1.0.0"

readonly PROJECT_NAME="monitoring"

readonly BASE_DIR="/opt/${PROJECT_NAME}"
readonly PROMETHEUS_DIR="${BASE_DIR}/prometheus"
readonly GRAFANA_DIR="${BASE_DIR}/grafana"

readonly PROMETHEUS_CONFIG="${PROMETHEUS_DIR}/prometheus.yml"
readonly COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"

readonly LOG_DIR="/var/log/${PROJECT_NAME}"
readonly LOG_FILE="${LOG_DIR}/install.log"

readonly PROMETHEUS_CONTAINER="prometheus"
readonly GRAFANA_CONTAINER="grafana"

readonly PROMETHEUS_PORT="9090"
readonly GRAFANA_PORT="3000"

readonly GRAFANA_ADMIN_USER="admin"
readonly GRAFANA_ADMIN_PASSWORD="admin"

readonly DOCKER_NETWORK="monitoring"

readonly PROMETHEUS_VOLUME="prometheus_data"
readonly GRAFANA_VOLUME="grafana_data"

readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
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
    fi

    sudo chown "$(id -un)":"$(id -gn)" "$LOG_FILE"
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
# ERROR HANDLER
# ============================================================

error_handler() {

    local exit_code=$?

    error "O script terminou com erro."
    error "Código: ${exit_code}"
    error "Linha: ${BASH_LINENO[0]}"

    log "ERROR" "Script failed with exit code ${exit_code}"

    exit "${exit_code}"
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
# HEADER
# ============================================================

show_header() {

    clear 2>/dev/null || true

    echo
    echo "============================================================"
    echo "       PROMETHEUS + GRAFANA DOCKER INSTALLER"
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
# SUDO
# ============================================================

check_sudo() {

    section "CHECKING SUDO"

    if ! command -v sudo >/dev/null 2>&1; then

        error "sudo não está instalado."

        exit 1
    fi

    if ! sudo -v; then

        error "Não foi possível obter privilégios sudo."

        exit 1
    fi

    success "Privilégios sudo disponíveis."
}

# ============================================================
# OPERATING SYSTEM
# ============================================================

check_os() {

    section "OPERATING SYSTEM"

    if [[ ! -f /etc/os-release ]]; then

        error "/etc/os-release não encontrado."

        exit 1
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    echo "OS           : ${PRETTY_NAME}"
    echo "Kernel       : $(uname -r)"
    echo "Architecture : $(uname -m)"

    case "${ID:-}" in

        ubuntu|debian)

            success "Sistema operativo suportado."
            ;;

        *)

            warning "O sistema não foi validado oficialmente por este script."
            warning "Detectado: ${PRETTY_NAME}"
            ;;
    esac
}

# ============================================================
# SYSTEM RESOURCES
# ============================================================

check_resources() {

    section "SYSTEM RESOURCES"

    local total_ram
    local available_disk

    total_ram="$(free -m | awk '/^Mem:/ {print $2}')"

    available_disk="$(df -Pm / | awk 'NR==2 {print $4}')"

    echo "CPU cores       : $(nproc)"
    echo "RAM             : ${total_ram} MB"
    echo "Available disk  : ${available_disk} MB"

    if (( total_ram < 2048 )); then

        warning "RAM inferior a 2 GB."
        warning "Grafana + Prometheus poderão funcionar lentamente."

    else

        success "RAM adequada para o laboratório."
    fi

    if (( available_disk < 10240 )); then

        error "Espaço livre inferior a 10 GB."

        exit 1

    else

        success "Espaço disponível suficiente."
    fi
}

# ============================================================
# NETWORK CONNECTIVITY
# ============================================================

check_network() {

    section "NETWORK CONNECTIVITY"

    if ! command -v curl >/dev/null 2>&1; then

        error "curl não está instalado."

        exit 1
    fi

    info "A testar conectividade HTTPS..."

    if curl -fsS \
        --connect-timeout 10 \
        --max-time 20 \
        https://www.google.com \
        >/dev/null 2>&1; then

        success "Conectividade HTTPS disponível."

    else

        error "Não existe conectividade HTTPS."

        exit 1
    fi
}

# ============================================================
# DOCKER INSTALLATION CHECK
# ============================================================

check_docker_installed() {

    section "DOCKER CHECK"

    if ! command -v docker >/dev/null 2>&1; then

        error "Docker não está instalado."

        echo
        echo "Instale o Docker antes de executar este script."
        echo
        echo "Exemplo:"
        echo
        echo "    docker --version"
        echo
        echo "O seu devops-tools.sh já pode instalar o Docker."

        exit 1
    fi

    success "Docker encontrado."

    docker --version
}

# ============================================================
# DOCKER COMPOSE CHECK
# ============================================================

check_docker_compose() {

    if ! docker compose version >/dev/null 2>&1; then

        error "Docker Compose Plugin não está disponível."

        echo
        echo "Execute:"
        echo
        echo "    docker compose version"
        echo

        exit 1
    fi

    success "Docker Compose disponível."

    docker compose version
}

# ============================================================
# DOCKER SERVICE
# ============================================================

check_docker_service() {

    section "DOCKER SERVICE"

    if ! systemctl is-active --quiet docker; then

        warning "Docker está instalado mas não está activo."

        info "A iniciar Docker..."

        sudo systemctl enable docker
        sudo systemctl start docker

    fi

    if systemctl is-active --quiet docker; then

        success "Docker service está RUNNING."

    else

        error "Docker service não está operacional."

        sudo systemctl status docker --no-pager

        exit 1
    fi
}

# ============================================================
# DOCKER FUNCTIONAL TEST
# ============================================================

test_docker_engine() {

    section "DOCKER ENGINE TEST"

    if docker info >/dev/null 2>&1; then

        success "Docker Engine está operacional."

        return 0
    fi

    warning "Docker não está acessível pelo utilizador actual."

    if sudo docker info >/dev/null 2>&1; then

        warning "Docker funciona através de sudo."

        warning "O utilizador actual pode ainda não pertencer ao grupo docker."

        info "A adicionar utilizador ao grupo docker..."

        sudo usermod -aG docker "$(id -un)"

        warning "Será necessário terminar sessão e iniciar sessão novamente."

        export DOCKER_SUDO="true"

    else

        error "Docker Engine não está operacional."

        exit 1
    fi
}

# =======================================================
# DOCKER REGISTRY TEST
# =======================================================

test_docker_registry() {

    section "DOCKER REGISTRY TEST"

    info "A testar acesso ao Docker Hub através do Docker..."

    if docker_cmd pull hello-world >/dev/null 2>&1; then

        success "Docker consegue comunicar com o Docker Hub."

    else

        error "Docker não conseguiu descarregar uma imagem do Docker Hub."

        echo
        echo "Possíveis causas:"
        echo "  - Falha de Internet"
        echo "  - DNS"
        echo "  - Firewall"
        echo "  - Proxy"
        echo "  - Docker daemon"
        echo "  - Docker Hub indisponível"
        echo

        exit 1
    fi
}


# ============================================================
# DOCKER COMMAND WRAPPER
# ============================================================

docker_cmd() {

    if [[ "${DOCKER_SUDO:-false}" == "true" ]]; then

        sudo docker "$@"

    else

        docker "$@"
    fi
}

# ============================================================
# COMPOSE COMMAND WRAPPER
# ============================================================

compose_cmd() {

    if [[ "${DOCKER_SUDO:-false}" == "true" ]]; then

        sudo docker compose "$@"

    else

        docker compose "$@"
    fi
}

# ============================================================
# DIRECTORY STRUCTURE
# ============================================================

create_directories() {

    section "DIRECTORY STRUCTURE"

    sudo mkdir -p \
        "$PROMETHEUS_DIR" \
        "$GRAFANA_DIR/provisioning/datasources"

    sudo chown -R "$(id -un)":"$(id -gn)" "$BASE_DIR"

    success "Estrutura criada em:"
    echo
    echo "    ${BASE_DIR}"
    echo "    ├── prometheus/"
    echo "    ├── grafana/"
    echo "    │   └── provisioning/"
    echo "    └── docker-compose.yml"
}

# ============================================================
# PROMETHEUS CONFIGURATION
# ============================================================

create_prometheus_config() {

    section "PROMETHEUS CONFIGURATION"

    cat > "$PROMETHEUS_CONFIG" <<'EOF'
global:

  scrape_interval: 15s

  evaluation_interval: 15s


scrape_configs:

  - job_name: "prometheus"

    static_configs:

      - targets:
          - "prometheus:9090"
EOF

    success "prometheus.yml criado."

    echo
    cat "$PROMETHEUS_CONFIG"
}

# ============================================================
# GRAFANA DATASOURCE
# ============================================================

create_grafana_datasource() {

    section "GRAFANA DATASOURCE"

    local datasource_file

    datasource_file="${GRAFANA_DIR}/provisioning/datasources/prometheus.yml"

    cat > "$datasource_file" <<'EOF'
apiVersion: 1

datasources:

  - name: Prometheus

    type: prometheus

    access: proxy

    url: http://prometheus:9090

    isDefault: true

    editable: true
EOF

    success "Grafana será configurado automaticamente com Prometheus."
}

# ============================================================
# DOCKER NETWORK
# ============================================================

create_docker_network() {

    section "DOCKER NETWORK"

    if docker_cmd network inspect "$DOCKER_NETWORK" \
        >/dev/null 2>&1; then

        success "Docker network '${DOCKER_NETWORK}' já existe."

    else

        docker_cmd network create "$DOCKER_NETWORK"

        success "Docker network criada."
    fi
}

# ============================================================
# DOCKER VOLUMES
# ============================================================

create_volumes() {

    section "PERSISTENT VOLUMES"

    if docker_cmd volume inspect "$PROMETHEUS_VOLUME" \
        >/dev/null 2>&1; then

        success "Volume ${PROMETHEUS_VOLUME} já existe."

    else

        docker_cmd volume create "$PROMETHEUS_VOLUME"

        success "Volume ${PROMETHEUS_VOLUME} criado."
    fi

    if docker_cmd volume inspect "$GRAFANA_VOLUME" \
        >/dev/null 2>&1; then

        success "Volume ${GRAFANA_VOLUME} já existe."

    else

        docker_cmd volume create "$GRAFANA_VOLUME"

        success "Volume ${GRAFANA_VOLUME} criado."
    fi
}

# ============================================================
# DOCKER COMPOSE FILE
# ============================================================

create_compose_file() {

    section "DOCKER COMPOSE"

    cat > "$COMPOSE_FILE" <<'EOF'
services:

  prometheus:

    image: prom/prometheus:latest

    container_name: prometheus

    restart: unless-stopped

    ports:
      - "9090:9090"

    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus

    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"

    networks:
      - monitoring


  grafana:

    image: grafana/grafana:latest

    container_name: grafana

    restart: unless-stopped

    ports:
      - "3000:3000"

    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: admin

    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro

    depends_on:
      - prometheus

    networks:
      - monitoring


networks:

  monitoring:

    external: true


volumes:

  prometheus_data:

    external: true

  grafana_data:

    external: true
EOF

    success "docker-compose.yml criado."
}

# ============================================================
# CONFIGURATION VALIDATION
# ============================================================

validate_compose() {

    section "COMPOSE VALIDATION"

    compose_cmd \
        -f "$COMPOSE_FILE" \
        config \
        >/dev/null

    success "Docker Compose configuration válida."
}

# ============================================================
# PROMETHEUS IMAGE
# ============================================================

pull_images() {

    section "DOCKER IMAGES"

    info "A descarregar Prometheus..."

    docker_cmd pull prom/prometheus:latest

    success "Prometheus image disponível."

    info "A descarregar Grafana..."

    docker_cmd pull grafana/grafana:latest

    success "Grafana image disponível."
}

# ============================================================
# START STACK
# ============================================================

start_stack() {

    section "STARTING MONITORING STACK"

    compose_cmd \
        -f "$COMPOSE_FILE" \
        up -d

    success "Prometheus + Grafana iniciados."
}

# ============================================================
# CONTAINER STATUS
# ============================================================

check_containers() {

    section "CONTAINER STATUS"

    echo

    docker_cmd ps \
        --filter "name=${PROMETHEUS_CONTAINER}" \
        --filter "name=${GRAFANA_CONTAINER}" \
        --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# ============================================================
# HTTP HEALTH CHECK
# ============================================================

check_http_services() {

    section "HTTP HEALTH CHECK"

    local prometheus_ready=false
    local grafana_ready=false

    for attempt in {1..30}; do

        if curl -fsS \
            "http://127.0.0.1:${PROMETHEUS_PORT}/-/ready" \
            >/dev/null 2>&1; then

            prometheus_ready=true

            break
        fi

        sleep 2
    done

    if [[ "$prometheus_ready" == "true" ]]; then

        success "Prometheus HTTP endpoint está READY."

    else

        error "Prometheus não ficou READY."

        docker_cmd logs \
            --tail 50 \
            "$PROMETHEUS_CONTAINER"

        exit 1
    fi


    for attempt in {1..30}; do

        if curl -fsS \
            "http://127.0.0.1:${GRAFANA_PORT}/api/health" \
            >/dev/null 2>&1; then

            grafana_ready=true

            break
        fi

        sleep 2
    done

    if [[ "$grafana_ready" == "true" ]]; then

        success "Grafana HTTP endpoint está READY."

    else

        error "Grafana não ficou READY."

        docker_cmd logs \
            --tail 50 \
            "$GRAFANA_CONTAINER"

        exit 1
    fi
}

# ============================================================
# PROMETHEUS TARGET CHECK
# ============================================================

check_prometheus_targets() {

    section "PROMETHEUS TARGETS"

    local response

    response="$(
        curl -fsS \
        "http://127.0.0.1:${PROMETHEUS_PORT}/api/v1/targets"
    )"

    if echo "$response" | grep -q '"health":"up"'; then

        success "Prometheus está a monitorizar pelo menos um target."

    else

        warning "Prometheus está operacional, mas não existem targets UP."
    fi
}

# ============================================================
# FINAL REPORT
# ============================================================

show_summary() {

    section "INSTALLATION COMPLETE"

    local ip_address

    ip_address="$(
        hostname -I \
        | awk '{print $1}'
    )"

    echo
    echo "Monitoring Stack"
    echo "----------------"
    echo
    echo "Prometheus:"
    echo "  URL: http://${ip_address}:${PROMETHEUS_PORT}"
    echo
    echo "Grafana:"
    echo "  URL: http://${ip_address}:${GRAFANA_PORT}"
    echo "  User: ${GRAFANA_ADMIN_USER}"
    echo "  Password: ${GRAFANA_ADMIN_PASSWORD}"
    echo
    echo "Project:"
    echo "  ${BASE_DIR}"
    echo
    echo "Compose:"
    echo "  ${COMPOSE_FILE}"
    echo
    echo "Log:"
    echo "  ${LOG_FILE}"
    echo
    echo "Useful commands:"
    echo
    echo "  cd ${BASE_DIR}"
    echo "  docker compose ps"
    echo "  docker compose logs -f"
    echo "  docker compose restart"
    echo "  docker compose down"
    echo
    echo "============================================================"
    echo
}

# ============================================================
# MAIN
# ============================================================

main() {

    show_header

    setup_logging

    log "INFO" "Starting Prometheus + Grafana installation"

    check_sudo

    check_os

    check_resources

    check_network

    check_docker_installed

    check_docker_compose

    check_docker_service

    test_docker_engine

    create_directories

    create_prometheus_config

    create_grafana_datasource

    create_docker_network

    create_volumes

    create_compose_file

    validate_compose

    pull_images

    start_stack

    check_containers

    check_http_services

    check_prometheus_targets

    show_summary

    log "INFO" "Prometheus + Grafana installation completed successfully"
}

main "$@"
