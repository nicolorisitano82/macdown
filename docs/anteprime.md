# Due anteprime: quella sotto il puntatore e quella nel Finder

Diario breve, nella serie del [WYSIWYG](wysiwyg-testo.md), dei
[blocchi di codice](blocchi-codice.md) e del [plugin drawio](drawio.md).
Due funzioni che sembrano lontane e chiedono la stessa cosa: **sapere cosa
c'è dall'altra parte senza aprire niente**.

---

## Ferma il puntatore su un link, e te lo dico

Nell'anteprima, tenendo il puntatore su un link per **cinque secondi**, si
apre una cartolina piccola: titolo del documento vicino e le sue prime
righe, l'immagine se il link è un'immagine, i pezzi dell'indirizzo se è un
indirizzo, o la frase che dice che il file non c'è ancora. Si sposta il
puntatore e la cartolina va via.

I cinque secondi sono un tempo lungo di proposito. Un'anteprima che scatta
subito è un impiccio mentre si legge: appare mentre l'occhio passa. A cinque
secondi il puntatore fermo è una domanda, non un incidente.

Il conto lo tiene la pagina, non l'applicazione: uno `setTimeout` messo con
un `WKUserScript`, annullato da `mouseout`, dallo scorrimento, dal perdere
il fuoco e dal passare a un altro link. Quando scade, la pagina manda un
messaggio con l'`href` e il rettangolo del link; l'applicazione lo converte
in coordinate della vista — attenzione al `pageZoom` e al fatto che la vista
web non è capovolta come quella di testo — e ci appoggia il popover.

### Quello che non fa

**Non scarica niente.** Un indirizzo `https://` viene *smontato*: host,
percorso con la sua query, schema. Tre righe di testo che c'erano già
nell'`href`. Bastano a dire dove porta un link, e nessuno scopre che stai
leggendo un documento perché il puntatore ci è passato sopra.

Dal disco legge solo un file che hai già: il documento vicino a cui il link
punta. Un `[[wikilink]]` senza estensione lo cerca come `md`, `markdown`,
`txt`; un percorso relativo lo risolve sulla cartella del documento, e
un'ancora `#qualcosa` non è un posto dove andare, quindi non apre nulla.

Il titolo è il primo titolo del file, e il corpo le prime righe **saltando
quel titolo**: ripeterlo due volte in una cartolina alta cinque righe è
spreco.

---

## Lo stesso documento, visto dal Finder

Barra spaziatrice su un `.md` nel Finder: prima si vedeva il sorgente in
carattere a spaziatura fissa, cancelletti e asterischi compresi. Ora si vede
il documento **come si legge**, con lo stesso foglio di stile con cui si
apre nell'applicazione (`GitHub2`), titoli, tabelle, blocchi di codice e le
caselle dei to-do disegnate come caselle.

È un'estensione a parte, `MacDownQuickLook.appex`, dentro l'app. Compila i
sorgenti di hoedown per conto suo: la conversione è la stessa, ma
l'estensione non porta con sé preferenze, plugin, evidenziazione. Il
montaggio della pagina — titolo, stile, caselle, figure — sta in
`MDPreviewPage`, che è codice Foundation puro e per questo ha le sue prove.

### Il front-matter non è il documento

Un documento che comincia con `---\ntitle: …\n---` mostrava, in anteprima,
una riga orizzontale e un titolo `title: scartato`. Ora il front-matter
viene lasciato fuori. Ma non basta guardare il primo `---`: **un documento
può cominciare con una riga orizzontale**, e prenderla per front-matter
significa mangiarsi il titolo vero fino al `---` successivo. Quindi la
riga dopo l'apertura deve *somigliare* a una voce (`chiave: valore`), e un
blocco che non si chiude non era front-matter.

### La sabbia, e le figure che ci restano dentro

Qui la parte che valeva il pomeriggio. Quick Look carica **solo estensioni
in sandbox**: senza `com.apple.security.app-sandbox` l'estensione non viene
nemmeno registrata — `pluginkit -a` risponde `invalid plugin path` e non
spiega altro. Dentro la sandbox arriva il documento e **basta**: le immagini
tenute accanto sono fuori portata. Misurato, non supposto: una riga di log
temporanea diceva `pictures wanted 1, sent 0`.

Due conseguenze nel codice:

* le figure viaggiano **con la risposta**, come allegati `cid:`, perché la
  pagina disegnata da Quick Look non ha accesso al disco;
* prima di rinominare una `src` in `cid:` l'estensione **apre davvero il
  file**. Vedere un file non è poterlo leggere, e una `cid:` senza allegato
  è un'immagine rotta garantita.

Per far vedere le figure serve un'eccezione: lettura, in sola lettura, della
cartella utente. Il perimetro resta stretto — non scrive niente, e la pagina
ha una `Content-Security-Policy` `default-src 'none'` che le vieta la rete.
Un documento ostile, al massimo, si fa mostrare un file che l'utente ha già:
niente script, niente immagini remote, nessun modo di mandare fuori quello
che ha letto. E il tempo di lettura ha un tetto: due megabyte di testo, poi
la pagina dice che il resto non è mostrato.

---

## Tre inciampi da ricordare, se l'estensione «non compare»

Sono tutti e tre nella registrazione, non nel codice.

1. **`codesign --force --deep` toglie i diritti alle cose annidate.** Firmato
   così il pacchetto dell'app, l'`appex` dentro perde `app-sandbox` e Quick
   Look lo ignora in silenzio. Si firma l'estensione con i suoi diritti, e
   *poi* l'app senza `--deep`.
2. **`lsregister -f` da solo non basta** quando un record vecchio è già lì.
   La sequenza che funziona è `lsregister -u` e poi
   `lsregister -f -R -trusted` sul pacchetto dell'app.
3. **`QLIsDataBasedPreview` non è opzionale.** Senza quella chiave in
   `NSExtensionAttributes` il sistema tratta l'estensione come se avesse una
   vista da mostrare, e muore su
   `Assertion failure in QLPreviewExtensionViewController.m:139` — che è
   l'unico posto dove lo dice.

E un'ultima cosa che fa perdere tempo: Quick Look **tiene in cache**
l'anteprima. Se stai provando una modifica sullo stesso file e non cambia
niente, non è la modifica: copia il file con un altro nome.

---

## Dove sta il conto

| Cosa | Dove |
|---|---|
| Cartolina del link | `MacDown/Code/Utility/MPLinkPreview.{h,m}`, `MacDown/Code/View/MPLinkPreviewViewController.{h,m}` |
| Attesa e posizione | `MPDocument.m`, `kMPHoverSource` e `showLinkPreviewFor:` |
| Pagina del Finder | `QuickLook/MDPreviewPage.{h,m}` |
| Estensione | `QuickLook/MDQuickLookProvider.{h,m}`, `QuickLook/Info.plist`, `QuickLook/MacDownQuickLook.entitlements` |
| Prove | `MacDownTests/MPLinkPreviewTests.m` (9), `MacDownTests/MDPreviewPageTests.m` (18) |
