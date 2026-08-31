# WYSIWYG: la parte di testo

Una roadmap per arrivare a un editor che mostra quello che il testo
significa, senza smettere di essere un editor di markdown.

Il punto di partenza non è zero, e a questo punto non è nemmeno la fine:
tutte le fasi qui sotto sono fatte e segnate come tali. Quello che resta
è scritto in fondo, sotto «Dove andare da qui».

---

## Il principio da cui non allontanarsi

**Il documento resta la stringa markdown.** Tutto quello che segue cambia
come il testo viene *disegnato*, mai cosa viene *salvato*. MacDown salva
`self.editor.string`, quindi nessuna quantità di stile può corrompere un
file. È questa proprietà che rende ogni passo reversibile: se una fase
esce male, si spegne e il documento è intatto.

Il momento in cui si è tentati di violarlo — «tanto vale tenere il
grassetto come attributo e serializzarlo dopo» — è il momento in cui si
sta costruendo un word processor con un dialetto proprietario. Da lì non
si torna indietro.

---

## Fase 0 — Le fondamenta *(fatta)*

L'evidenziatore parsa il documento a ogni pausa e produce un elenco di
intervalli tipizzati: `{tipo, inizio, fine}` per titoli, enfasi, codice,
citazioni, liste. È il modello semantico che serve a tutto il resto.

Prima era privato. Ora c'è un gancio che lo espone a ogni parse
(`elementsDidChange`), quindi nessuno deve parsare il documento una
seconda volta.

**Se dovessi rifarlo:** niente. È il pezzo su cui poggia ogni fase
successiva ed è piccolo.

---

## Fase 1 — La tipografia *(fatta, e più piccola del previsto)*

I titoli sono più grandi, l'enfasi è corsiva, il codice è a spaziatura
fissa.

**La lezione che vale più del codice:** quasi tutto questo lo facevano
già i temi dell'editor. Il formato `.style` supporta `font-size`,
`font-style`, `foreground` e `background-color`, e i temi li usano. Chi
affronta una fase nuova dovrebbe prima chiedersi *chi fa già questo
lavoro*, perché la risposta cambia la fase.

Quello che restava di genuino era una cosa sola: le dimensioni del tema
sono in punti assoluti, quindi non seguono il corpo scelto dal lettore.
A 22pt i titoli si distinguono appena, oltre i 24 diventano più piccoli
del testo. Ora le proporzioni del tema vengono mantenute e riscalate.

---

## Fase 2 — Far sparire i marcatori *(fatta)*

**Era qui che si decideva se il progetto stava in piedi**, e sta in piedi.

Fatto: soppressione dei glifi, ripristino sotto il cursore, cancellazione
che toglie l'enfasi invece di spezzarla, movimento che scavalca i
delimitatori. Enfasi, forte e codice in linea, come previsto.

**Le due lezioni che valgono più del codice.**

La terza, trovata molto dopo mentre si estendeva il nascondimento ai
titoli: **la freccia destra scavalcava i marcatori e poi faceva anche il
passo**, mentre la freccia sinistra faceva il passo e poi scavalcava. Con
il cursore appoggiato su un marcatore — ci si arriva con un clic, con
Inizio, o tornando all'inizio di una riga — quello a destra usciva un
carattere oltre. Il difetto è rimasto invisibile finché non si è provato a
cancellare da lì. *Due operazioni simmetriche vanno scritte simmetriche,
altrimenti la differenza si paga in un caso che nessuno pensa di provare.*

La prima: la regola «scavalca ciò che non si vede» *si autoannulla*.
Avvicinandosi a un costrutto il ripristino rende i marcatori visibili,
quindi non esiste un istante in cui il cursore è adiacente a un marcatore
nascosto. La regola giusta è più rozza e funziona: con il nascondimento
acceso i delimitatori non sono posizioni.

