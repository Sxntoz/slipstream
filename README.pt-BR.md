<p align="center"><img src="assets/logo.png" alt="Slipstream" width="128"></p>

<h1 align="center">Slipstream</h1>

<p align="center"><b>Português (Brasil)</b> · <a href="README.md">English</a></p>

<p align="center">Patcher de conexão por app para Windows.<br>
Dá a um app a própria rota (WireGuard, proxy), um IP novo quando você quiser e limpezas seguras,<br>
enquanto o resto do PC fica exatamente como está.</p>

**Apps suportados:** OpenCode desktop. Outros apps estão planejados; o motor de conexão não depende de nenhum app específico.

> Não oficial. Sem vínculo com os apps que ele suporta. Ele troca o IP de saída de um app; seguir os termos dos serviços que
> você usa é responsabilidade sua.

## Instalação

Abra o **PowerShell** e rode:

```ps1
iex "& { $(iwr -useb 'https://raw.githubusercontent.com/Sxntoz/slipstream/main/install.ps1') } -start"
```

Espelho (se o raw do GitHub estiver bloqueado):

```ps1
iex "& { $(iwr -useb 'https://raw.githubusercontent.com/Sxntoz/slipstream/main/install.ps1') } -m -start"
```

OpenCode ainda não instalado? Adicione `-download` e o original é baixado primeiro das releases oficiais do GitHub.

## O que o instalador faz

Ele conversa com você como o SpotX. Rode e ele vê o que está instalado, depois pergunta (responda `S`/`sim` ou `N`):

1. OpenCode não encontrado: baixar e instalar o oficial?
2. Existe uma versão mais nova do OpenCode: atualizar?
3. Bloquear as atualizações do próprio OpenCode (uma atualização removeria o patch)?
4. Instalar o Slipstream para o terminal também?

Depois: `Baixando o OpenCode 2.3.2` (com barra de progresso), `Instalando o OpenCode`, `Aplicando o patch no OpenCode...`,
`Instalação do Slipstream concluída.` As perguntas saem no idioma do Windows. `-yes` responde Sim a todas, e sem console ele usa
os padrões seguros.

### Atualizar sem perder nada

Antes de uma atualização ele salva, e depois confere, tudo o que é seu e fica fora do app:

- seus chats (`opencode.db`) e seu login (`auth.json`)
- as configurações e os rascunhos do OpenCode
- as configurações do Slipstream, a conta WARP e o arquivo WireGuard

Cada arquivo é copiado para `%LOCALAPPDATA%\slipstream\backup\update-<data>` (os 3 mais novos ficam) e comparado byte a byte
depois. Se algum arquivo estiver diferente ou faltando, ele é devolvido do backup e o instalador avisa.

## Desinstalar

```ps1
iex "& { $(iwr -useb 'https://raw.githubusercontent.com/Sxntoz/slipstream/main/install.ps1') } -uninstall"
```

Isso devolve o `app.asar` original. Nada mais do OpenCode é alterado.

## Requisitos

- Windows 10 / 11, PowerShell 5.1 ou acima (também funciona no PowerShell 7)
- OpenCode desktop (o instalador oficial)
- Sem admin, sem driver, sem programa extra

## O que você recebe

Um ícone na bandeja, ao lado do relógio:

