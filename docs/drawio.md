# I diagrammi draw.io

Diario, come per il [WYSIWYG](wysiwyg-testo.md), l'[aiuto alla
scrittura](ai-locale.md) e i [blocchi di codice](blocchi-codice.md). Serve a
chi riprende in mano questa parte: **la cosa che ho verificato prima di
scrivere il resto, e la strada che ho chiuso.**

---

## Un plug-in vero, perché il posto c'era

MacDown ha un caricatore di plug-in dal 2016 e in questo fork nessuno lo
usava: bundle `.plugin` in `~/Library/Application Support/MacDown/PlugIns`,
classe principale che risponde a `name` e `run:`, un pannello per
attivarli e disattivarli. Chiedere «scrivi un plug-in» e ricevere invece una
voce di menù dentro l'applicazione sarebbe stato rispondere a un'altra
domanda.

Quindi: `Drawio.plugin`, target suo, compilato accanto all'app (dipendenza
esplicita, così non può restare indietro) e copiato in `dist/`, dove il
gestore dei plug-in va a prenderlo.

Il plug-in **non chiama dentro MacDown**. Trova il documento con
`NSDocumentController` e l'editor cercando la prima `NSTextView` nella
finestra. Una text view in una finestra è una text view in qualunque
versione; `MPDocument` no.

---

## Prima ho misurato se si poteva disegnare in locale

L'ordine non è stato: scrivo il plug-in e poi vedo. Era: **il render locale
funziona, sì o no?** Se no, tutto il resto era da rifare intorno a una
chiamata di rete.

Una sonda di ottanta righe: `WKWebView` fuori da ogni finestra, il
visualizzatore di draw.io scritto dentro la pagina, `takeSnapshot`, e poi
tre numeri — quanti SVG, quanto grandi, quanti pixel non bianchi.

Il primo tentativo ha risposto `svgs: 0`. Chiamavo
`GraphViewer.createViewerForElement` a mano; il visualizzatore si avvia da
sé sugli elementi con `class="mxgraph"` e l'attributo `data-mxgraph`. Con la
forma standard: **un SVG, 585×125, nessun errore in console.** Poi la stessa
pagina con una CSP che blocca tutto il remoto: **identica.** E il PNG
mostrava le forme, i colori, le etichette e le frecce al loro posto.

Da lì il resto era lavoro, non ricerca.

> Il visualizzatore è dentro la pagina come testo, non come `src`. Due
> ragioni: una pagina caricata da una stringa non ha una cartella contro cui
> risolvere un `src`, e copiare due megabyte e mezzo in una cartella
> temporanea per ogni figura è peggio che tenerle in una stringa per un
> istante.

---

## Due indirizzi su otto

Alla domanda «ma non ci sono librerie?» la risposta è che la libreria è
quella e la stiamo usando: non esiste un renderer di `.drawio` che non sia
il JavaScript di draw.io. L'export server in docker, `drawio-batch`, l'app
desktop con `--export` sono **lo stesso JS** dentro un Electron; JGraphX, il
port Java di mxGraph, disegna i modelli base e non conosce le librerie di
forme di draw.io; una libreria nativa non c'è.

Ma andando a verificarlo ho trovato una cosa mia. Il visualizzatore tiene
**otto** indirizzi propri, tutti su `viewer.diagrams.net`:

```
PROXY_URL  STYLE_PATH  SHAPES_PATH  STENCIL_PATH
DRAW_MATH_URL  GRAPH_IMAGE_PATH  mxImageBasePath  mxBasePath
```

Io ne avevo svuotati **due**, e avevo scritto che la pagina non chiedeva
niente a nessuno. Per il diagramma della sonda era vero — le forme di base
sono dentro il JS — e per un diagramma con la libreria AWS non lo era
affatto: `STENCIL_PATH/aws4.xml` sarebbe uscito, mentre il plug-in
dichiarava di lavorare offline.

Ora sono svuotati tutti e otto, e **vuoti per davvero**: al primo tentativo
scrivevo `'/stencils'` invece di `''`, cioè una richiesta che falliva in
silenzio invece di una richiesta non fatta. La prova lo ha preso: elenca gli
otto nomi e pretende `window.NOME=''` per ognuno.

Quello che si perde svuotandoli sono le librerie di forme grandi, che il
visualizzatore non porta dentro. Quindi c'è una casella, spenta di suo, per
scaricarle: il diagramma resta qui, escono le richieste dei file di forme.
Ed è una scelta migliore dell'export server per questo problema — lì il
diagramma lo mandi tutto.

---

## La strada che ho chiuso

`https://convert.diagrams.net/node/export` risponde così:

```
Referer not allowed: this service only accepts requests from draw.io applications
```

Con un `Referer: https://app.diagrams.net/` risponde invece con un PNG di
14 KB. Ho verificato che funziona, e **non l'ho messo**: chi offre il
servizio ha detto per chi è, e aggirarlo dichiarando di essere draw.io non è
una cosa da spedire dentro un programma.

La via esterna esiste comunque, e va verso un **export server tuo** —
`jgraph/export-server` in docker, o qualunque cosa parli quell'API. Serve
per le librerie di forme che si scaricano le immagini. L'indirizzo lo dai
nel foglio e viene ricordato.

---

## Le quattro forme di un file .drawio

Quella che conta è la seconda, perché è come draw.io salva davvero:
**deflate grezzo, base64, URI-escape**. Tre passaggi, tre modi di
sbagliare, e se sbagli l'ultimo non ottieni un errore: ottieni del testo
che non è XML. Per questo `MDDrawioXMLFromCompactPayload` controlla che in
fondo ci sia un `<mxGraphModel` e altrimenti dice no.

Nel test il payload è **congelato**: un base64 vero, generato una volta,
scritto nel file. Così i tre passaggi vengono provati insieme e non contro
una mia reimplementazione.

Le altre tre: XML in chiaro, un PNG che porta il file in un chunk `tEXt`, un
SVG che lo porta in un attributo — le ultime due sono "PNG modificabile" e
"SVG modificabile" nel menù di draw.io.

---

## Una pagina, un'immagine

Un file di quattro schede dà quattro PNG, ognuno col nome della sua scheda.
E reimportare **riscrive** i file senza aggiungere un secondo collegamento:
è così che una figura in un verbale si aggiorna quando il diagramma cambia,
che è il motivo per cui uno importa un diagramma in un documento.

Il nome della pagina passa per uno slug, perché una scheda chiamata
`rete/interna` non deve creare una cartella; e il collegamento è relativo
quando l'immagine sta sotto la cartella del documento, così i due si
spostano insieme.

Le due risposte con dentro un più-uno — lo slug e il percorso relativo —
sono classe a sé, `MDDrawioNaming`, per poterle provare senza una finestra.
