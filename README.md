# Guitar Tab Player

Toque junto com suas músicas favoritas: um player de tablaturas que canta cada nota, acorde, bend e slide de verdade, deixa você mutar/solar faixas, ajustar velocidade e afinação, e gravar seu próprio play-along.

## Para que serve

O Guitar Tab Player não é só um leitor de tablatura em texto — ele **executa** a tab. Cada música é um documento estruturado (compasso, andamento, afinação, capotraste) com uma ou mais faixas de instrumento (guitarra base, guitarra solo, violão, baixo, bateria), e o motor de playback sintetiza notas, acordes, bends, slides, hammer-ons/pull-offs, vibrato, palm mute, ghost notes, harmônicos e taps em sincronia com uma tablatura que rola sozinha na tela. A ideia é praticar: ouvir a parte certa, isolar um instrumento, desacelerar uma passagem difícil, transpor pro seu tom e tocar junto — inclusive gravando a sua performance.

## Funcionalidades

- **Busca e catálogo** — pesquise tabs em vários provedores/catálogos ao mesmo tempo (com filtros por afinação, instrumento e dificuldade), e navegue pelo catálogo local de demonstração.
- **Biblioteca pessoal** — favorite músicas, baixe tabs para tocar offline (quando a licença permite) e acompanhe quantas vezes já tocou cada uma.
- **Retomar de onde parou** — posição no compasso, velocidade, transposição e quais faixas estavam mudas são salvos automaticamente por música.
- **Mixer por faixa** — mute, solo, volume e pan independentes para cada instrumento da música (`TrackMixerView`).
- **Transporte completo** — play/pause, scrubber, presets de velocidade e mudança de tom, com contagem regressiva (count-in) opcional antes de tocar.
- **Metrônomo configurável** — subdivisão (semínima, colcheia, etc.) e volume ajustáveis, mais uma faixa de "backtrack" (base de acompanhamento) opcional.
- **Transposição inteligente** — transpõe acordes e notas na tablatura respeitando a afinação e o capotraste do instrumento, realocando automaticamente para a posição mais tocável no braço quando necessário.
- **Afinações suportadas** — Standard, Drop D, Eb Standard, D Standard, Drop C, Open G, Open D, Bass Standard e Bass Drop D.
- **Tablatura interativa** — acompanha o áudio com auto-scroll, mostra os diagramas de acorde acima da tab e permite tocar em qualquer ponto para pular direto pra lá.
- **Gravação** — grave a si mesmo tocando junto com a música.
- **Atalhos de teclado** — suporte a teclado físico no iPad.
- **Ajustes por padrão** — defina no app quais recursos (metrônomo, count-in, backtrack, auto-scroll, exibição de acordes, retomar posição, velocidade padrão) já vêm ligados em toda música nova.

## Como usar

### Como usuário

1. Abra o app e use a aba **Search** para procurar uma música (ou navegue pelo catálogo local de demonstração).
2. Adicione a música à sua **Library** — ela fica salva com suas favoritas e progresso.
3. Abra a música na aba **Player**: toque, ajuste velocidade e tom, ligue o metrônomo/count-in e use o mixer para mutar ou solar faixas.
4. Siga a tablatura, que rola sozinha no ritmo da música, ou toque em qualquer trecho para pular pra lá.
5. Configure seus padrões preferidos na aba **Settings** — eles valem para toda música nova.

### Como desenvolvedor

- O app nativo é um projeto Xcode (`GuitarTabPlayer.xcodeproj`), escrito em SwiftUI + SwiftData. Abra o projeto no Xcode, escolha um simulador/dispositivo iOS 17+ e rode.
- Também existe uma versão para navegador em [web/](web/) e um instalador para Windows em [windows/](windows/).
- Os scripts em [scripts/](scripts/) geram os dados de tab (`build_songs_json.py`, `make_tabs.py`) e os builds (`build.sh`, `build_web.py`).

## Plataformas e versões de SO

| Plataforma           | Como roda                                                | Requisito mínimo           |
| -------------------- | --------------------------------------------------------- | --------------------------- |
| iOS (iPhone e iPad)  | App nativo SwiftUI, via Xcode/App Store                  | iOS 17.0+                   |
| Navegador            | Versão web servida a partir de [web/](web/)               | Qualquer navegador moderno  |
| Windows              | Instalador em [windows/](windows/) (`Install.ps1` / `Instalar.cmd`) | Windows 10 ou superior |

## Licença

Distribuído sob a licença MIT — veja [LICENSE](LICENSE).