| Item | O que faz |
|---|---|
| **Novo IP** | Pega um IP novo para a conexão atual |
| **Conexão ▸ Direta** | O OpenCode usa a sua conexão normal |
| **Conexão ▸ WARP embutido** | Cliente WireGuard próprio (escrito em JS, sem `.exe`) com uma conta WARP grátis da Cloudflare. **IPv6 primeiro**, IPv4 como alternativa |
| **Conexão ▸ Arquivo WireGuard** | Qualquer `.conf` do WireGuard (Route64, Proton, Mullvad, seu servidor). Escolha em *Escolher arquivo WireGuard...* |
| **Conexão ▸ Proxies públicos grátis** | Testa listas de proxies públicos e usa o primeiro que funciona (não confiáveis, veja abaixo) |
| **Conexão ▸ Minha lista de proxies** | Seus proxies `http://` e `socks5://`, editados em *Editar configurações* |
| **Rotação automática** | Quando um chat para no limite grátis: IP novo, depois a mensagem é enviada de novo |
| **Limpar ▸ Login** | Faz backup do `auth.json` e o remove. Os chats ficam |
| **Limpar ▸ Restaurar login** | Devolve o último backup |
| **Limpar ▸ Cache e logs** | Libera espaço em disco. Os chats ficam |
| **Status** | O IP que o OpenCode está usando |
| **Idioma** | Idioma do menu (automático por padrão) |
| **Reiniciar / Sair** | Reinicia, ou fecha tudo (túnel e serviço em segundo plano incluídos) |

Ele também remove a bandeja persistente "Limite grátis atingido / Assinar o Go" que substitui a caixa de mensagem.

## Versão de terminal

O mesmo motor para o OpenCode de **terminal** (v2 `@opencode/cli`, e o v1 mais antigo `opencode-ai`). Precisa de Node.js 20+.

```ps1
iex "& { $(iwr -useb 'https://raw.githubusercontent.com/Sxntoz/slipstream/main/install.ps1') } -terminal"
```

Adicione `-update` para atualizar também o OpenCode de terminal para a versão mais nova (v2 como `opencode` / `opencode2`,
v1 à parte como `opencode1`):

```ps1
iex "& { $(iwr -useb 'https://raw.githubusercontent.com/Sxntoz/slipstream/main/install.ps1') } -terminal -update"
```

Depois, em qualquer terminal:

```
slipstream opencode            # o app OpenCode desktop
slipstream cli                 # OpenCode v2 neste terminal (igual a: slipstream opencode cli, ou opencode2)
slipstream cli run "..."       # não interativo: um erro de limite grátis troca o IP e roda de novo
slipstream ip                  # IP novo. Use em um SEGUNDO terminal enquanto uma sessão está rodando
slipstream status              # o IP em uso
slipstream mode wg             # direct | wg | wgfile | free | list
slipstream wgfile my.conf      # usa um arquivo WireGuard
slipstream proxy add socks5://host:1080
slipstream context opencode/deepseek-v4.1-flash-free 1000000
slipstream clear login|restore|cache
slipstream lang pt-BR
slipstream run <qualquer programa>   # qualquer programa pela mesma rota
```

Observações:
- `slipstream opencode` abre o app desktop (patcheado pelo instalador). O terminal é `slipstream cli`, `slipstream opencode cli`
  ou `slipstream opencode2`; o v1 mais antigo é `slipstream opencode1`.
- O terminal tem as próprias configurações (`cli.json`), a própria conta WARP e a própria porta de proxy, então pode rodar ao
  lado do app desktop.
- Na tela interativa não existe jeito seguro de vigiar o limite grátis. Quando ele parar você, rode `slipstream ip` em outro
  terminal e mande a mensagem de novo.
- v1 e v2 não podem compartilhar o mesmo banco, então `slipstream opencode1` guarda os dados em `%LOCALAPPDATA%\opencode-v1\xdg`
  (com o próprio login também).
- Remova com `-terminal -uninstall`.

## Atualizar o OpenCode desktop

`-update` remove o patch, instala o OpenCode oficial mais novo e aplica o patch de novo (o atualizador do próprio OpenCode fica
bloqueado porque ele tiraria o patch):

```ps1
iex "& { $(iwr -useb 'https://raw.githubusercontent.com/Sxntoz/slipstream/main/install.ps1') } -update -start"
```

## Idiomas

O menu da bandeja, as mensagens dele e o instalador seguem o idioma do Windows automaticamente. 12 idiomas:

English, Português (Brasil), Español, Français, Deutsch, Русский, 简体中文, 日本語, 한국어, हिन्दी, العربية, Bahasa Indonesia.

