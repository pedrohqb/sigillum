# Como o Sigillum funciona

## O problema

O Lacuna Web PKI e o Softplan WebSigner têm duas partes:

- uma **extensão** do navegador, que conversa com o site do tribunal;
- um **programa nativo**, que a extensão abre por *native messaging*: o navegador executa o programa e conversa com ele pela entrada e saída padrão. É o programa que carrega o driver PKCS#11, mostra as janelas (escolha do certificado, PIN) e assina.

Os pacotes dos fornecedores instalam o programa em `/opt` e os manifestos de native messaging em `/etc/opt/chrome`, `/etc/chromium`, `/etc/opt/edge` e `/usr/lib/mozilla`. Um navegador em Flatpak não vê nenhuma dessas pastas. Além disso, só executa programas que estejam dentro do seu próprio sandbox.

## A solução

O navegador executa o programa dentro do próprio sandbox, e o programa chega aos tokens do Tessera pelo mesmo caminho que o navegador já usa.

```
site do tribunal ─► extensão ─► (native messaging) ─► iniciar.sh ─► programa do fornecedor
                                                         │ LD_LIBRARY_PATH=…/lib
                                                         ▼
                                    libaetpkss.so.3 ─► p11-kit-client.so do runtime
                                                         │ $XDG_RUNTIME_DIR/p11-kit/pkcs11
                                                         ▼
                                    servidor p11-kit do sistema ─► drivers do Tessera
```

1. **O programa** fica em `~/.local/share/sigillum/<componente>/programa`. O navegador recebe leitura dessa pasta pelo override `--filesystem=~/.local/share/sigillum:ro`.
2. **O manifesto** de native messaging vai para a pasta de usuário do navegador, dentro de `~/.var/app/<navegador>/`, com o nome e os IDs de extensão do pacote original. O `path` aponta para `iniciar.sh`.
3. **O `iniciar.sh`** põe `~/.local/share/sigillum/lib` à frente no `LD_LIBRARY_PATH` e executa o programa.
4. **Nessa pasta há um só arquivo,** o link `libaetpkss.so.3` → `/usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-client.so`. O caminho do destino é o do runtime do Flatpak, válido dentro do sandbox do navegador; no sistema, o link aparece quebrado, e isso é esperado.
5. **A extensão,** quando a opção "Dispositivos SafeSign AET" está marcada, manda o programa carregar a biblioteca `libaetpkss.so.3`, só pelo nome. O programa a procura pelo `LD_LIBRARY_PATH` e carrega o `p11-kit-client.so`. Esse cliente conecta no servidor p11-kit do sistema, que o passo 1 do Tessera deixa o navegador alcançar. Lá estão todos os drivers do Tessera.

### Por que só um link

A extensão do WebSigner 2.18.3 conhece dois nomes: `libeToken.so` ("Tokens SafeNet") e `libaetpkss.so.3` ("Dispositivos SafeSign AET"). Se os dois apontassem para o p11-kit, e as duas opções estivessem marcadas, cada token apareceria duas vezes. Um nome basta, porque o p11-kit entrega todos os tokens.

O Web PKI é o mesmo motor da Lacuna e usa o mesmo nome. Isso foi confirmado no teste.

## Os pacotes

| | Web PKI | WebSigner |
|---|---|---|
| Versão | 2.16.1 | 2.15.0 |
| Download | `https://get.webpkiplugin.com/Downloads/2.16.1/setup-deb-64` | `https://websigner.softplan.com.br/Downloads/2.15.0/webpki-chrome-64-deb` |
| SHA256 | `a4ef76b1f0f5ff4489211b459d147ef0e2dea2ecad97d8f9ba2b0b283d3e3d85` | `04fa41e962d91e4d7337f4707479437bf660f19057fac63829fb46784ee08289` |
| Programa no `.deb` | `/opt/lacuna-webpki/webpki` | `/opt/softplan-websigner/websigner` |
| Nome nativo | `com.lacunasoftware.webpki` | `br.com.softplan.webpki` |
| Extensão (Chrome, Chromium, Brave) | `dcngeagmmhegagicpcmpinaoklddcgon` | `bbafmabaelnnkondpfpjmdklbmfnbmol` |
| Extensão (Edge) | `nedeegdmhlnmboboahchfpkmdnnemapd` | `bbafmabaelnnkondpfpjmdklbmfnbmol` |
| Extensão (Firefox) | `webpki@lacunasoftware.com`, `webpki-beta@lacunasoftware.com` | `websigner@softplan.com.br`, `websigner@softplan_com_br` |
| Dados do usuário | `~/.lacuna-webpki` | `~/.softplan-websigner` |

As URLs e os SHA256 são os do distrobox-adv-br. O servidor da Softplan já teve problemas de certificado: o distrobox-adv-br baixa com `--no-check-certificate`, e o Sigillum com `curl -k`. Em ambos, a garantia é o SHA256.

Nos manifestos do Chrome, do Chromium, do Edge e do Brave, o Sigillum põe os dois IDs de extensão do Web PKI. Assim, no Edge, funciona tanto a extensão da loja da Microsoft quanto a da Chrome Web Store.

