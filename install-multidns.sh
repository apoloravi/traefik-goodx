#!/bin/bash

# =============================================
# CONFIGURAÇÕES PERSONALIZADAS - ALTERE AQUI!
# =============================================
DOMINIO="multi.prov.top"          # Seu domínio principal
EMAIL="admin@multi.prov.top"      # E-mail para certificados SSL
USUARIO="apolo"                   # Usuário do dashboard
SENHA="yagusto0065"               # Senha do dashboard
FUSO_HORARIO="America/Sao_Paulo"  # Ajuste o fuso horário se necessário

# =============================================
# INSTALAÇÃO AUTOMÁTICA - NÃO ALTERE ABAIXO!
# =============================================

# Funções para output colorido
vermelho() { echo -e "\033[31m$1\033[0m"; }
verde() { echo -e "\033[32m$1\033[0m"; }
amarelo() { echo -e "\033[33m$1\033[0m"; }
azul() { echo -e "\033[34m$1\033[0m"; }

# Verificar e instalar dependências
instalar_dependencias() {
    azul "\n🔍 Verificando dependências..."
    
    # Docker
    if ! command -v docker &> /dev/null; then
        amarelo "🛠 Instalando Docker..."
        curl -fsSL https://get.docker.com | sh
        sudo usermod -aG docker $USER
    else
        verde "✓ Docker já está instalado"
    fi

    # Docker Compose
    if ! command -v docker compose &> /dev/null; then
        amarelo "🛠 Instalando Docker Compose..."
        sudo apt-get install -y docker-compose-plugin || {
            sudo curl -L "https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
        }
    else
        verde "✓ Docker Compose já está instalado"
    fi

    # htpasswd
    if ! command -v htpasswd &> /dev/null; then
        amarelo "🛠 Instalando htpasswd..."
        sudo apt-get install -y apache2-utils
    fi
}

# Configurar estrutura de diretórios
configurar_diretorios() {
    azul "\n📂 Criando estrutura de diretórios..."
    mkdir -p ~/docker/{traefik,portainer/data}
    cd ~/docker
    touch traefik/acme.json
    chmod 600 traefik/acme.json
}

# Criar arquivos de configuração
criar_configs() {
    azul "\n⚙️ Criando arquivos de configuração..."

    # Gerar hash da senha
    HASH=$(htpasswd -nbB $USUARIO "$SENHA" | sed -e 's/\$/\$\$/g')

    # traefik.toml
    cat > traefik/traefik.toml <<EOF
[global]
  checkNewVersion = true
  sendAnonymousUsage = false

[entryPoints]
  [entryPoints.web]
    address = ":80"
    [entryPoints.web.http.redirections.entryPoint]
      to = "websecure"
      scheme = "https"

  [entryPoints.websecure]
    address = ":443"

[api]
  dashboard = true
  insecure = false

[providers]
  [providers.docker]
    exposedByDefault = false
    network = "web"

[certificatesResolvers.letsencrypt.acme]
  email = "$EMAIL"
  storage = "/acme.json"
  [certificatesResolvers.letsencrypt.acme.httpChallenge]
    entryPoint = "web"

[http.middlewares]
  [http.middlewares.auth.basicAuth]
    users = ["$HASH"]
EOF

    # docker-compose.yml
    cat > docker-compose.yml <<EOF
version: '3.8'

services:
  traefik:
    image: traefik:v2.10
    container_name: traefik
    restart: unless-stopped
    networks:
      - web
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"  # Dashboard
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik/traefik.toml:/etc/traefik/traefik.toml
      - ./traefik/acme.json:/acme.json
    environment:
      - TZ=$FUSO_HORARIO
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(\`traefik.$DOMINIO\`) && PathPrefix(\`/api\`, \`/dashboard\`)"
      - "traefik.http.routers.dashboard.service=api@internal"
      - "traefik.http.routers.dashboard.entrypoints=websecure"
      - "traefik.http.routers.dashboard.tls=true"
      - "traefik.http.routers.dashboard.tls.certresolver=letsencrypt"
      - "traefik.http.routers.dashboard.middlewares=auth@file"

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    networks:
      - web
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./portainer/data:/data
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.portainer.rule=Host(\`portainer.$DOMINIO\`)"
      - "traefik.http.routers.portainer.entrypoints=websecure"
      - "traefik.http.routers.portainer.tls=true"
      - "traefik.http.routers.portainer.tls.certresolver=letsencrypt"
      - "traefik.http.services.portainer.loadbalancer.server.port=9443"

networks:
  web:
    external: true
EOF
}

# Iniciar serviços
iniciar_servicos() {
    azul "\n🚀 Iniciando containers..."
    docker network create web >/dev/null 2>&1 || true
    docker compose up -d
}

# Mostrar resumo
mostrar_resumo() {
    verde "\n✅ INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
    
    echo -e "\n🔑 \033[1mDADOS DE ACESSO:\033[0m"
    echo -e "  Traefik Dashboard: \033[32mhttps://traefik.$DOMINIO\033[0m"
    echo -e "    Usuário: \033[33m$USUARIO\033[0m"
    echo -e "    Senha: \033[33m$SENHA\033[0m"
    
    echo -e "\n  Portainer: \033[32mhttps://portainer.$DOMINIO\033[0m"
    echo -e "    (Crie a senha no primeiro acesso)"
    
    echo -e "\n🛠 \033[1mCOMANDOS ÚTEIS:\033[0m"
    echo -e "  Reiniciar serviços: \033[35mcd ~/docker && docker compose up -d\033[0m"
    echo -e "  Ver logs do Traefik: \033[35mdocker logs traefik\033[0m"
    echo -e "  Ver logs do Portainer: \033[35mdocker logs portainer\033[0m"
    
    vermelho "\n⚠️ IMPORTANTE:"
    echo -e "  1. Configure seu DNS para apontar:"
    echo -e "     - traefik.$DOMINIO e portainer.$DOMINIO para $(curl -s ifconfig.me)"
    echo -e "  2. Certifique-se que as portas 80 e 443 estão abertas no firewall"
}

# Execução principal
clear
echo -e "\033[34m========================================\033[0m"
echo -e "\033[34m  INSTALAÇÃO TRAEFIK + PORTAINER        \033[0m"
echo -e "\033[34m========================================\033[0m"

instalar_dependencias
configurar_diretorios
criar_configs
iniciar_servicos
mostrar_resumo
