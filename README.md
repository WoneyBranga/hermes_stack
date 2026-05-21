# Stack Hermes Multi-Instância

Uma plataforma para executar várias instâncias independentes do [hermes-agent](https://github.com/NousResearch/hermes-agent), cada uma com seu próprio frontend [hermes-webui](https://github.com/nesquena/hermes-webui). Todos os agentes trafegam por meio de um proxy compartilhado do [LiteLLM](https://github.com/BerriAI/litellm), oferecendo controle centralizado de LLM para todas as sessões.

## Arquitetura

```
Navegador → http://localhost:8787  ──► hermes-webui-1 ──┐
Navegador → http://localhost:8788  ──► hermes-webui-2 ──┤  hermes-net compartilhada
Navegador → http://localhost:878N  ──► hermes-webui-N ──┤
                                                            ▼
                                      hermes-agent-1/2/N ──► proxy LiteLLM
                                                               (seu endpoint)

Cada instância compartilha um hermes-home montado por bind:
  instances/instance-N/hermes-home/   ← sessões, skills, memórias, config
  instances/instance-N/workspace/     ← arquivos do workspace do agente
```

Cada par webui+agent compartilha um diretório `hermes-home` isolado no host, então os dados não vazam entre instâncias. A única exceção é o diretório `shared-skills/`: skills colocadas nele ficam visíveis em modo somente leitura para todos os webuis.

## Pré-requisitos

- Docker + Docker Compose v2
- Python 3 (para o template do bootstrap — não requer instalação além do Python do sistema)
- bash 3.2+ (o padrão do macOS é suficiente)

## Início rápido

```bash
# 1. Configure o ambiente
cp .env.example .env
$EDITOR .env          # defina LITELLM_BASE_URL, senhas, HOST_UID/GID

# 2. Gere as configs por instância
./scripts/bootstrap.sh

# 3. Suba a stack
docker compose up -d

# 4. Abra no navegador
open http://localhost:8787   # instância 1
open http://localhost:8788   # instância 2
```

## Mapeamento de portas

| Instância | URL do WebUI                      | Gateway do agente (somente loopback) |
|-----------|-----------------------------------|--------------------------------------|
| 1         | http://\<server-ip\>:8787         | localhost:8642                       |
| 2         | http://\<server-ip\>:8788         | localhost:8643                       |
| N         | http://\<server-ip\>:8786+N       | localhost:8641+N                     |

As portas do WebUI ficam expostas em todas as interfaces (`0.0.0.0`) e podem ser acessadas pela rede. As portas do gateway do agente ficam limitadas a `127.0.0.1` (somente loopback) — o acesso externo à API do agente não é necessário, pois o webui trata disso internamente. A proteção por senha é aplicada em todos os webuis.

## Dados das instâncias

Cada instância armazena seus dados em um diretório montado por bind que pode ser acessado diretamente:

```
instances/
  instance-1/
    hermes-home/          # dados do agente (sessões, skills, memórias, config.yaml, .env)
    workspace/            # workspace de arquivos visível dentro do agente
  instance-2/
    ...
```

Os arquivos pertencem a `HOST_UID:HOST_GID` (definidos em `.env`). Você pode ler, copiar ou editar qualquer arquivo diretamente — as mudanças são refletidas pelo agente em execução.

## Referência de scripts

| Script | Uso | Descrição |
|--------|-----|-----------|
| `bootstrap.sh` | `./scripts/bootstrap.sh` | Cria `.env` a partir do exemplo e renderiza `config.yaml` para todas as instâncias |
| `add-instance.sh` | `./scripts/add-instance.sh <N> <litellm-api-key>` | Adiciona uma nova instância (idempotente e com senha do WebUI gerada automaticamente) |
| `remove-instance.sh` | `./scripts/remove-instance.sh <N> [--purge] [--yes]` | Remove uma instância; `--purge` apaga os dados |
| `share-skill.sh` | `./scripts/share-skill.sh <skill> [from] [to\|all]` | Copia uma skill entre instâncias |
| `status.sh` | `./scripts/status.sh` | Exibe uma tabela de status de todas as instâncias |
| `backup-instance.sh` | `./scripts/backup-instance.sh <N>` | Cria um backup tarball de uma instância |

Consulte [docs/SCALING.md](docs/SCALING.md) para instruções de escala e [docs/SKILL_SHARING.md](docs/SKILL_SHARING.md) para gerenciamento de skills.

## Configuração

Toda a configuração fica em `.env`. Consulte [docs/ENV_REFERENCE.md](docs/ENV_REFERENCE.md) para a referência completa das variáveis.

As variáveis mais importantes para definir antes da primeira execução são:

```env
LITELLM_BASE_URL=http://host.docker.internal:4000/v1
LITELLM_API_KEY=sk-your-key
HERMES_DEFAULT_MODEL=gpt-4o-mini
HOST_UID=501    # execute: id -u
HOST_GID=20     # execute: id -g
HERMES_WEBUI_PASSWORD_1=your-secure-password
HERMES_WEBUI_PASSWORD_2=another-secure-password
```

## Privilégios do Agent e do WebUI

Tanto `hermes-agent` quanto `hermes-webui` são construídos localmente a partir dos Dockerfiles em `docker/`, cada um estendendo a imagem upstream com `sudo` sem senha:

- `docker/hermes-agent/Dockerfile` — adiciona sudo para o usuário `hermes`
- `docker/hermes-webui/Dockerfile` — adiciona sudo para o usuário `hermeswebui`

A ferramenta shell do Hermes é executada dentro do contêiner do **webui** (e não do agent), então o `sudo` no webui é o que permite ao LLM instalar pacotes sob demanda:

```bash
sudo apt-get update && sudo apt-get install -y <package>
```

Ambos os contêineres ainda reduzem privilégios para `HOST_UID:HOST_GID` em tempo de execução, então os arquivos gravados em `hermes-home/` e `workspace/` mantêm a propriedade correta no host. `docker compose up -d` constrói as duas imagens automaticamente na primeira execução; para reconstruir manualmente:

```bash
docker compose build
```

**Atrás de proxy corporativo:** o Dockerfile aceita argumentos de build `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY`, preenchidos a partir de `proxy.env`. Execute o build (ou `up`) com ambos os arquivos de ambiente para que o compose faça a substituição:

```bash
docker compose --env-file proxy.env --env-file .env build
docker compose --env-file proxy.env --env-file .env up -d
```

Os valores do proxy ficam limitados apenas à etapa de `apt-get` — eles não são incorporados à imagem final. O proxy em runtime é injetado separadamente via `env_file: proxy.env`, já configurado em cada serviço.

## Integração com LiteLLM

Cada instância do hermes-agent se conecta exclusivamente ao seu proxy LiteLLM. O proxy é configurado uma vez no `.env` por meio de `LITELLM_BASE_URL` e `LITELLM_API_KEY`, e depois injetado no `config.yaml` de cada instância durante o bootstrap.

O LiteLLM precisa estar acessível de dentro da rede Docker:
- **Mesmo host (macOS/Linux):** `http://host.docker.internal:4000/v1`
- **Serviço Docker irmão:** `http://litellm:4000/v1` (conecte o litellm à `hermes-net`)
- **Externo/cloud:** `https://litellm.example.com/v1`
