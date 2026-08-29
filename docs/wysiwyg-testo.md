# WYSIWYG: la parte di testo

Una roadmap per arrivare a un editor che mostra quello che il testo
significa, senza smettere di essere un editor di markdown.

Il punto di partenza non è zero: due dei passi qui sotto sono già fatti e
sono segnati come tali. Quello che resta è, in ordine, il lavoro vero.

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

## Fase 2 — Far sparire i marcatori

**È qui che si decide se il progetto sta in piedi.** Tutto il resto è
lavoro; questa è la parte con le domande difficili.

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

---

## Fase 3 — L'impaginazione di blocco

Qui i temi non arrivano, e il guadagno visivo è alto rispetto al rischio.

- **Rientri delle liste**, con rientro sporgente sui capoversi successivi
- **Barra della citazione** nel margine
- **Spaziatura dei titoli**, più aria sopra che sotto
- **Righe orizzontali** disegnate invece che tre trattini

`NSParagraphStyle` copre rientri e spaziature. La barra della citazione e
la riga orizzontale vanno disegnate, in `drawViewBackgroundInRect:`.

Nessuno di questi tocca il cursore, quindi la fase è tranquilla. Un buon
posto dove andare se la fase 2 si è impantanata e serve un risultato.

---

## Fase 4 — Il comportamento in scrittura

Quello che trasforma «guarda come è bello» in «si scrive meglio».

- I marcatori collassano appena il costrutto è completo
- ⌘B e ⌘I si comportano da interruttori sulla selezione
- Incollare del testo formattato produce markdown, non testo semplice

Questa fase ha senso solo dopo la 2: senza sparizione dei marcatori,
collassarli non significa niente.

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
