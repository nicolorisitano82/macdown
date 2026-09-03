# Drawio.plugin — un diagramma draw.io dentro il documento

Scegli un file `.drawio`, e ogni sua pagina diventa un PNG accanto al
documento, collegato dove sta il cursore.

Un `.drawio` è XML che solo draw.io sa disegnare: un documento Markdown può
collegarlo quanto vuole, non si vede niente. Questo plug-in disegna.

## Installarlo

**Menu applicazione › Gestisci plug-in… › +** e scegli `Drawio.plugin`
(nella cartella `dist/Release/` accanto all'app, o dove l'hai compilato).
Finisce in `~/Library/Application Support/MacDown/PlugIns/`.

Poi la voce **Importa un diagramma draw.io…** è nel menu dei plug-in.

## Cosa legge

Le quattro forme in cui un diagramma arriva:

| | |
|---|---|
| `mxfile` con pagine in XML | come le scrive un export |
| `mxfile` con pagine compresse | **come le salva draw.io**: deflate, base64, URI-escape |
| PNG modificabile | il file intero in un chunk di testo |
| SVG modificabile | il file intero in un attributo |

Un file di più pagine dà **un PNG per pagina**, ognuno col nome della sua
scheda: un documento che collega una sola immagine e si ritrova quattro
pagine di diagramma dentro non è quello che uno voleva.

Reimportare lo stesso diagramma **riscrive** i PNG e non aggiunge un
secondo collegamento: è così che una figura si aggiorna quando il diagramma
cambia.

## Dove viene disegnato

**Su questo Mac** — è l'impostazione predefinita, e **non serve
connessione**. Dentro il plug-in ci sono:

| | |
|---|---|
| `viewer.min.js` | il visualizzatore di draw.io, 2,6 MB |
| `stencils/`, `shapes/`, `styles/` | **97 librerie di forme**, 23 MB di XML tenuti gzippati in 3,3 MB |

Sono le librerie che il visualizzatore non porta dentro e andrebbe a
scaricare: AWS, Cisco, Azure, GCP, BPMN, Kubernetes, mockup, e le altre
novanta. Quali esattamente non è una lista scritta a mano — sono quelle
nominate nel codice del visualizzatore, estratte da lì da
`Tools/fetch_drawio_viewer.sh`.

Il visualizzatore tiene otto indirizzi propri, tutti su
`viewer.diagrams.net`: `PROXY_URL`, `STYLE_PATH`, `SHAPES_PATH`,
`STENCIL_PATH`, `DRAW_MATH_URL`, `GRAPH_IMAGE_PATH`, `mxImageBasePath`,
`mxBasePath`. Nella pagina che il plug-in costruisce **tutti e otto**
puntano dentro il bundle — tranne il proxy e MathJax, che sono vuoti.

Le librerie vengono servite da uno **schema URL suo**, `drawio-res://`, non
da `file:`: una pagina caricata da una stringa non ha un'origine da cui
leggere un file locale, e copiare le librerie in una cartella temporanea per
ogni figura è peggio che leggerle dove sono. Anche la pagina passa da lì,
così pagina e librerie condividono l'origine e le richieste XHR del
visualizzatore non sono cross-origin. Niente di quello schema può uscire
dalle risorse del bundle.

L'unica cosa non portata dentro è **MathJax**: sono decine di file caricati
su richiesta, e la matematica dentro un diagramma è abbastanza rara da non
portarsi dietro tutto quello. Una formula in un diagramma resta senza
comporre.

**Su un export server tuo** — l'indirizzo lo indichi nel foglio; viene
ricordato. Con le librerie già dentro serve poco, ma resta la strada per
chi ne ha uno e vuole passare da lì. È l'API del servlet di draw.io
(`format`, `xml`, `scale`), quella che parla anche l'immagine docker
`jgraph/export-server`:

```bash
docker run -it --rm -p 8000:8000 jgraph/export-server
```

e nel foglio `http://localhost:8000/`.

### Perché non il servizio pubblico di diagrams.net

Perché lo dice lui:

```
Referer not allowed: this service only accepts requests from draw.io applications
```

Funziona se gli si dichiara un `Referer` di draw.io. Aggirare così una
regola di accesso di chi offre il servizio non è una cosa da mettere in un
programma che si distribuisce.

## Le prove

`MacDownTests/MDDrawioPlugInTests.m`, dodici prove. Girano **sul bundle
compilato**, caricato per nome come lo carica l'applicazione: quello che
viene controllato è l'artefatto — la classe principale c'è, il
visualizzatore è dentro, un diagramma esce come immagine e non come pagina
bianca — non una copia dei sorgenti compilata nei test.

Una di quelle prove è la sola che dica se le librerie funzionano davvero:
un diagramma con una forma AWS, e poi la domanda se `stencils/aws4.xml` è
stato **servito** e non solo **chiesto**. Le due liste nel gestore sono
tenute separate esattamente per questo: un diagramma il cui stencil non è
arrivato si disegna comunque — come un rettangolo — e la figura sembra
plausibile.

## Aggiornare il visualizzatore e le librerie

```bash
Tools/fetch_drawio_viewer.sh
```

Scarica il visualizzatore, estrae dal suo codice i percorsi delle librerie
che sa chiedere, le scarica e le gzippa. Un paio non ci sono più sul sito
(`stencils/sap.xml`); lo script lo dice e tira avanti, come fa il
visualizzatore.

È tutto committato invece di essere scaricato dalla build: una build che ha
bisogno della rete è una build che fallisce in treno.
