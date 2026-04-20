# Diagnose Toolkit

Toolkit para coleta padronizada de informações de diagnóstico em sistemas Linux, com foco em ambientes HPC. Com o Diagnose Toolkit é possível coletar de forma consistente informações dinâmicas do sistema (via comandos), configurações e arquivos relevantes e evidências estruturadas para troubleshooting.

---

## Arquitetura

O toolkit é composto por três scripts:

`diagnose-toolkit.sh`: Wrapper - orquestrador principal

`collect-commands.sh`: Coletor via comandos

`collect-files.sh`: Coletor de arquivos de configuração e diretórios

### 1. `diagnose-toolkit.sh`

1. Define o perfil de coleta:

| Perfil   | Descrição                              |
| -------- | -------------------------------------- |
| basic    | Coleta mínima                          |
| full     | Coleta completa                        |
| cluster  | Foco em HPC (rede, storage, scheduler) |
| gpu      | Foco em nós com GPU                    |
| packages | Pacotes e repositórios                 |
| network  | Rede                                   |
| storage  | Storage                                |


2. Cria estrutura de saída
3. Executa os coletores
4. Consolida resultados
5. Gera arquivo compactado (opcional)

---

### 2. `collect-commands.sh`

1. Executa comandos do sistema
2. Organiza saídas por categoria:
    * `meta`
    * `hardware`
    * `network`
    * `storage`
    * `security`
    * `packages`
    * `cluster`
3. Registra status de execução

---

### 3. `collect-files.sh`

1. Copia arquivos e diretórios de configuração
2. Preserva estrutura original
3. Registra manifesto e status

---

## Requisitos

* Bash
* Permissão de root
* Utilitários padrão Linux (coreutils, iproute2, etc.)

Alguns comandos são opcionais e podem não existir em todos os hosts:

* `nvidia-smi`
* `ibstat`
* `pcs`
* `multipath`

Nestes casos, o toolkit registra como `SKIP`.

---

## Modos de utilização


### Ajuda

```bash
./diagnose-toolkit.sh --help
```

### Execução padrão (perfil completo)

```bash
./diagnose-toolkit.sh
```

---

### Execução com perfil específico

```bash
./diagnose-toolkit.sh cluster
```

---

### Sem gerar arquivo compactado

```bash
./diagnose-toolkit.sh full --no-archive
```

---

### Listar perfis disponíveis

```bash
./diagnose-toolkit.sh --list-profiles
```

---

## Arquivos de logs

### `command-status.log`

Registra a execução dos comandos:

```
timestamp | status | comando | arquivo_saida | rc
```

### `file-status.log`

Registra a coleta de arquivos:

```
timestamp | status | caminho | destino | detalhe
```

### `files-manifest.txt`

Lista todos os arquivos efetivamente coletados.

---

## Saída final

**Muita atenção!! Pois, a coleta pode incluir arquivos sensíveis**, como:

* `/etc/shadow` (será incluído)
* configuração de serviços
* chaves e credenciais indiretas

**É fortemente recomendado que o conteúdo seja revisado antes de compartilhar.**

---

## Para customizações adicionais

### Adicionar comandos

Para adicionar comandos basta editar o arquivo `collect-commands.sh`, seguindo o seguinte padrão:

```bash
"categoria|nome|comando"
```

---

### Adicionar arquivos

Para adicionar arquivos basta editar o arquivo `collect-files.sh`, seguindo o seguinte padrão:

```bash
paths=(
    "/etc/exemplo"
)
```

---

### Criar novo perfil

Novos perfis também podem ser criados. Basta adicionar novas funções como abaixo:

```bash
load_meu_perfil()
```

e incluir no `case`.
