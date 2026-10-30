# Sigillum

O Sigillum instala o **Lacuna Web PKI** e o **Softplan WebSigner** nos navegadores em Flatpak e os liga aos tokens do [**Tessera**](https://github.com/pedrohqb/tessera). Esses dois componentes são exigidos por alguns tribunais para assinar documentos, como o e-SAJ.

Ele é um complemento provisório do Tessera: um script só, que instala e desinstala tudo, sem mexer no sistema nem no Tessera. Quando os tribunais deixarem de exigir esses componentes, basta removê-lo.

*Sigillum* era, em latim, o selo com que se lacravam e autenticavam os documentos.

Estão incluídos:

1. **Lacuna Web PKI**, usado para assinatura eletrônica de documentos em diversos sistemas;
2. **Softplan WebSigner**, usado para assinatura eletrônica de documentos nos sistemas SAJ, fornecidos pela Softplan.

O Certisign WebSigner, usado no portal de assinatura da OAB, ainda não está incluído.

Ambos funcionam nos navegadores que o Tessera configura: **Firefox, Chromium, Google Chrome, Microsoft Edge e Brave**. O script configura os que estiverem instalados.

---

## Antes de começar

1. O **Tessera** precisa estar instalado e funcionando: o token aparece na janela dele, e a linha "Conexão com o sistema" está em "Ativo". Veja a [instalação do Tessera](https://github.com/pedrohqb/tessera#instalação).
2. No Tessera, cada navegador deve estar com o **passo 1** feito, a permissão de acesso ao servidor p11-kit do sistema. Na lista de aplicativos do Tessera, o navegador aparece como **Pronto**.

---

## Instalação

Baixe o script e rode:

```bash
cd ~/Downloads && \
curl -fLO https://raw.githubusercontent.com/pedrohqb/sigillum/main/sigillum.sh && \
chmod +x sigillum.sh && ./sigillum.sh instalar
```

O script baixa o Web PKI e o WebSigner dos sites oficiais e confere cada um pelo SHA256, os mesmos do [distrobox-adv-br](https://github.com/pedrohqb/distrobox-adv-br). Se o arquivo baixado não conferir, nada é instalado.

Para instalar só um dos dois:

```bash
./sigillum.sh instalar webpki
./sigillum.sh instalar websigner
```

**OBS:** se você instalar outro navegador depois, rode `./sigillum.sh instalar` de novo. Os que já estavam configurados não são alterados.

---

## Configuração das extensões

Depois da instalação, em cada navegador:

1. Feche o navegador e abra de novo.
2. Instale a extensão de cada componente pelos sites oficiais: a) https://get.webpkiplugin.com/, para o Lacuna Web PKI; e b) https://websigner.softplan.com.br/, para o Softplan WebSigner.
3. Abra a extensão e acesse a aba **"Cripto Dispositivos"**.
4. Em "Dispositivos criptográficos (PKCS #11)", marque **"Dispositivos SafeSign AET"**.

Isso basta. Essa opção passa a mostrar **todos os tokens do Tessera**: SafeSign, SafeNet e o certificado em nuvem SerproID.

**OBS:** não marque "Tokens SafeNet" nem acrescente caminhos em "Opções personalizadas". Os tokens já aparecem pela opção do SafeSign, e outra opção os faria aparecer duas vezes.

---

## Conferir e desinstalar

Para ver em quais navegadores cada componente está instalado:

```bash
./sigillum.sh estado
```

Para desinstalar tudo:

```bash
./sigillum.sh remover
```

Ou só um dos dois:

```bash
./sigillum.sh remover webpki
./sigillum.sh remover websigner
```

O script desfaz só o que ele mesmo fez. As permissões que o Tessera pediu continuam como estavam. As extensões ficam nos navegadores e podem ser removidas à mão.

---

## Documentação

A parte técnica (como funciona, o que é gravado em cada navegador e como atualizar as versões) está em [docs/funcionamento.md](docs/funcionamento.md).

---

## Suporte

Havendo qualquer dificuldade, abra uma [issue](https://github.com/pedrohqb/sigillum/issues) ou peça ajuda no grupo oficial no [Telegram](https://t.me/advogados_linux).

---

## Licença

GPL-3.0-or-later. O Web PKI e o WebSigner não fazem parte do Sigillum: são baixados dos fornecedores e seguem as licenças deles.