Mude o idioma do menu quando quiser na bandeja: **Idioma**. Para o instalador use `-lang pt-BR` (ou `es`, `fr`, `de`, `ru`,
`zh-CN`, `ja`, `ko`, `hi`, `ar`, `id`). Detalhes técnicos (erros de rede, o arquivo de log) ficam em inglês.

## Como funciona

- O instalador adiciona um arquivo de entrada ao `resources\app.asar` e aponta o `main` do `package.json` para ele. O original
  intacto fica como `app.asar.slipstream.bak`. Ele também impede o app de salvar o horário do limite grátis que mantém aquela
  bandeja na tela.
- Essa entrada sobe um proxy pequeno em `127.0.0.1` e aponta só o OpenCode (e o serviço em segundo plano dele) para ele. Trocar a
  conexão é imediato, sem reiniciar.
- O WARP embutido é um cliente WireGuard em modo usuário: handshake Noise, ChaCha20-Poly1305, X25519, BLAKE2s, mais uma pequena
  pilha IPv4/IPv6/TCP/UDP e DNS pelo túnel. A conta grátis é registrada pela API da Cloudflare, como o `wgcf` faz.
- O atualizador do próprio OpenCode é apontado para nada (uma atualização trocaria o patch). Desfaça com `-block_update_off`.

Os arquivos da ferramenta ficam em `%LOCALAPPDATA%\slipstream` (`proxy.json` = configurações e lista de proxies, `slipstream.log`,
`backup\`, `wg\`).

## Parâmetros

| Parâmetro | |
|---|---|
| `-start` | Abre o OpenCode quando terminar |
| `-uninstall` | Remove o patch |
| `-status` | Mostra o que está instalado |
| `-download` | Instala o OpenCode original primeiro se ele estiver faltando |
| `-yes` / `-y` | Responde Sim a todas as perguntas |
| `-update` | Atualiza o OpenCode para a versão mais nova e aplica o patch de novo (chats, login e configurações são salvos e conferidos) |
| `-terminal` | A versão de terminal (adicione `-update` para atualizar o OpenCode de terminal também, `-uninstall` para remover) |
| `-version 2.3.0` | Versão para baixar com `-download` |
| `-block_update_off` | Deixa o OpenCode se atualizar de novo (atualizações removem o patch) |
| `-path <pasta>` | Pasta do OpenCode, se não estiver no lugar padrão |
| `-lang pt-BR` | Idioma do instalador (padrão: o do Windows) |
| `-m` | (instalador) usa o espelho |

## Observações e limites

- **Proxies públicos grátis não são confiáveis.** O HTTPS continua criptografado de ponta a ponta, mas o operador do proxy vê a
  quais hosts você se conecta. Eles também são lentos e duram pouco. Prefira o WARP embutido ou o seu próprio arquivo WireGuard.
- Uma conta WARP não tem IP fixo: a Cloudflare entrega a saída do servidor mais próximo, então *Novo IP* pode devolver o mesmo bloco.
- WireGuard precisa de UDP até o servidor (WARP: porta 2408). Se a sua rede bloquear, o túnel não sobe e o app volta para Direta.
- Uma atualização do OpenCode troca o patch. Rode o instalador de novo depois de atualizar.
- Testado no OpenCode 2.3.2 (desktop e terminal) e 1.19.6 (terminal).

## Desenvolvimento

O `run.ps1` é gerado a partir dos módulos em `src/`; não edite ele na mão. Veja [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

```
src/installer/   PowerShell, em ordem        src/runtime/core/  o motor (WireGuard próprio, proxy, ações)
src/runtime/boot o patch do desktop          src/runtime/cli/   a versão de terminal
src/i18n/        um arquivo por idioma       build/build.mjs    junta tudo em run.ps1
tests/           npm test                    assets/            logo, ícone da bandeja (desktop), ícone da bandeja (CLI)
```

```ps1
npm run build    # gera o run.ps1 de novo
npm run check    # falha se o run.ps1 estiver desatualizado (o CI faz isso)
npm test         # vetores de cripto, pacotes, idiomas, build, lógica do instalador
```

## Licença

MIT
