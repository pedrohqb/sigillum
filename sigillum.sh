#!/bin/bash
# Sigillum: Lacuna Web PKI e Softplan WebSigner (e-SAJ) nos navegadores em
# Flatpak, usando os tokens do Tessera (https://github.com/pedrohqb/tessera).
# Sai por inteiro com "remover". Detalhes em docs/funcionamento.md.
#
#   ./sigillum.sh instalar [webpki|websigner]   (sem nome: os dois)
#   ./sigillum.sh remover  [webpki|websigner]   (sem nome: tudo)
#   ./sigillum.sh estado
#
# Como funciona: cada navegador roda o programa do fornecedor dentro do
# próprio sandbox (native messaging). Um script de partida põe à frente na
# busca de bibliotecas um link chamado libaetpkss.so.3, o nome que a opção
# "Dispositivos SafeSign AET" das extensões procura, apontando para o
# p11-kit-client.so do runtime. Ele chega aos tokens do Tessera pelo servidor
# p11-kit do sistema; por isso o passo 1 do Tessera precisa estar feito.
#
# Os pacotes são os mesmos do distrobox-adv-br, com o mesmo SHA256.
set -eu

BASE=~/.local/share/sigillum
OVR=~/.local/share/flatpak/overrides
CLIENTE=/usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-client.so

# componente | URL | SHA256 | caminho no .deb | nome nativo | pasta de dados | IDs Chrome/Edge | IDs Firefox
COMPONENTES="
webpki|https://get.webpkiplugin.com/Downloads/2.16.1/setup-deb-64|a4ef76b1f0f5ff4489211b459d147ef0e2dea2ecad97d8f9ba2b0b283d3e3d85|./opt/lacuna-webpki/webpki|com.lacunasoftware.webpki|.lacuna-webpki|dcngeagmmhegagicpcmpinaoklddcgon nedeegdmhlnmboboahchfpkmdnnemapd|webpki@lacunasoftware.com webpki-beta@lacunasoftware.com
websigner|https://websigner.softplan.com.br/Downloads/2.15.0/webpki-chrome-64-deb|04fa41e962d91e4d7337f4707479437bf660f19057fac63829fb46784ee08289|./opt/softplan-websigner/websigner|br.com.softplan.webpki|.softplan-websigner|bbafmabaelnnkondpfpjmdklbmfnbmol|websigner@softplan.com.br websigner@softplan_com_br
"

# Os navegadores que o Tessera configura: id | pasta dos manifestos em ~/.var/app/<id> | tipo
NAVEGADORES="
org.mozilla.firefox|.mozilla/native-messaging-hosts|firefox
org.mozilla.firefox|config/mozilla/native-messaging-hosts|firefox
org.chromium.Chromium|config/chromium/NativeMessagingHosts|chrome
com.google.Chrome|config/google-chrome/NativeMessagingHosts|chrome
com.microsoft.Edge|config/microsoft-edge/NativeMessagingHosts|chrome
com.brave.Browser|config/BraveSoftware/Brave-Browser/NativeMessagingHosts|chrome
"

instalado() { flatpak info --user "$1" >/dev/null 2>&1 || flatpak info --system "$1" >/dev/null 2>&1; }

campo() { # componente número
    echo "$COMPONENTES" | awk -F'|' -v c="$1" -v n="$2" '$1 == c { print $n }'
}

lista_json() { # palavras -> "a", "b"
    local out="" x
    for x in "$@"; do out="$out${out:+, }\"$x\""; done
    echo "$out"
}

manifesto() { # componente tipo
    local nome origem ids x
    nome=$(campo "$1" 5)
    if [ "$2" = chrome ]; then
        ids=""
        for x in $(campo "$1" 7); do ids="$ids chrome-extension://$x/"; done
        origem="\"allowed_origins\": [ $(lista_json $ids) ]"
    else
        origem="\"allowed_extensions\": [ $(lista_json $(campo "$1" 8)) ]"
    fi
    cat <<EOF
{
  "name": "$nome",
  "description": "PKI Connector",
  "path": "$BASE/$1/iniciar.sh",
  "type": "stdio",
  $origem
}
EOF
}

# Os nomes e IDs que o override recebe, para tirar depois só o que se pôs.
override_add() { # id opções...
    local id=$1; shift
    flatpak override --user "$@" "$id"
}

