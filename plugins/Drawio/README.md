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

**Su questo Mac** — è l'impostazione predefinita. Il visualizzatore di
draw.io viaggia dentro il plug-in (2,6 MB di JavaScript, Apache 2.0, JGraph
Ltd) e disegna in un WebKit che non chiede niente a nessuno: la pagina è
costruita col visualizzatore scritto dentro, `STYLE_PATH` e `PROXY_URL`
vuoti, e nessuna risorsa esterna. **Il diagramma non esce dalla macchina, e
funziona senza connessione.**

**Su un export server tuo** — l'indirizzo lo indichi nel foglio; viene
ricordato. Serve per le librerie di forme che si portano dietro immagini da
scaricare. È l'API del servlet di draw.io (`format`, `xml`, `scale`), quella
che parla anche l'immagine docker `jgraph/export-server`:

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

`MacDownTests/MDDrawioPlugInTests.m`, dieci prove. Girano **sul bundle
compilato**, caricato per nome come lo carica l'applicazione: quello che
viene controllato è l'artefatto — la classe principale c'è, il
visualizzatore è dentro, un diagramma esce come immagine e non come pagina
bianca — non una copia dei sorgenti compilata nei test.

## Aggiornare il visualizzatore

```bash
Tools/fetch_drawio_viewer.sh
```

È committato invece di essere scaricato dalla build: una build che ha
bisogno della rete è una build che fallisce in treno.