> Questa premessa è rimasta falsa per mesi ai due bordi esterni, e il
> ragionamento che ci stava sopra è caduto con lei. Vedi
> *[Correzione — il bordo del costrutto](#correzione--il-bordo-del-costrutto)*.

La seconda: la correzione a «cancellare un asterisco lascia l'altro» non
è cancellare anche l'altro — resterebbe markup rotto dall'altro capo. È
togliere l'enfasi: `**grassetto**` diventa `grassetto`. Quando una
correzione sembra doversi applicare due volte, di solito l'operazione è
un'altra.

### Il meccanismo

L'editor è in TextKit 1 — perché il codice accede a `layoutManager` — ed
è una fortuna: l'unico modo affidabile di nascondere caratteri è il
gancio di generazione dei glifi, `NSLayoutManagerDelegate`, restituendo
`NSGlyphPropertyNull` per gli intervalli da sopprimere. TextKit 2 non
offre l'equivalente.

### Il problema che non ha una soluzione ovvia

Il parser dà l'intervallo dell'*intero* costrutto: `**grassetto**` arriva
come un solo elemento STRONG che comprende gli asterischi. Per
nasconderli bisogna derivarne le posizioni dal tipo, e la regola non è
uniforme:

| Costrutto | Insidia |
|---|---|
| `*x*` e `**x**` | stesso tipo, delimitatore di lunghezza diversa |
| `` `x` `` e ``` ``x`` ``` | numero di backtick variabile |
| `# Titolo #` | chiusura opzionale |
| Titolo setext | il marcatore è sulla **riga successiva** |

Serve una funzione per tipo che, dato l'intervallo e la sorgente,
restituisca gli intervalli dei marcatori. È noioso ma delimitato, e
sbagliarlo si vede subito.

### Il cursore

Se `**` è invisibile, cosa succede quando ci scrivi dentro? La risposta
che usano tutti — Typora, Obsidian — è **rivelare il markup
dell'elemento che contiene la selezione**. Significa reagire al cambio
di selezione, ricalcolare cosa rivelare, invalidare i glifi di quelle
righe.

E poi il caso cattivo: cancellare un `*` di una coppia nascosta deve
fare qualcosa di sensato, non lasciare markup rotto e invisibile.

### Come affrontarla

Non tutta insieme. Tre tipi soltanto: **enfasi, forte, codice in linea**.
Niente link né immagini, che hanno due parti — testo e destinazione — e
sollevano subito la domanda su cosa mostrare.

Se il cursore si comporta bene su questi tre, il resto è estensione. Se
non si comporta bene, hai scoperto che la fase non regge prima di aver
scritto il codice per dodici tipi.

**Esito:** si comporta bene. Estendere ad altri tipi è ora lavoro
meccanico — l'unico che richiede una decisione nuova è il link, che ha
due parti e obbliga a scegliere cosa mostrare.

### I link, fatti dopo *(fatti)*

La decisione è stata: si mostra il testo, sparisce la destinazione.
`[testo](url)` si legge «testo» finché il cursore non entra.

La cosa da sapere prima di scriverla: fino a qui i due capi di un
costrutto erano **uguali** — due asterischi di qua, due di là. Un link
no: `[` da una parte e `](url)` dall'altra. Il codice che teneva «la
lunghezza del marcatore» andava sostituito con due intervalli separati,
apertura e chiusura, e da lì tutto il resto (rivelazione, cancellazione,
salto del cursore) ha continuato a funzionare senza toccarlo.

I link di riferimento — `[testo][rif]` con la definizione altrove — sono
lasciati stare di proposito: nascondere `[rif]` toglie l'unico modo di
sapere quale definizione stavi usando.

### I titoli e le citazioni, fatti dopo *(fatti)*

I cancelletti dei titoli ATX spariscono — il titolo è già più grande, non
serve dirlo due volte — e con loro lo spazio che li segue, altrimenti il
titolo resterebbe rientrato di un carattere per nessun motivo visibile.
Sparisce anche la chiusura opzionale di `# Titolo #`.

I `>` delle citazioni spariscono uno per riga, e quello che resta è testo
rientrato con la barra nel margine: la fase 3 disegnava già la barra, e
finalmente è lei a dire che è una citazione.

**Due cose imparate qui.**

*Il parser non riporta la citazione, riporta il marcatore.* Un elemento
`pmh_BLOCKQUOTE` è lungo due caratteri: `> `. La citazione va ricostruita
dalla riga su cui il marcatore si trova. Comodo, a conti fatti — un
costrutto per riga è la forma giusta, perché i segni non sono una coppia
attorno al testo ma un prefisso ripetuto lungo il fianco.

*La stessa insidia dei glifi soppressi, terza volta.* Nascondere il `>`
faceva saltare la barra una riga più su, esattamente come per la riga
orizzontale: un blocco di glifi soppressi a inizio riga viene assorbito
nel frammento precedente. La barra ora si misura dal testo citato, non dal
marcatore. **Quando una regola di misura si rompe per la terza volta nello
stesso modo, non è sfortuna: è che si sta misurando la cosa sbagliata.**

### Quello che resta visibile, e perché

- **I titoli setext.** Il marcatore è sulla riga sotto, e sopprimere i
  glifi di una riga intera lascia la riga: i segni vanno via, la riga
  vuota no. Un buco sotto ogni titolo sarebbe peggio dei segni.
- **Le immagini.** `![diagramma](x.png)` ridotto a «diagramma» è
  indistinguibile da una parola qualsiasi: il documento mentirebbe su cosa
  contiene. La risposta onesta è disegnare l'immagine, che è una fase a sé.
- **Barrato ed evidenza.** Il parser non li conosce — sono estensioni del
  renderer — quindi servirebbe una scansione a parte, come per le tabelle.
- **I punti elenco.** Il trattino è informazione, non un delimitatore.

---

## Fase 3 — L'impaginazione di blocco *(fatta)*

Qui i temi non arrivano, e il guadagno visivo è alto rispetto al rischio.

- **Rientri delle liste**, con rientro sporgente sui capoversi successivi
- **Barra della citazione** nel margine
- **Spaziatura dei titoli**, più aria sopra che sotto
- **Righe orizzontali** disegnate invece che tre trattini

`NSParagraphStyle` copre rientri e spaziature. La barra della citazione e
la riga orizzontale sono disegnate in `drawViewBackgroundInRect:`.

Nessuno di questi tocca il cursore, e infatti è stata la fase tranquilla
che prometteva di essere. Un buon posto dove andare se la fase 2 si è
impantanata e serve un risultato.

**Le tre cose che non erano ovvie.**

*Lo stile di paragrafo va derivato, non costruito.* La spaziatura fra le
righe scelta nelle preferenze vive nello stesso attributo dei rientri:
un `NSParagraphStyle` nuovo di zecca la butta via senza dire niente. Si
parte da quello che c'è già e si aggiunge.

*Una barra si disegna per frammento di riga, non per intervallo.* Una
citazione che va a capo ha un solo rettangolo che copre due righe, e la
riga di continuazione non ha un `>` suo: disegnando dai frammenti la
barra viene continua, disegnando dall'intervallo viene a pezzi.

*I glifi soppressi a inizio riga finiscono nel frammento di sopra.* La
riga orizzontale è fatta solo di trattini nascosti, quindi chiedere «dove
sono i trattini» risponde con la riga precedente e la linea viene
disegnata una riga più su. Si misura dal ritorno a capo che chiude la
riga, che un glifo ce l'ha. Vale per qualunque costrutto interamente
nascosto: è la stessa insidia della fase 2 vista da un'altra angolazione.

E una scelta di struttura che si è rivelata giusta: gli intervalli delle
righe orizzontali li produce **chi nasconde i trattini**, non chi
impagina. Sono esattamente i caratteri che hanno smesso di essere
disegnati, e una seconda misura fatta altrove potrebbe non coincidere.
Per lo stesso motivo il disegno richiede entrambe le preferenze accese:
una linea disegnata accanto a tre trattini visibili sono due righe.

---

## Fase 4 — Il comportamento in scrittura *(fatta)*

Quello che trasforma «guarda come è bello» in «si scrive meglio».

- I marcatori collassano appena il costrutto è completo
- ⌘B e ⌘I si comportano da interruttori sulla selezione
- Incollare del testo formattato produce markdown, non testo semplice

Questa fase ha senso solo dopo la 2: senza sparizione dei marcatori,
collassarli non significa niente.

### Il collasso era una riga sola

La regola della fase 2 allargava di un carattere per lato l'intervallo che
rivela i marcatori, così che con il cursore appena fuori si potesse
cancellarli. Bastava toglierla — rivelare solo *dentro* — perché il
collasso funzionasse: chiudendo il secondo `**` il cursore finisce
esattamente sul bordo, che ora non conta come «dentro».

Si poteva togliere perché nel frattempo la cancellazione non dipendeva più
da cosa fosse visibile. **Quando una fase sembra richiedere codice nuovo,
vale la pena guardare se una decisione precedente è diventata superflua.**

> E poi è stata rimessa, perché il carattere in più per lato non serviva
> alla cancellazione: serviva a *vedere*. Vedi sotto.

### ⌘B senza selezione

Il toggle c'era già e sapeva anche togliere il markup; gli mancava solo
cosa fare a selezione vuota — inseriva `****` e ci metteva il cursore in
mezzo. Ora prende la parola sotto il cursore, come farebbe un
elaboratore di testi.

Con i marcatori nascosti c'è un dettaglio: il cursore dopo `**forte**` è
disegnato subito dopo la `e`, quindi «la parola sotto il cursore» deve
scavalcare il delimitatore che sta in mezzo prima di cercarla.

### Il difetto vero: gli intervalli invecchiano

Questa è la lezione della fase, e non riguarda nessuno dei tre punti.

Il parse arriva dopo una pausa, ma il testo si muove a ogni tasto. Fra i
due, gli intervalli registrati descrivono un documento che non esiste più.
Finché servivano solo a *non disegnare* dei glifi, l'errore durava un
decimo di secondo e non si vedeva. Appena hanno cominciato a decidere
*cosa cancellare*, dieci backspace veloci lasciavano una fila di
asterischi orfani.

La correzione non è aspettare il parse: è far seguire agli intervalli le
modifiche mentre avvengono. Una modifica prima del costrutto lo trasla,
una dentro il contenuto lo allunga, una che tocca un delimitatore lo
distrugge — e quel costrutto smette di esistere fino al parse successivo.

**Se un dato derivato inizia a guidare un'azione distruttiva, la latenza
con cui si aggiorna smette di essere un dettaglio di rendering.**

E il secondo pezzo della stessa storia: dopo aver cancellato *attraverso*
dei marcatori nascosti, il cursore va rimesso dall'altra parte. Lasciarlo
nel punto della cancellazione lo mette dentro il costrutto, che quindi si
rivela, e il tasto premuto una seconda volta fa una cosa diversa dalla
prima. Un comando ripetuto deve ripetersi.

### Incollare

Un convertitore HTML→markdown scritto per l'occasione
(`MPMarkdownFromRichText`): titoli, elenchi annidati, link, immagini,
codice con il linguaggio, citazioni, tabelle, entità. Quello che non
riconosce contribuisce il suo testo e nient'altro — cioè lo stesso
risultato di incollare testo semplice, mai una pagina di parentesi
angolari.

Le tre cose che il mondo reale impone e che non si scoprono a tavolino:

- **Google Docs avvolge tutto in `<b style="font-weight:normal">`.** Preso
  alla lettera, ogni incollaggio da Google Docs è in grassetto.
- **Un `<a>` che avvolge un `<h3>`.** Il markup in linea non può
  attraversare un confine di blocco: se il contenuto di un costrutto
  contiene un a capo, i delimitatori vanno tolti, non chiusi.
- **`<p>` dentro `<li>`.** Preso alla lettera stacca il testo dal punto
  elenco. Dentro una lista lo stacco di blocco si riduce a una riga.

E una scelta: `⌘⇧V` incolla il testo esattamente com'è. Serviva una via
d'uscita, e la voce di menu non c'era — è stata aggiunta.

---

## Fase 5 — Le tabelle *(fatta, poi ridotta)*

I comandi per modificarle: tasto destro sopra una tabella per righe e
colonne, allineamento, riparazione della riga dei trattini; e «crea
tabella» nella barra degli strumenti. Sotto c'è `MPTableSource`, un
modello testo-dentro-testo-fuori, che è la parte con i test.

### Perché non riscrivere il file

È quello che fanno tutti: si riempiono le celle di spazi finché le barre
non tornano. Funziona una volta e poi ti combatte — riscrive righe che non
hai toccato, a timer, mentre ci hai dentro il cursore. E viola il principio
da cui parte tutto: **il documento è la stringa che hai scritto**.

I comandi riscrivono la tabella solo quando glielo chiedi, e in un colpo
solo: una sostituzione, un passo di annullamento.

### L'allineamento delle colonne, tolto

C'era anche una resa a colonne nell'editor: ogni cella misurata, ogni
colonna larga quanto la sua cella più larga, la differenza messa nella
crenatura del carattere prima della barra — `NSKernAttributeName`, che
allarga l'avanzamento del carattere su cui è messo. Le barre si
allineavano e il file restava carattere per carattere quello battuto.

Era ingegnoso e l'ha detto l'uso: **la riga dei trattini non si allarga**.
`|---` seguito da una colonna larga lascia i tre trattini appiccicati e
poi il vuoto, e a occhio quella riga sembra aver perso i trattini. La
segnalazione è arrivata proprio così — «le tabelle nell'editor perdono i
`---`» — e insieme la richiesta giusta: nell'editor la tabella sia la
sorgente, la resa a colonne stia nell'anteprima, che ha lo spazio per
farla.

Tolta. `MPTableAligner` non c'è più, e con lui la preferenza che lo
accendeva e il predicato che serviva solo a misurarlo.

**La lezione.** Una resa che copre il novanta per cento delle righe di una
tabella e non la riga che ne dichiara la struttura non è una resa: è una
resa e un'eccezione, e l'eccezione è proprio la riga che conta.

### Quello che resta non ovvio

*La tabella va trovata a mano.* Il parser non conosce le tabelle — sono
un'estensione del renderer, non del linguaggio che analizza. È una
scansione per righe: una riga con delle barre diventa una tabella solo
quando la riga sotto è fatta di trattini.

*Le barre di apertura e chiusura non sono confini di cella.* `| a | b |`
ha due celle, non quattro: i pezzi vuoti ai due capi vanno scartati. Vale
per il modello e vale per il salto dall'anteprima al testo.

---

## Dall'anteprima al testo — la cella cliccata

Clicchi una cella nell'anteprima, il cursore va in quella cella
nell'editor.

Non è servito etichettare ogni cella nell'HTML. L'anteprima sa in che
posizione della sua riga sta la cella cliccata, la riga porta già il suo
offset di sorgente per la sincronizzazione dello scorrimento, e la
sorgente ha le stesse celle nello stesso ordine con le barre in mezzo: si
taglia la riga sulle barre non protette e si prende l'ennesimo pezzo.
Niente da tenere in step quando la tabella cambia.

Solo a selezione vuota. Trascinare dentro una tabella dell'anteprima è
qualcuno che sta copiando, e portargli via il fuoco a metà del gesto gli
butterebbe la selezione.

### La cella fantasma

Cercandola, ne è saltata fuori un'altra, introdotta con la
sincronizzazione per righe della 0.13.1: **l'intestazione di ogni tabella
nell'anteprima era spostata di una colonna** appena la barra «sei qui»
finiva su una riga di tabella.

La barra è uno `::before` in posizione assoluta. Su un paragrafo va bene;
su un `<tr>` no — una riga dispone i propri figli in celle, quindi il
browser ne fabbrica una anonima per contenerlo, e l'intestazione slitta a
destra di una colonna. Ora la riga appende la barra alla sua prima cella,
che è un blocco normale e la prende volentieri.

**La lezione.** Uno pseudo-elemento non è gratis: è un figlio, e in una
tabella i figli sono celle.

---

## Correzione — Il bordo del costrutto

Segnalazione, in una riga: «se metto il cursore all'inizio della parola, e
alla fine della parola, non compare il `_`, e così non posso cancellarlo o
modificarlo».

Ed era vero. Il ripristino guardava se il cursore era *strettamente
dentro* il costrutto, `location > inizio && location < fine`. Ma un
delimitatore nascosto non occupa spazio, quindi **l'inizio di `_pippo_` e
l'inizio di `pippo` sono lo stesso punto sullo schermo**: chi clicca
davanti alla parola atterra sul bordo, che non contava come dentro. Idem
dall'altra parte. I due soli posti dove uno va per toccare un underscore
erano i due posti dove restava invisibile.

Il difetto vero però era un altro, e più vecchio: **due parti del codice
credevano cose diverse**. La regola dello scavalcamento era scritta sulla
premessa «avvicinandosi a un costrutto lo si rivela, quindi un marcatore
non è mai insieme adiacente e nascosto» — premessa falsa ai bordi, dove il
ripristino non arrivava. Ognuna delle due parti era difendibile da sola.

La correzione è una disuguaglianza: `>=` e `<=`. Toccare basta.

E le altre due parti sono state riportate in riga con essa:

- **Il movimento** scavalca solo i marcatori *effettivamente* non
  disegnati. Arrivando a fianco di un costrutto ora lo si rivela davvero,
  quindi non c'è niente da scavalcare e il cursore cammina sui delimitatori
  uno alla volta — che è giusto, perché a quel punto li si vede.
- **La cancellazione** tratta il costrutto come una cosa sola solo finché
  i marcatori sono nascosti. Con l'asterisco in vista, il backspace su di
  esso è editing normale. È l'unico modo di *modificare* un delimitatore
  invece di poterlo solo togliere in blocco — `_pippo_` che diventa
  `__pippo__` senza cancellare niente.
- **La riga orizzontale** non viene disegnata sui trattini rivelati:
  altrimenti sarebbero il righello e il suo sorgente nello stesso punto.

Il prezzo è il collasso al delimitatore di chiusura, che era la ragione
per cui la regola stretta era stata scelta: ora un costrutto resta aperto
finché il cursore non se ne va, invece di chiudersi appena si batte
l'ultimo asterisco. È la sorpresa minore: **quello che è ancora sotto il
cursore è ancora in scrittura.** È anche quello che fanno Typora e
Obsidian.

Il ripristino guarda inoltre *tutti* gli intervalli selezionati, non solo
il primo: anche un secondo cursore è un posto dove qualcuno sta per
scrivere.

Undici test nuovi (`MPMarkerHiderTests`) fissano i bordi, perché è
esattamente il genere di cosa che si rompe senza che nessuno se ne accorga
finché non la usa.

**La lezione.** Quando una regola è scritta sulla premessa che *un'altra*
regola garantisce qualcosa, quella garanzia va verificata, non assunta —
e se cade, non cade solo lei.

---

## Dove andare da qui

Le fasi coprono il testo e le tabelle. Quello che resta smetterebbe di
essere testo, ed è in ordine di rapporto fra guadagno e rischio:

- **Le immagini in linea.** Un `![](…)` che mostra l'immagine.
  Tecnicamente è un allegato in un `NSTextAttachment`, cioè il primo
  posto in cui il testo dell'editor smetterebbe di essere solo testo:
  va disegnato, non inserito.
- **I diagrammi.** Stessa domanda delle immagini, con in più il fatto che
  il rendering sta nell'anteprima e passarlo all'editor significa
  renderizzare due volte.

E una cosa che *non* è un'estensione naturale: rendere modificabile
l'anteprima. Continua a essere l'unica strada che rompe la proprietà da
cui siamo partiti — vedi qui sotto.

---

## Cosa non fare

**Non rendere modificabile l'anteprima.** La conversione HTML→markdown è
lossy: un `<em>` non sa se era `*` o `_`, una tabella riformattata perde
l'allineamento scritto a mano. Ogni battuta rischierebbe di riscrivere il
file. È l'architettura che rende impossibile la proprietà da cui siamo
partiti.

**Non usare attributi temporanei per cambiare le dimensioni.** Sono
documentati come display-only: il font entra, e nulla viene reimpaginato.
Il carattere cambia senza che l'altezza della riga lo segua. Per le
dimensioni serve scrivere nel text storage — che comunque non finisce nel
file, perché il documento è la stringa.

**Non fidarsi di un tema che non hai letto.** Vale la pena ripeterlo: il
motivo per cui la fase 1 si è rivelata quasi già fatta è che avevo
guardato il *meccanismo* dell'evidenziatore e non i file di tema.

---

## Come misurare che una fase è finita

Non «sembra giusto». Per ogni fase:

1. **Il documento salvato è identico** prima e dopo averla accesa. È il
   controllo che protegge il principio di partenza — confronta i byte.
2. **Spegnendo la preferenza si torna esattamente a prima.** Se resta
   qualcosa, hai scritto dove non dovevi.
3. **Un documento senza quel costrutto non cambia di un pixel.** Ti
   accorgi degli effetti collaterali prima che diventino segnalazioni.

Per la fase 2 aggiungi: **muovere il cursore per tutto il documento con
le frecce non deve mai lasciare markup rivelato dove non c'è il cursore.**
È il difetto che si presenta per primo e si nota di più.

---

## Dove tenere d'occhio le interazioni

Tre cose in MacDown toccano lo stesso testo, e vanno considerate a ogni
fase:

- **Il prose checker** usa attributi temporanei per le sottolineature. Un
  `removeTemporaryAttribute:` troppo largo se le porta via.
- **La sincronizzazione dello scorrimento** mappa posizioni verticali
  dell'editor sui titoli dell'anteprima. Cambiare i corpi cambia le
  altezze: la mappatura regge, perché è basata su misure reali, ma va
  guardata.
- **`scrollsPastEnd`** calcola l'altezza del contenuto assumendo un font
  uniforme. Con corpi variabili va riprovato.