instalar_um() { # componente
    local c=$1 url sha dentro tmp
    url=$(campo "$c" 2); sha=$(campo "$c" 3); dentro=$(campo "$c" 4)
    [ -n "$url" ] || { echo "Componente desconhecido: $c"; exit 2; }
    mkdir -p "$BASE/$c" "$BASE/lib"
    tmp=$(mktemp -d)
    echo "Baixando $c..."
    # O servidor da Softplan já teve problemas de certificado (o
    # distrobox-adv-br usa --no-check-certificate); vale o SHA256.
    curl -fsSL -k -o "$tmp/pacote.deb" "$url"
    echo "$sha  $tmp/pacote.deb" | sha256sum -c --status \
        || { rm -rf "$tmp"; echo "O SHA256 de $c não confere; nada foi instalado."; exit 1; }
    bsdtar -xOf "$tmp/pacote.deb" 'data.tar.*' | bsdtar -xf - -C "$BASE/$c" --strip-components 3 "$dentro"
    rm -rf "$tmp"
    mv "$BASE/$c/$(basename "$dentro")" "$BASE/$c/programa"
    cat > "$BASE/$c/iniciar.sh" <<'EOF'
#!/bin/sh
D=$(dirname "$(readlink -f "$0")")
export LD_LIBRARY_PATH="$D/../lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$D/programa" "$@"
EOF
    chmod +x "$BASE/$c/iniciar.sh" "$BASE/$c/programa"
    ln -sfn "$CLIENTE" "$BASE/lib/libaetpkss.so.3"

    # Numa reinstalação, guarda só a anotação do X11 (quem o pôs continua dono dele).
    grep -s '^x11 ' "$BASE/$c/.estado" > "$BASE/$c/.estado.novo" || true
    mv "$BASE/$c/.estado.novo" "$BASE/$c/.estado"
    echo "$NAVEGADORES" | while IFS='|' read -r id pasta tipo; do
        [ -n "$id" ] && instalado "$id" || continue
        mkdir -p ~/.var/app/"$id"/"$pasta"
        manifesto "$c" "$tipo" > ~/.var/app/"$id"/"$pasta"/"$(campo "$c" 5)".json
        echo "manifesto $id $pasta" >> "$BASE/$c/.estado"
        grep -q "^override $id$" "$BASE/$c/.estado" && continue
        override_add "$id" --filesystem='~/.local/share/sigillum:ro' --persist="$(campo "$c" 6)"
        echo "override $id" >> "$BASE/$c/.estado"
        # As janelas dos dois programas só desenham por X11, e o Firefox só tem fallback-x11.
        # Se foi o outro componente que o pôs, este também o anota, para ele
        # só sair quando nenhum dos dois precisar.
        if [ "$tipo" = firefox ]; then
            outro=webpki; [ "$c" = webpki ] && outro=websigner
            if ! grep -qE '^sockets=(.*;)?x11;' "$OVR/$id" 2>/dev/null; then
                override_add "$id" --socket=x11
                echo "x11 $id" >> "$BASE/$c/.estado"
            elif grep -qs "^x11 $id$" "$BASE/$outro/.estado" && ! grep -q "^x11 $id$" "$BASE/$c/.estado"; then
                echo "x11 $id" >> "$BASE/$c/.estado"
            fi
        fi
        echo "  $c: $id"
    done
}

tirar_do_override() { # arquivo chave valor
    [ -f "$1" ] || return 0
    sed -i -E -e "s#^($2=(.*;)?)$3;#\\1#" -e "/^$2=\$/d" "$1"
}

remover_um() { # componente
    local c=$1 e="$BASE/$1/.estado" outro
    [ -f "$e" ] || return 0
    outro=webpki; [ "$c" = webpki ] && outro=websigner
    while read -r o id pasta; do
        case "$o" in
            manifesto) rm -f ~/.var/app/"$id"/"$pasta"/"$(campo "$c" 5)".json ;;
            override)
                tirar_do_override "$OVR/$id" persistent "$(campo "$c" 6 | sed 's/\./\\./g')"
                rm -rf ~/.var/app/"$id"/"$(campo "$c" 6)"
                # A pasta comum só sai do override se o outro componente não a usa.
                if ! grep -qs "^override $id$" "$BASE/$outro/.estado"; then
                    tirar_do_override "$OVR/$id" filesystems '[^;]*/\.local/share/sigillum:ro'
                fi
                echo "  $c: $id" ;;
            x11)
                grep -qs "^x11 $id$" "$BASE/$outro/.estado" || tirar_do_override "$OVR/$id" sockets x11 ;;
        esac
    done < "$e"
    rm -rf "${BASE:?}/$c"
}

estado() {
    local c
    for c in webpki websigner; do
        if [ -f "$BASE/$c/.estado" ]; then
            echo "$c: instalado em $(awk '$1 == "override" { printf "%s ", $2 }' "$BASE/$c/.estado")"
        else
            echo "$c: não instalado"
        fi
    done
}

for p in curl bsdtar sha256sum flatpak; do
    command -v $p >/dev/null || { echo "Falta o programa $p."; exit 1; }
done

ACAO=${1:-}; QUAIS=${2:-webpki websigner}
case "$ACAO" in
    instalar)
        for c in $QUAIS; do instalar_um "$c"; done
        echo
        echo "Pronto. Em cada navegador: reinicie-o, instale a extensão (Web PKI e/ou"
        echo "WebSigner) se ainda não tiver, abra-a, aba \"Cripto Dispositivos\", e marque"
        echo "\"Dispositivos SafeSign AET\" uma vez. Ela passa a mostrar todos os tokens"
        echo "do Tessera, inclusive o SerproID." ;;
    remover)
        for c in $QUAIS; do remover_um "$c"; done
        [ -d "$BASE/webpki" ] || [ -d "$BASE/websigner" ] || rm -rf "$BASE"
        echo "Pronto. As extensões podem ser removidas de cada navegador à mão." ;;
    estado) estado ;;
    *) sed -n '2,9p' "$0"; exit 2 ;;
esac