O que se viu nos dois pacotes:

- **Um binário só, de cerca de 140 MB:** um aplicativo .NET autocontido em arquivo único, com o .NET, o Avalonia, o SkiaSharp e o HarfBuzz embutidos. Não precisa de .NET instalado.
- **Bibliotecas exigidas:** só a glibc, a libstdc++ e a zlib. Na hora, carrega X11, GL, fontconfig, ICU, OpenSSL e GTK 3, todos presentes no runtime freedesktop dos navegadores.
- **Os scripts `postinst` e `postrm`** só copiam e apagam os manifestos e apagam a pasta de dados do usuário. O Sigillum não os executa.
- **Nenhum caminho fixo para arquivos de recurso,** ao contrário do Certisign WebSigner, que, segundo um relato, abre arquivos em `/opt/certisign-websigner/res`.

## O que o Sigillum grava

| Onde | O quê |
|---|---|
| `~/.local/share/sigillum/<componente>/programa` | o binário do fornecedor |
| `~/.local/share/sigillum/<componente>/iniciar.sh` | o script de partida |
| `~/.local/share/sigillum/<componente>/.estado` | o que foi feito em cada navegador, para o `remover` |
| `~/.local/share/sigillum/lib/libaetpkss.so.3` | o link para o `p11-kit-client.so` |
| `~/.var/app/<navegador>/<pasta de manifestos>/<nome nativo>.json` | o manifesto de native messaging |
| `~/.local/share/flatpak/overrides/<navegador>` | as permissões abaixo |

As permissões acrescentadas ao override de cada navegador:

- `--filesystem=~/.local/share/sigillum:ro`: ler o programa.
- `--persist=.lacuna-webpki` ou `--persist=.softplan-websigner`: os programas guardam os dados em `~/.<nome>`. O Chrome, o Edge e o Brave em Flatpak não veem a pasta pessoal, e sem isso esses dados se perderiam a cada execução. Com a permissão, ficam em `~/.var/app/<navegador>/.<nome>`.
- No Firefox, `--socket=x11`: as janelas dos programas (Avalonia) só desenham por X11, e o Firefox do Flathub tem só `fallback-x11`, que numa sessão Wayland não entrega o X11. Os outros navegadores já têm X11.

As pastas de manifestos:

| Navegador | Pasta, dentro de `~/.var/app/<id>/` |
|---|---|
| Firefox (`org.mozilla.firefox`) | `.mozilla/native-messaging-hosts` e `config/mozilla/native-messaging-hosts` |
| Chromium (`org.chromium.Chromium`) | `config/chromium/NativeMessagingHosts` |
| Google Chrome (`com.google.Chrome`) | `config/google-chrome/NativeMessagingHosts` |
| Microsoft Edge (`com.microsoft.Edge`) | `config/microsoft-edge/NativeMessagingHosts` |
| Brave (`com.brave.Browser`) | `config/BraveSoftware/Brave-Browser/NativeMessagingHosts` |

No Firefox, o manifesto vai para as duas pastas, porque o Firefox 147 em diante mudou o perfil para `config/mozilla`.

Um navegador só é configurado se `flatpak info` o encontrar instalado, para o usuário ou para o sistema.

## Remoção

O `remover` lê o `.estado` de cada componente e desfaz só o que ele registra:

- apaga os manifestos e a pasta `~/.var/app/<navegador>/.<nome>`;
- tira do override só as entradas que o Sigillum pôs;
- a leitura de `~/.local/share/sigillum` e o `x11` do Firefox são compartilhados pelos dois componentes, e só saem quando nenhum dos dois precisa mais deles.

A permissão do passo 1 do Tessera (`xdg-run/p11-kit/pkcs11`) nunca é tocada.

## Atualizar uma versão

1. Baixe o pacote novo e calcule o SHA256: `sha256sum pacote.deb`.
2. Confira o caminho do programa e os manifestos dentro do pacote:
   ```bash
   bsdtar -xOf pacote.deb 'data.tar.*' | bsdtar -tvf -
   bsdtar -xOf pacote.deb 'data.tar.*' | bsdtar -xOf - ./opt/<pasta>/manifest.json ./opt/<pasta>/manifest-edge.json
   ```
3. Atualize a linha do componente em `COMPONENTES`, no `sigillum.sh`: URL, SHA256, caminho, nome nativo, pasta de dados e IDs.
4. Para conferir se a extensão nova ainda procura o SafeSign como `libaetpkss.so.3`, procure o nome no código dela:
   ```bash
   grep -ohE '.{80}libaetpkss[^"]*.{40}' ~/.var/app/com.google.Chrome/config/google-chrome/Default/Extensions/<ID>/*/*.js
   ```

## Testes

Testado em 29 de outubro de 2026, num Bluefin, com o Tessera 0.1.0, um token GD Burti (SafeSign) e um certificado em nuvem SerproID: o Web PKI e o WebSigner funcionaram no Firefox, no Chromium, no Chrome, no Edge e no Brave.
